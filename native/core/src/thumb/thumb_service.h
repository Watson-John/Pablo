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
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>

#include "edit/edit_spec.h"
#include "edit/render.h"  // edit::Watermark (ExportOptions member)
#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"

namespace photo {

class ThumbCache;

class ThumbService {
public:
    ThumbService(SlotStore* slots, EventRing* events, JobSystem* jobs);
    ~ThumbService();

    ThumbService(const ThumbService&)            = delete;
    ThumbService& operator=(const ThumbService&) = delete;

    // Attach the persistent thumbnail cache (owned by Engine). When set,
    // requests serve from disk on a hit and store decoded frames on a miss.
    void set_cache(ThumbCache* cache) { cache_ = cache; }

    // Inject the per-asset edit lookup (owned by Engine; reads its lock-free COW
    // map). When set, each request applies the asset's saved edit during render
    // and folds its content_rev into the cache key. Mirrors set_cache: called
    // once at engine init, read-only thereafter. Unset → unedited behaviour.
    void set_edit_lookup(std::function<edit::EditEntry(uint64_t)> fn) {
        edit_lookup_ = std::move(fn);
    }

    // Live, TRANSIENT preview: render `spec` over a fresh decode of `path` and
    // publish it straight to the slot. Never touches the cache or a request_id;
    // emits STAGE_READY (request_id 0) with the echoed generation. Backed by a
    // 1-entry decoded-base cache so debounced slider ticks are apply+resize only.
    // No-op without libvips. Honors the slot generation guard.
    void preview(uint64_t slot_id, uint64_t generation, const std::string& path,
                 uint32_t target_w, uint32_t target_h,
                 const edit::EditSpec& spec);

    // Render `spec` over a FULL-RES decode of `src` and write a flattened copy to
    // `dst` (format by extension; jpg honours quality 1..100). True on success.
    // No slot/cache. libvips only (false without it). Used by "Save as Copy".
    bool export_to_file(const std::string& src, const std::string& dst,
                        const edit::EditSpec& spec, int quality);

    // Export output options. `max_dim` bounds the LONG edge of the written file
    // (0 = source size; never upscales). A watermark applies when `wm.text` is
    // non-empty, drawn on the post-resize frame so its on-disk scale is exact.
    struct ExportOptions {
        uint32_t max_dim = 0;
        int quality = 92;
        edit::Watermark wm;
    };

    // export_to_file with resize + watermark. Same contract otherwise; the
    // quality-only export_to_file delegates here with default options.
    bool export_to_file2(const std::string& src, const std::string& dst,
                         const edit::EditSpec& spec, const ExportOptions& opts);

    // Write a layered TIFF to `dst`: page 0 = the full edited render, page 1 =
    // the untouched original (both padded to a common canvas), with the spec in
    // the TIFF ImageDescription. Reversible from the file itself. libvips only.
    bool save_layered_tiff(const std::string& src, const std::string& dst,
                           const edit::EditSpec& spec);

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
    ThumbCache* cache_{nullptr};  // not owned (Engine owns it)

    // Per-asset edit lookup (Engine-owned COW map). Empty == unedited behaviour.
    std::function<edit::EditEntry(uint64_t)> edit_lookup_;

    // 1-entry decoded-base cache for the preview path: holds the last decoded
    // VipsImage so pure tone/colour ticks (which don't change the decode dim) are
    // apply+resize+publish, not a re-decode. `base` is a VipsImage* stored opaque
    // so this header needn't include <vips/vips.h>; freed in ~ThumbService.
    struct PreviewBase {
        std::mutex  mu;
        std::string path;
        int         decode_dim = 0;
        void*       base = nullptr;  // VipsImage* (owned)
    };
    PreviewBase preview_base_;

    // Public request_id namespace lives in ThumbService, not JobSystem,
    // so callers cancel by request_id without leaking the underlying
    // job allocator's identity. Mapping is removed in run_synthetic when
    // the work completes.
    std::atomic<uint64_t>                            next_request_id_{1};
    mutable std::mutex                               req_mu_;
    std::unordered_map<uint64_t, uint64_t>           request_to_job_;
};

}  // namespace photo
