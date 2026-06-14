// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// job_system.h — fixed-size worker pool with 3 priority lanes and O(1)
// cancellation.
//
// Lanes (lower = more urgent):
//   0 = PHOTO_PRIORITY_INTERACTIVE  (visible-now placeholders)
//   1 = PHOTO_PRIORITY_VIEWPORT     (in-viewport thumbs + short prefetch)
//   2 = PHOTO_PRIORITY_IDLE         (background prefetch / recache)
//
// Cancellation is advisory: each enqueued job holds a shared_ptr to an
// `atomic<bool> cancelled` flag. cancel(id) flips the flag; the worker
// checks it after pop and skips execution. Already-running jobs run to
// completion (they will not produce a visible result because the caller
// also checks the slot's generation token before publishing).
//
// Performance: no lock-free magic; one mutex protects the lanes. M2's
// submit-side cost is dominated by lock + push, both ~100ns on modern
// hardware. The 50µs FFI hot-path budget allows for that comfortably.

#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

namespace photo {

class JobSystem {
public:
    using JobFn = std::function<void()>;

    // A cancellable handle. Returned by submit(). The cancellation token is
    // a shared_ptr so the worker can read it even after the JobSystem map
    // entry is gone (lifetime extension during execution).
    struct Handle {
        uint64_t                              id{0};
        std::shared_ptr<std::atomic<bool>>    cancelled;
    };

    explicit JobSystem(uint32_t worker_count);
    ~JobSystem();

    JobSystem(const JobSystem&)            = delete;
    JobSystem& operator=(const JobSystem&) = delete;

    // Submit a job at the given priority lane. Returns a handle whose id is
    // unique within this JobSystem's lifetime. Lane is clamped to [0, 2].
    Handle submit(int lane, JobFn fn);

    // Mark a previously submitted job as cancelled. Safe with unknown ids
    // (no-op). Does not block on running jobs.
    void cancel(uint64_t id);

    // Best-effort queue depth, all lanes combined. Cheap (single lock).
    size_t pending() const;

private:
    struct Item {
        uint64_t                            id;
        uint64_t                            seq;      // FIFO tiebreak per lane
        std::shared_ptr<std::atomic<bool>>  cancelled;
        JobFn                               fn;
    };

    void worker_loop();
    bool pop_next_locked(Item* out);

    mutable std::mutex                                          mu_;
    std::condition_variable                                     cv_;
    std::deque<Item>                                            lanes_[3];
    std::unordered_map<uint64_t, std::shared_ptr<std::atomic<bool>>>
                                                                cancellable_;
    std::vector<std::thread>                                    workers_;
    std::atomic<uint64_t>                                       next_id_{1};
    std::atomic<uint64_t>                                       next_seq_{1};
    std::atomic<bool>                                           stop_{false};
};

}  // namespace photo
