// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "job_system.h"

#include <algorithm>
#include <utility>

namespace photo {

JobSystem::JobSystem(uint32_t worker_count) {
    worker_count = std::max(1u, worker_count);
    workers_.reserve(worker_count);
    for (uint32_t i = 0; i < worker_count; ++i) {
        workers_.emplace_back([this] { worker_loop(); });
    }
}

JobSystem::~JobSystem() {
    {
        std::lock_guard lk(mu_);
        stop_.store(true, std::memory_order_release);
    }
    cv_.notify_all();
    for (auto& t : workers_) {
        if (t.joinable()) t.join();
    }
}

JobSystem::Handle JobSystem::submit(int lane, JobFn fn) {
    if (lane < 0) lane = 0;
    if (lane > 2) lane = 2;

    Handle h;
    h.id = next_id_.fetch_add(1, std::memory_order_relaxed);
    h.cancelled = std::make_shared<std::atomic<bool>>(false);

    Item item;
    item.id = h.id;
    item.seq = next_seq_.fetch_add(1, std::memory_order_relaxed);
    item.cancelled = h.cancelled;
    item.fn = std::move(fn);

    {
        std::lock_guard lk(mu_);
        cancellable_.emplace(h.id, h.cancelled);
        lanes_[lane].emplace_back(std::move(item));
    }
    cv_.notify_one();
    return h;
}

void JobSystem::cancel(uint64_t id) {
    std::shared_ptr<std::atomic<bool>> flag;
    {
        std::lock_guard lk(mu_);
        auto it = cancellable_.find(id);
        if (it == cancellable_.end()) return;
        flag = it->second;
    }
    if (flag) flag->store(true, std::memory_order_release);
}

size_t JobSystem::pending() const {
    std::lock_guard lk(mu_);
    return lanes_[0].size() + lanes_[1].size() + lanes_[2].size();
}

bool JobSystem::pop_next_locked(Item* out) {
    for (int lane = 0; lane < 3; ++lane) {
        if (!lanes_[lane].empty()) {
            *out = std::move(lanes_[lane].front());
            lanes_[lane].pop_front();
            return true;
        }
    }
    return false;
}

void JobSystem::worker_loop() {
    while (true) {
        Item item;
        bool have_item = false;
        {
            std::unique_lock lk(mu_);
            cv_.wait(lk, [this] {
                return stop_.load(std::memory_order_acquire) ||
                       lanes_[0].size() + lanes_[1].size() + lanes_[2].size() > 0;
            });
            if (stop_.load(std::memory_order_acquire) &&
                lanes_[0].empty() && lanes_[1].empty() && lanes_[2].empty()) {
                return;
            }
            have_item = pop_next_locked(&item);
            if (have_item) {
                cancellable_.erase(item.id);
            }
        }
        if (!have_item) continue;

        // Check cancellation outside the lock. The flag may have been set
        // between submit and pop; worker honors it then.
        if (item.cancelled->load(std::memory_order_acquire)) {
            continue;
        }
        try {
            item.fn();
        } catch (...) {
            // Swallow — exceptions must never cross thread boundaries here.
            // The job is expected to translate failures into PHOTO_EVT_*_FAILED.
        }
    }
}

}  // namespace photo
