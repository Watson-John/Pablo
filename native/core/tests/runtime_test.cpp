// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// runtime_test.cpp — white-box tests for the runtime primitives that until
// now were only exercised indirectly through the C ABI: JobSystem (3 priority
// lanes + advisory cancel), EventRing (bounded MPSC ring, drop-new overflow),
// and SlotStore/Slot (id registry, generation tokens, frame publish/borrow).
// Linked against photo_core_objects; src/ is on the include path.

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <vector>

#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"
#include "thumb/slot.h"

using photo::EventRing;
using photo::JobSystem;
using photo::Slot;
using photo::SlotStore;

namespace {

// Bounded wait for an arbitrary condition. All waits in this file are bounded
// so a regression fails the test instead of hanging the suite.
bool wait_until(const std::function<bool()>& pred,
                std::chrono::milliseconds timeout = std::chrono::seconds(5)) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (!pred()) {
        if (std::chrono::steady_clock::now() > deadline) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return true;
}

// Minimal manual-reset gate (std::latch is C++20; keep the dependency low).
class Gate {
public:
    void open() {
        {
            std::lock_guard lk(mu_);
            open_ = true;
        }
        cv_.notify_all();
    }
    void wait() {
        std::unique_lock lk(mu_);
        cv_.wait(lk, [this] { return open_; });
    }

private:
    std::mutex              mu_;
    std::condition_variable cv_;
    bool                    open_{false};
};

photo_event_t make_event(uint64_t request_id) {
    photo_event_t e{};
    e.kind       = 7;
    e.stage      = 2;
    e.status     = -3;
    e.width      = 640;
    e.height     = 480;
    e.request_id = request_id;
    e.asset_id   = 0xA55E7'0000ull + request_id;
    e.slot_id    = 0x510Full;
    e.generation = 99;
    e.aux64      = 0xDEADBEEFCAFEF00Dull;
    e.aux64_b    = 0x0123456789ABCDEFull;
    return e;
}

}  // namespace

/* ------------------------------------------------------------------------ */
/* JobSystem                                                                 */
/* ------------------------------------------------------------------------ */

// Jobs submitted on all three lanes all execute, and out-of-range lanes are
// clamped into [0, 2] rather than rejected.
TEST(JobSystemTest, JobsOnAllLanesRun) {
    JobSystem jobs(2);
    std::atomic<int> ran{0};

    auto h0 = jobs.submit(PHOTO_PRIORITY_INTERACTIVE, [&] { ran.fetch_add(1); });
    auto h1 = jobs.submit(PHOTO_PRIORITY_VIEWPORT, [&] { ran.fetch_add(1); });
    auto h2 = jobs.submit(PHOTO_PRIORITY_IDLE, [&] { ran.fetch_add(1); });
    // Lane is documented as clamped to [0, 2]; these must run, not vanish.
    auto h3 = jobs.submit(-5, [&] { ran.fetch_add(1); });
    auto h4 = jobs.submit(99, [&] { ran.fetch_add(1); });

    // Handles carry unique ids and a live (unset) cancellation token.
    EXPECT_NE(h0.id, 0u);
    EXPECT_NE(h0.id, h1.id);
    EXPECT_NE(h1.id, h2.id);
    EXPECT_NE(h3.id, h4.id);
    ASSERT_NE(h0.cancelled, nullptr);
    EXPECT_FALSE(h0.cancelled->load());

    EXPECT_TRUE(wait_until([&] { return ran.load() == 5; }));
    EXPECT_TRUE(wait_until([&] { return jobs.pending() == 0; }));
}

// With a single worker pinned by a gate job, an interactive job submitted
// AFTER a pile of idle jobs must still be the first thing the worker runs
// once the gate opens (pop scans lane 0 first). This pins the anti-starvation
// property of the lane order.
TEST(JobSystemTest, InteractiveJobNotStarvedByIdleBacklog) {
    JobSystem jobs(1);

    Gate gate;
    std::atomic<bool> gate_running{false};
    jobs.submit(PHOTO_PRIORITY_IDLE, [&] {
        gate_running.store(true);
        gate.wait();
    });
    ASSERT_TRUE(wait_until([&] { return gate_running.load(); }));

    // Worker is now blocked; everything below queues up behind the gate.
    std::mutex order_mu;
    std::vector<int> order;
    auto record = [&](int tag) {
        std::lock_guard lk(order_mu);
        order.push_back(tag);
    };

    constexpr int kIdleJobs = 64;
    for (int i = 0; i < kIdleJobs; ++i) {
        jobs.submit(PHOTO_PRIORITY_IDLE, [&record] { record(2); });
    }
    jobs.submit(PHOTO_PRIORITY_INTERACTIVE, [&record] { record(0); });

    gate.open();
    ASSERT_TRUE(wait_until([&] {
        std::lock_guard lk(order_mu);
        return order.size() == kIdleJobs + 1;
    }));

    std::lock_guard lk(order_mu);
    // The interactive job ran before every one of the 64 earlier-queued idle
    // jobs — with one worker this is deterministic, not just "eventually".
    ASSERT_FALSE(order.empty());
    EXPECT_EQ(order.front(), 0);
}

