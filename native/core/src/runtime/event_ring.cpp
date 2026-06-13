// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "event_ring.h"

#include <algorithm>
#include <cstring>

namespace photo {

EventRing::EventRing(std::size_t capacity) : buf_(capacity) {}

bool EventRing::push(const photo_event_t& evt) {
    std::lock_guard lk(mu_);
    if (size_ == buf_.size()) {
        ++dropped_;
        return false;
    }
    buf_[head_] = evt;
    head_ = (head_ + 1) % buf_.size();
    ++size_;
    return true;
}

std::size_t EventRing::pop_n(photo_event_t* out, std::size_t cap) {
    if (cap == 0) return 0;
    std::lock_guard lk(mu_);
    std::size_t n = std::min(cap, size_);
    for (std::size_t i = 0; i < n; ++i) {
        out[i] = buf_[tail_];
        tail_ = (tail_ + 1) % buf_.size();
    }
    size_ -= n;
    return n;
}

std::uint64_t EventRing::dropped_count() const {
    std::lock_guard lk(mu_);
    return dropped_;
}

}  // namespace photo
