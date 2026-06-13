// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "slot.h"

#include <algorithm>

namespace photo {

namespace {

constexpr uint32_t kSafeDimMin = 1u;
constexpr uint32_t kSafeDimMax = 16384u;

uint32_t clamp_dim(int32_t v, uint32_t fallback) noexcept {
    if (v <= 0) return fallback;
    auto uv = static_cast<uint32_t>(v);
    if (uv < kSafeDimMin) return kSafeDimMin;
    if (uv > kSafeDimMax) return kSafeDimMax;
    return uv;
}

}  // namespace

Slot::Slot(uint64_t id, int32_t initial_w, int32_t initial_h)
    : id_(id),
      initial_w_(clamp_dim(initial_w, 256u)),
      initial_h_(clamp_dim(initial_h, 256u)) {}

uint64_t Slot::bind_generation(uint64_t gen) noexcept {
    return generation_.exchange(gen, std::memory_order_acq_rel);
}

void Slot::publish_solid_color(uint8_t b, uint8_t g, uint8_t r, uint8_t a) {
    // Allocate outside any lock — this is the bulk of the work.
    auto fb = std::make_shared<FrameBuffer>();
    fb->width  = initial_w_;
    fb->height = initial_h_;
    fb->stride = fb->width * 4;
    fb->bgra.assign(static_cast<size_t>(fb->stride) * fb->height, 0);

    // Pre-multiplied alpha (alpha = 255 here so values are unchanged).
    const uint8_t pb = static_cast<uint8_t>((b * a + 127) / 255);
    const uint8_t pg = static_cast<uint8_t>((g * a + 127) / 255);
    const uint8_t pr = static_cast<uint8_t>((r * a + 127) / 255);

    uint8_t* p = fb->bgra.data();
    const size_t pixels = static_cast<size_t>(fb->width) * fb->height;
    for (size_t i = 0; i < pixels; ++i) {
        p[i * 4 + 0] = pb;
        p[i * 4 + 1] = pg;
        p[i * 4 + 2] = pr;
        p[i * 4 + 3] = a;
    }

    {
        std::lock_guard lk(front_mu_);
        front_ = std::move(fb);
    }
}

FramePtr Slot::acquire_view() noexcept {
    std::lock_guard lk(front_mu_);
    return front_;  // copies the shared_ptr (refcount +1)
}

}  // namespace photo
