// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "thumb/thumb_service.h"

#include <cstring>
#include <utility>

namespace photo {

namespace {

// FNV-1a 64-bit hash of the path. Deterministic across runs so the same
// photo always renders the same M2 synthetic color — useful for visual
// inspection in the gallery.
uint64_t fnv1a_64(const char* s, size_t n) {
    constexpr uint64_t kPrime = 0x100000001b3ULL;
    uint64_t h = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < n; ++i) {
        h ^= static_cast<uint8_t>(s[i]);
        h *= kPrime;
    }
    return h;
}

struct Bgra { uint8_t b, g, r, a; };

// Map (path, stage) to a stable BGRA color. Stage modulates brightness so
// the placeholder / thumb / full transitions are visually obvious during
// M2 testing. Replaced by real decoding in M3.
Bgra synthetic_color(const std::string& path, uint32_t stage) {
    uint64_t h = fnv1a_64(path.data(), path.size());
    uint8_t r = static_cast<uint8_t>((h >>  0) & 0xff);
    uint8_t g = static_cast<uint8_t>((h >>  8) & 0xff);
    uint8_t b = static_cast<uint8_t>((h >> 16) & 0xff);

    float brightness = 1.0f;
    switch (stage) {
        case PHOTO_STAGE_PLACEHOLDER32: brightness = 0.45f; break;
        case PHOTO_STAGE_THUMB256:      brightness = 0.85f; break;
        case PHOTO_STAGE_FULL:          brightness = 1.00f; break;
    }

    auto scale = [brightness](uint8_t v) {
        float f = static_cast<float>(v) * brightness + 24.0f;  // +24 floor
        if (f > 255.0f) f = 255.0f;
        return static_cast<uint8_t>(f);
    };
    return Bgra{scale(b), scale(g), scale(r), 255};
}

}  // namespace

ThumbService::ThumbService(SlotStore* slots, EventRing* events, JobSystem* jobs)
    : slots_(slots), events_(events), jobs_(jobs) {}

uint64_t ThumbService::submit(uint64_t asset_id,
                              uint64_t slot_id,
                              uint64_t generation,
                              const char* path_utf8,
                              uint32_t target_w,
                              uint32_t target_h,
                              uint32_t wanted_stages_mask,
                              uint32_t priority) {
    if (slot_id == 0)              return 0;
    if (wanted_stages_mask == 0)   return 0;
    if (slots_->get(slot_id) == nullptr) return 0;

    const uint64_t request_id =
        next_request_id_.fetch_add(1, std::memory_order_relaxed);
    std::string path = path_utf8 ? std::string(path_utf8) : std::string{};

    auto handle = jobs_->submit(
        static_cast<int>(priority),
        [this, request_id, asset_id, slot_id, generation, p = std::move(path),
         target_w, target_h, wanted_stages_mask]() mutable {
            run_synthetic(request_id, asset_id, slot_id, generation,
                          std::move(p), target_w, target_h,
                          wanted_stages_mask);
            // Drop our cancellation entry now that the job is running.
            std::lock_guard lk(req_mu_);
            request_to_job_.erase(request_id);
        });

    {
        std::lock_guard lk(req_mu_);
        request_to_job_.emplace(request_id, handle.id);
    }
    return request_id;
}

void ThumbService::cancel(uint64_t request_id) {
    if (request_id == 0) return;
    uint64_t job_id = 0;
    {
        std::lock_guard lk(req_mu_);
        auto it = request_to_job_.find(request_id);
        if (it == request_to_job_.end()) return;
        job_id = it->second;
        request_to_job_.erase(it);
    }
    jobs_->cancel(job_id);
}

void ThumbService::publish_stage_for_path(Slot& slot,
                                          uint32_t stage,
                                          const std::string& path) {
    Bgra c = synthetic_color(path, stage);
    slot.publish_solid_color(c.b, c.g, c.r, c.a);
}

void ThumbService::emit_stage_ready(uint64_t request_id,
                                    uint64_t asset_id,
                                    uint64_t slot_id,
                                    uint64_t generation,
                                    uint32_t stage,
                                    uint32_t width,
                                    uint32_t height) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_STAGE_READY;
    e.stage = stage;
    e.status = PHOTO_STATUS_OK;
    e.width = width;
    e.height = height;
    e.request_id = request_id;
    e.asset_id = asset_id;
    e.slot_id = slot_id;
    e.generation = generation;
    events_->push(e);
}

void ThumbService::emit_stage_failed(uint64_t request_id,
                                     uint64_t asset_id,
                                     uint64_t slot_id,
                                     uint64_t generation,
                                     uint32_t stage,
                                     int32_t status) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_STAGE_FAILED;
    e.stage = stage;
    e.status = status;
    e.request_id = request_id;
    e.asset_id = asset_id;
    e.slot_id = slot_id;
    e.generation = generation;
    events_->push(e);
}

void ThumbService::run_synthetic(uint64_t request_id,
                                 uint64_t asset_id,
                                 uint64_t slot_id,
                                 uint64_t generation,
                                 std::string path,
                                 uint32_t target_w,
                                 uint32_t target_h,
                                 uint32_t wanted_stages_mask) {
    (void)target_w;
    (void)target_h;

    auto* slot = slots_->get(slot_id);
    if (slot == nullptr) {
        emit_stage_failed(request_id, asset_id, slot_id, generation,
                          0, PHOTO_STATUS_NOT_FOUND);
        return;
    }
    // Drop stale generations silently — this is the normal consequence of
    // rapid scroll-rebinding, not an error.
    if (slot->current_generation() != generation) {
        return;
    }

    constexpr uint32_t kStages[] = {
        PHOTO_STAGE_PLACEHOLDER32,
        PHOTO_STAGE_THUMB256,
        PHOTO_STAGE_FULL,
    };
    constexpr uint32_t kStageBits[] = {
        PHOTO_STAGE_MASK_PLACEHOLDER32,
        PHOTO_STAGE_MASK_THUMB256,
        PHOTO_STAGE_MASK_FULL,
    };
    for (size_t i = 0; i < 3; ++i) {
        if ((wanted_stages_mask & kStageBits[i]) == 0) continue;
        if (slot->current_generation() != generation) return;

        publish_stage_for_path(*slot, kStages[i], path);
        emit_stage_ready(request_id, asset_id, slot_id, generation,
                         kStages[i], slot->initial_w(), slot->initial_h());
    }
}

}  // namespace photo
