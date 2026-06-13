// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// slot_store.h — registry of active slots.
//
// Slots are created and destroyed by the photo_native plugin in response to
// Flutter widget lifecycle. The store assigns monotonic IDs and tracks the
// Slot objects under a single mutex (low contention; calls are infrequent
// relative to per-frame work).

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <unordered_map>

#include "thumb/slot.h"

namespace photo {

class SlotStore {
public:
    uint64_t create(int32_t initial_w, int32_t initial_h);
    void     destroy(uint64_t slot_id);

    // Returns nullptr if the slot does not exist or has been destroyed.
    Slot* get(uint64_t slot_id);

    size_t size() const;

private:
    mutable std::mutex                                   mu_;
    std::unordered_map<uint64_t, std::unique_ptr<Slot>>  slots_;
    std::atomic<uint64_t>                                next_id_{1};
};

}  // namespace photo