// cancel(id) on a queued (not-yet-started) job flips the handle's shared
// token and the worker skips execution. cancel of an unknown id is a no-op.
TEST(JobSystemTest, CancelPreventsQueuedJobFromRunning) {
    JobSystem jobs(1);

    Gate gate;
    std::atomic<bool> gate_running{false};
    jobs.submit(PHOTO_PRIORITY_IDLE, [&] {
        gate_running.store(true);
        gate.wait();
    });
    ASSERT_TRUE(wait_until([&] { return gate_running.load(); }));

    std::atomic<bool> victim_ran{false};
    auto victim = jobs.submit(PHOTO_PRIORITY_IDLE, [&] { victim_ran.store(true); });

    jobs.cancel(victim.id);
    EXPECT_TRUE(victim.cancelled->load());  // advisory flag is shared with the handle

    jobs.cancel(0xFFFFFFFFFFFFull);  // unknown id: documented no-op, must not crash

    // A sentinel queued after the victim; when it has run, the worker has
    // already popped (and skipped) the cancelled victim ahead of it.
    std::atomic<bool> sentinel_ran{false};
    jobs.submit(PHOTO_PRIORITY_IDLE, [&] { sentinel_ran.store(true); });

    gate.open();
    ASSERT_TRUE(wait_until([&] { return sentinel_ran.load(); }));
    EXPECT_FALSE(victim_ran.load());
}

// A job that throws must be swallowed by the worker (exceptions never cross
// the thread boundary) and must not take the worker down.
TEST(JobSystemTest, ThrowingJobDoesNotKillWorker) {
    JobSystem jobs(1);

    jobs.submit(PHOTO_PRIORITY_IDLE, [] { throw std::runtime_error("boom"); });

    std::atomic<bool> after_ran{false};
    jobs.submit(PHOTO_PRIORITY_IDLE, [&] { after_ran.store(true); });

    EXPECT_TRUE(wait_until([&] { return after_ran.load(); }));
}

// Destruction drains: the worker loop only exits once stop is set AND all
// lanes are empty, so jobs queued before the destructor still execute. This
// pins current behavior (callers rely on submitted work not being dropped).
TEST(JobSystemTest, DestructorDrainsQueuedJobs) {
    std::atomic<int> ran{0};
    constexpr int kJobs = 32;
    {
        JobSystem jobs(1);
        for (int i = 0; i < kJobs; ++i) {
            jobs.submit(PHOTO_PRIORITY_IDLE, [&] { ran.fetch_add(1); });
        }
        // Destructor runs here, joining the worker after the lanes empty.
    }
    EXPECT_EQ(ran.load(), kJobs);
}

/* ------------------------------------------------------------------------ */
/* EventRing                                                                 */
/* ------------------------------------------------------------------------ */

// A pushed event comes back with every field intact.
TEST(EventRingTest, PushPopRoundTripsAllFields) {
    EventRing ring(8);

    const photo_event_t in = make_event(41);
    EXPECT_TRUE(ring.push(in));

    photo_event_t out[2] = {};
    ASSERT_EQ(ring.pop_n(out, 2), 1u);

    EXPECT_EQ(out[0].kind, in.kind);
    EXPECT_EQ(out[0].stage, in.stage);
    EXPECT_EQ(out[0].status, in.status);
    EXPECT_EQ(out[0].width, in.width);
    EXPECT_EQ(out[0].height, in.height);
    EXPECT_EQ(out[0].request_id, in.request_id);
    EXPECT_EQ(out[0].asset_id, in.asset_id);
    EXPECT_EQ(out[0].slot_id, in.slot_id);
    EXPECT_EQ(out[0].generation, in.generation);
    EXPECT_EQ(out[0].aux64, in.aux64);
    EXPECT_EQ(out[0].aux64_b, in.aux64_b);

    EXPECT_EQ(ring.pop_n(out, 2), 0u);  // drained
    EXPECT_EQ(ring.dropped_count(), 0u);
}

