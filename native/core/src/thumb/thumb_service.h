// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// thumb_service.h — implements photo_thumb_request_fast.
//
// M2 scope:
//   * Accept requests, enqueue onto the JobSystem.
//   * Worker thread runs a *synthetic* "decoder" that publishes a solid
//     color derived from a stable hash of the asset path, once per stage
//     bit set in the request mask.
//   * Honor generation tokens: a request whose generation no longer
//     matches the slot's current generation is silently dropped.
//   * Emit PHOTO_EVT_STAGE_READY (or PHOTO_EVT_STAGE_FAILED) into the
//     EventRing for each handled stage.
//
// M3 replaces the synthetic publish with libvips / libjpeg-turbo decoding.
// The request API and event shape do not change.

#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>

#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"

namespace photo {

class ThumbService {
public:
    ThumbService(SlotStore* slots, EventRing* events, JobSystem* jobs);

    ThumbService(const ThumbService&)            = delete;
    ThumbService& operator=(const ThumbService&) = delete;

    // Submit a thumbnail request. Returns a non-zero request id on
    // acceptance; 0 if rejected (invalid slot, no stages requested).
    uint64_t submit(uint64_t asset_id,
                    uint64_t slot_id,
                    uint64_t generation,
                    const char* path_utf8,
                    uint32_t target_w,
                    uint32_t target_h,
                    uint32_t wanted_stages_mask,
                    uint32_t priority);

    void cancel(uint64_t request_id);

private:
    void run_synthetic(uint64_t request_id,
                       uint64_t asset_id,
                       uint64_t slot_id,
                       uint64_t generation,
                       std::string path,
                       uint32_t target_w,
                       uint32_t target_h,
                       uint32_t wanted_stages_mask);

    void publish_stage_for_path(Slot& slot,
                                uint32_t stage,
                                const std::string& path);

    void emit_stage_ready(uint64_t request_id,
                          uint64_t asset_id,
                          uint64_t slot_id,
                          uint64_t generation,
                          uint32_t stage,
                          uint32_t width,
                          uint32_t height);

    void emit_stage_failed(uint64_t request_id,
                           uint64_t asset_id,
                           uint64_t slot_id,
                           uint64_t generation,
                           uint32_t stage,
                           int32_t status);

    SlotStore*  slots_;
    EventRing*  events_;
    JobSystem*  jobs_;

    // Public request_id namespace lives in ThumbService, not JobSystem,
    // so callers cancel by request_id without leaking the underlying
    // job allocator's identity. Mapping is removed in run_synthetic when
    // the work completes.
    std::atomic<uint64_t>                            next_request_id_{1};
    mutable std::mutex                               req_mu_;
    std::unordered_map<uint64_t, uint64_t>           request_to_job_;
};

}  // namespace photo
