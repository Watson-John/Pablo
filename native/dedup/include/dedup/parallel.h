// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Minimal parallel-for over an index range. The pipeline is decode/IO-bound, so
// a plain static-chunked std::thread fan-out is plenty — no work-stealing pool
// warranted. `body(i)` must be thread-safe across distinct i.

#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <functional>
#include <thread>
#include <vector>

namespace dedup {

// Invoke body(i) for i in [0, n) across `threads` workers (clamped to [1, n]).
// Uses an atomic cursor so uneven per-item cost (e.g. RAW vs JPEG decode) still
// load-balances. Blocks until all items complete.
inline void parallel_for(size_t n, int threads, const std::function<void(size_t)>& body) {
    if (n == 0) return;
    if (threads <= 0) {
        unsigned hc = std::thread::hardware_concurrency();
        threads = hc > 0 ? static_cast<int>(hc) : 4;
    }
    int t = std::max(1, threads);
    t = static_cast<int>(std::min<size_t>(static_cast<size_t>(t), n));
    if (t == 1) {
        for (size_t i = 0; i < n; ++i) body(i);
        return;
    }
    std::atomic<size_t> cursor{0};
    std::vector<std::thread> pool;
    pool.reserve(t);
    for (int w = 0; w < t; ++w) {
        pool.emplace_back([&] {
            for (;;) {
                size_t i = cursor.fetch_add(1, std::memory_order_relaxed);
                if (i >= n) break;
                body(i);
            }
        });
    }
    for (auto& th : pool) th.join();
}

}  // namespace dedup
