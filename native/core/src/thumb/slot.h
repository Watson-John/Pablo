// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// slot.h — a render slot in the native core.
//
// A slot pairs 1:1 with a Flutter Texture registration owned by the
// photo_native plugin. Stage upgrades swap the underlying FrameBuffer; the
// plugin's texture registration never changes for the slot's lifetime
// (DECISIONS.md §D7).
//
// FRAME OWNERSHIP MODEL
// =====================
// The slot holds a shared_ptr<const FrameBuffer> as the current presentable
// frame ("front"). Publishing replaces front_ under a small lock; the old
// front_ is released by the producer's shared_ptr drop.
//
// The texture callback path borrows via acquire_view() which copies the
// shared_ptr into a heap-allocated FrameHolder and returns its raw pointer
// as release_ctx through the C ABI. release_view() destroys the holder,
// dropping the borrower's refcount. This guarantees the pixel memory stays
// valid for the borrow's duration even if the producer swaps mid-callback.
//
// M1: each publish_solid_color allocates a fresh FrameBuffer. M3 replaces
// this with a recycle pool to amortize allocation cost under sustained
// scroll. The shared_ptr contract above does not change.

#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

#include "photo_core.h"

namespace photo {

struct FrameBuffer {
    std::vector<uint8_t> bgra;     // width * height * 4, premultiplied alpha
    uint32_t width  {0};
    uint32_t height {0};
    uint32_t stride {0};            // bytes per row, >= width * 4
};

using FramePtr = std::shared_ptr<const FrameBuffer>;

// Heap holder returned through release_ctx. Keeps a strong refcount on the
// borrowed frame; release destroys it.
struct FrameHolder {
    FramePtr frame;
};

class Slot {
public:
    Slot(uint64_t id, int32_t initial_w, int32_t initial_h);

    uint64_t id() const noexcept { return id_; }

    // Returns previous generation.
    uint64_t bind_generation(uint64_t gen) noexcept;
    uint64_t current_generation() const noexcept {
        return generation_.load(std::memory_order_acquire);
    }

    // Default dimensions for solid-color publishes when the caller doesn't
    // specify. Used by the M1 texture-harness plumbing.
    uint32_t initial_w() const noexcept { return initial_w_; }
    uint32_t initial_h() const noexcept { return initial_h_; }

    // Publish a solid color as the new front frame. Thread-safe.
    // M1 plumbing only; real publishes come from the compositor in M3.
    void publish_solid_color(uint8_t b, uint8_t g, uint8_t r, uint8_t a);

    // Publish a fully-decoded frame (premultiplied BGRA) as the new front
    // frame. Thread-safe. Used by the M3 libvips decode path.
    void publish_frame(FramePtr frame);

    // Borrow the latest front frame. Returns nullptr if no frame has been
    // published. The returned shared_ptr keeps the pixel memory alive for
    // the caller's use; the caller drops it (via release_view) to free.
    FramePtr acquire_view() noexcept;

private:
    const uint64_t          id_;
    const uint32_t          initial_w_;
    const uint32_t          initial_h_;

    std::atomic<uint64_t>   generation_{0};

    mutable std::mutex      front_mu_;
    FramePtr                front_;   // guarded by front_mu_
};

}  // namespace photo