// Overflow policy is DROP-NEW: when full, push returns false, the incoming
// event is discarded, dropped_count() increments, and the events already in
// the ring are preserved in FIFO order. (Not drop-oldest.)
TEST(EventRingTest, OverflowDropsNewIncrementsCounterKeepsOldest) {
    EventRing ring(4);

    for (uint64_t i = 1; i <= 4; ++i) {
        EXPECT_TRUE(ring.push(make_event(i)));
    }
    // Ring is full: these two must be rejected and counted.
    EXPECT_FALSE(ring.push(make_event(5)));
    EXPECT_FALSE(ring.push(make_event(6)));
    EXPECT_EQ(ring.dropped_count(), 2u);

    photo_event_t out[8] = {};
    ASSERT_EQ(ring.pop_n(out, 8), 4u);
    for (uint64_t i = 0; i < 4; ++i) {
        EXPECT_EQ(out[i].request_id, i + 1) << "survivors are the OLDEST, in FIFO order";
    }

    // Capacity recovered: pushes succeed again; dropped counter is cumulative.
    EXPECT_TRUE(ring.push(make_event(7)));
    ASSERT_EQ(ring.pop_n(out, 8), 1u);
    EXPECT_EQ(out[0].request_id, 7u);
    EXPECT_EQ(ring.dropped_count(), 2u);
}

// pop_n with a small buffer returns at most `cap` events and leaves the rest
// queued for the next drain; cap == 0 is a safe no-op.
TEST(EventRingTest, PopNSmallBufferDrainsPartially) {
    EventRing ring(8);
    for (uint64_t i = 1; i <= 5; ++i) {
        ASSERT_TRUE(ring.push(make_event(i)));
    }

    photo_event_t out[8] = {};
    EXPECT_EQ(ring.pop_n(out, 0), 0u);

    ASSERT_EQ(ring.pop_n(out, 2), 2u);
    EXPECT_EQ(out[0].request_id, 1u);
    EXPECT_EQ(out[1].request_id, 2u);

    ASSERT_EQ(ring.pop_n(out, 8), 3u);
    EXPECT_EQ(out[0].request_id, 3u);
    EXPECT_EQ(out[1].request_id, 4u);
    EXPECT_EQ(out[2].request_id, 5u);

    EXPECT_EQ(ring.pop_n(out, 8), 0u);
    EXPECT_EQ(ring.dropped_count(), 0u);
}

// Wrap-around: interleaved push/pop past the physical end of the buffer keeps
// FIFO order (indices wrap modulo capacity). Each round drains what it pushed,
// so a capacity-4 ring never fills while head/tail walk around it three times
// (12 events through 4 slots).
TEST(EventRingTest, WrapAroundPreservesFifoOrder) {
    EventRing ring(4);
    photo_event_t out[4] = {};
    uint64_t next_push = 1, next_pop = 1;

    for (int round = 0; round < 4; ++round) {
        for (int i = 0; i < 3; ++i)
            ASSERT_TRUE(ring.push(make_event(next_push++))) << "round " << round;
        ASSERT_EQ(ring.pop_n(out, 4), 3u) << "round " << round;
        EXPECT_EQ(out[0].request_id, next_pop++);
        EXPECT_EQ(out[1].request_id, next_pop++);
        EXPECT_EQ(out[2].request_id, next_pop++);
    }
    EXPECT_EQ(ring.pop_n(out, 4), 0u);
    EXPECT_EQ(next_pop, next_push);
    EXPECT_EQ(ring.dropped_count(), 0u);
}

/* ------------------------------------------------------------------------ */
/* SlotStore + Slot                                                          */
/* ------------------------------------------------------------------------ */

// create → get returns the live slot; destroy → get returns nullptr. Ids are
// non-zero and unique; destroying an unknown id is a safe no-op.
TEST(SlotStoreTest, CreateGetDestroyLifecycle) {
    SlotStore store;
    EXPECT_EQ(store.size(), 0u);

    const uint64_t a = store.create(128, 64);
    const uint64_t b = store.create(32, 32);
    EXPECT_NE(a, 0u);
    EXPECT_NE(b, 0u);
    EXPECT_NE(a, b);
    EXPECT_EQ(store.size(), 2u);

    Slot* sa = store.get(a);
    ASSERT_NE(sa, nullptr);
    EXPECT_EQ(sa->id(), a);
    EXPECT_EQ(sa->initial_w(), 128u);
    EXPECT_EQ(sa->initial_h(), 64u);

    store.destroy(a);
    EXPECT_EQ(store.get(a), nullptr);
    EXPECT_EQ(store.size(), 1u);
    ASSERT_NE(store.get(b), nullptr);

    store.destroy(0xFFFFFFFFull);  // unknown id: no-op
    EXPECT_EQ(store.size(), 1u);

    store.destroy(b);
    EXPECT_EQ(store.size(), 0u);
}

