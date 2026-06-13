// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "slot_store.h"

namespace photo {

uint64_t SlotStore::create(int32_t initial_w, int32_t initial_h) {
    const uint64_t id = next_id_.fetch_add(1, std::memory_order_relaxed);
    auto slot = std::make_unique<Slot>(id, initial_w, initial_h);
    std::lock_guard lk(mu_);
    slots_.emplace(id, std::move(slot));
    return id;
}

void SlotStore::destroy(uint64_t slot_id) {
    std::lock_guard lk(mu_);
    slots_.erase(slot_id);
}

Slot* SlotStore::get(uint64_t slot_id) {
    std::lock_guard lk(mu_);
    auto it = slots_.find(slot_id);
    return it == slots_.end() ? nullptr : it->second.get();
}

size_t SlotStore::size() const {
    std::lock_guard lk(mu_);
    return slots_.size();
}

}  // namespace photo
