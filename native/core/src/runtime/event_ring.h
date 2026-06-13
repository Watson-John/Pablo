// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// event_ring.h — bounded MPSC ring for photo_event_t.
//
// Many engine subsystems produce events (decode workers, ML pipeline,
// scheduler) but only the Dart event pump consumes them. M1 only needs
// correctness; the M2 milestone will replace this with a lock-free SPSC ring
// once we have one well-defined producer per event source.
//
// Drops events when full and bumps a dropped-counter; the engine surfaces
// PHOTO_EVT_LOG with the dropped count when capacity recovers.

#pragma once

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <vector>

#include "photo_core.h"

namespace photo {

class EventRing {
public:
    explicit EventRing(std::size_t capacity);

    // Push one event. Returns false if the ring is full; in that case the
    // event is dropped and dropped_count() is incremented.
    bool push(const photo_event_t& evt);

    // Drain up to `cap` events into `out`. Returns the number written.
    // Single-consumer expected.
    std::size_t pop_n(photo_event_t* out, std::size_t cap);

    std::uint64_t dropped_count() const;

private:
    mutable std::mutex             mu_;
    std::vector<photo_event_t>     buf_;
    std::size_t                    head_{0};   // next write index
    std::size_t                    tail_{0};   // next read index
    std::size_t                    size_{0};
    std::uint64_t                  dropped_{0};
};

}  // namespace photo