// Non-positive creation dims fall back to 256; oversized dims clamp to the
// 16384 safety ceiling (slot.cpp clamp_dim).
TEST(SlotStoreTest, CreationDimensionsAreSanitized) {
    SlotStore store;

    Slot* fallback = store.get(store.create(0, -7));
    ASSERT_NE(fallback, nullptr);
    EXPECT_EQ(fallback->initial_w(), 256u);
    EXPECT_EQ(fallback->initial_h(), 256u);

    Slot* clamped = store.get(store.create(1 << 20, 20000));
    ASSERT_NE(clamped, nullptr);
    EXPECT_EQ(clamped->initial_w(), 16384u);
    EXPECT_EQ(clamped->initial_h(), 16384u);
}

// Generation tokens: a fresh slot starts at gen 0; bind_generation swaps in
// the new token and returns the previous one (the compare point publishers
// use to suppress stale results).
TEST(SlotStoreTest, GenerationBindReturnsPrevious) {
    SlotStore store;
    Slot* slot = store.get(store.create(64, 64));
    ASSERT_NE(slot, nullptr);

    EXPECT_EQ(slot->current_generation(), 0u);
    EXPECT_EQ(slot->bind_generation(42), 0u);
    EXPECT_EQ(slot->current_generation(), 42u);
    EXPECT_EQ(slot->bind_generation(43), 42u);
    EXPECT_EQ(slot->current_generation(), 43u);
}

// Frame publish/borrow without any real texture: acquire_view() is null
// before the first publish; publish_solid_color produces a premultiplied
// BGRA frame at the slot's initial dimensions; a borrowed view stays valid
// (same bytes) after a newer frame is published over it.
TEST(SlotStoreTest, PublishSolidColorAndBorrowedViewSurvivesRepublish) {
    SlotStore store;
    Slot* slot = store.get(store.create(4, 3));
    ASSERT_NE(slot, nullptr);

    EXPECT_EQ(slot->acquire_view(), nullptr);  // nothing published yet

    slot->publish_solid_color(/*b=*/10, /*g=*/20, /*r=*/30, /*a=*/255);
    photo::FramePtr v1 = slot->acquire_view();
    ASSERT_NE(v1, nullptr);
    EXPECT_EQ(v1->width, 4u);
    EXPECT_EQ(v1->height, 3u);
    EXPECT_EQ(v1->stride, 16u);  // width * 4
    ASSERT_EQ(v1->bgra.size(), static_cast<size_t>(v1->stride) * v1->height);
    // Opaque alpha: premultiply is identity.
    EXPECT_EQ(v1->bgra[0], 10u);
    EXPECT_EQ(v1->bgra[1], 20u);
    EXPECT_EQ(v1->bgra[2], 30u);
    EXPECT_EQ(v1->bgra[3], 255u);

    // Half-transparent publish: channels are stored premultiplied,
    // round-to-nearest ((c * a + 127) / 255).
    slot->publish_solid_color(/*b=*/100, /*g=*/200, /*r=*/50, /*a=*/128);
    photo::FramePtr v2 = slot->acquire_view();
    ASSERT_NE(v2, nullptr);
    EXPECT_NE(v2, v1);          // a publish swaps in a fresh FrameBuffer
    EXPECT_EQ(v2->bgra[0], 50u);   // (100*128+127)/255
    EXPECT_EQ(v2->bgra[1], 100u);  // (200*128+127)/255
    EXPECT_EQ(v2->bgra[2], 25u);   // ( 50*128+127)/255
    EXPECT_EQ(v2->bgra[3], 128u);

    // The old borrow is untouched by the republish: the shared_ptr keeps the
    // first buffer alive with its original bytes (borrow-safety contract the
    // texture callback relies on).
    EXPECT_EQ(v1->bgra[0], 10u);
    EXPECT_EQ(v1->bgra[3], 255u);

    // publish_frame path: hand-built frame becomes the new front.
    auto fb = std::make_shared<photo::FrameBuffer>();
    fb->width = 1;
    fb->height = 1;
    fb->stride = 4;
    fb->bgra = {1, 2, 3, 4};
    slot->publish_frame(fb);
    photo::FramePtr v3 = slot->acquire_view();
    ASSERT_NE(v3, nullptr);
    EXPECT_EQ(v3.get(), fb.get());
    EXPECT_EQ(v3->bgra[2], 3u);
}
