// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// c_api.cpp — extern "C" dispatch from photo_core.h to internal C++.
//
// Rules followed in this TU:
//   - Every PHOTO_API function is implemented here, even if it delegates to
//     a single internal call. Keeping all symbols in one TU makes the
//     export surface easy to audit.
//   - No exceptions cross the C boundary. C++ subsystems that throw must be
//     wrapped in a try/catch here.
//   - NULL engines are tolerated by lifecycle functions (destroy). Other
//     functions treat NULL engine as a misuse and return a sentinel.

#include <stdexcept>
#include <utility>

#include "photo_core.h"
#include "runtime/engine.h"
#include "runtime/event_ring.h"
#include "runtime/slot_store.h"
#include "thumb/slot.h"
#include "util/log.h"

namespace {

photo::Engine* cast(photo_engine_t* p) {
    return reinterpret_cast<photo::Engine*>(p);
}

photo_engine_t* cast_back(photo::Engine* p) {
    return reinterpret_cast<photo_engine_t*>(p);
}

}  // namespace

// ---------------------------------------------------------------------------
// Version + ABI
// ---------------------------------------------------------------------------

PHOTO_API uint32_t photo_abi_version(void) {
    return static_cast<uint32_t>(PHOTO_ABI_VERSION);
}

PHOTO_API const char* photo_engine_version(void) {
    // Static storage; safe to return.
    static const char kVersion[] =
        "0.1.0+dev";  // PHOTO_VERSION_MAJOR.MINOR.PATCH + git sha (M1: dev)
    return kVersion;
}

// ---------------------------------------------------------------------------
// Engine lifecycle
// ---------------------------------------------------------------------------

PHOTO_API photo_engine_t* photo_engine_create(const photo_config_t* cfg) {
    if (!cfg) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_engine_create: cfg is NULL");
        return nullptr;
    }
    try {
        auto eng = photo::Engine::create(*cfg);
        return eng ? cast_back(eng.release()) : nullptr;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "engine create exception: %s", e.what());
        return nullptr;
    } catch (...) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "engine create: unknown exception");
        return nullptr;
    }
}

PHOTO_API void photo_engine_destroy(photo_engine_t* engine) {
    delete cast(engine);  // delete nullptr is well-defined
}

// ---------------------------------------------------------------------------
// Slot lifecycle
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_slot_create(photo_engine_t* engine,
                                     int32_t initial_w, int32_t initial_h) {
    if (!engine) return 0;
    return cast(engine)->slots().create(initial_w, initial_h);
}

PHOTO_API void photo_slot_destroy(photo_engine_t* engine, uint64_t slot_id) {
    if (!engine) return;
    cast(engine)->slots().destroy(slot_id);
}

PHOTO_API uint64_t photo_slot_bind_generation(photo_engine_t* engine,
                                              uint64_t slot_id,
                                              uint64_t generation) {
    if (!engine) return 0;
    auto* slot = cast(engine)->slots().get(slot_id);
    return slot ? slot->bind_generation(generation) : 0;
}

// ---------------------------------------------------------------------------
// Thumbnail requests — M2 implements; M1 returns 0 (rejected).
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_thumb_request_fast(
    photo_engine_t* engine,
    uint64_t asset_id,
    uint64_t slot_id,
    uint64_t generation,
    const char* path_utf8,
    uint32_t target_w,
    uint32_t target_h,
    uint32_t wanted_stages_mask,
    uint32_t priority,
    uint32_t /*flags*/) {
    if (!engine) return 0;
    return cast(engine)->thumbs().submit(
        asset_id, slot_id, generation,
        path_utf8, target_w, target_h,
        wanted_stages_mask, priority);
}

PHOTO_API uint64_t photo_thumb_request(photo_engine_t* engine,
                                       const photo_thumb_request_t* req) {
    if (!engine || !req) return 0;
    return cast(engine)->thumbs().submit(
        req->asset_id, req->slot_id, req->generation,
        req->path_utf8, req->target_w, req->target_h,
        req->wanted_stages_mask, req->priority);
}

PHOTO_API void photo_thumb_cancel(photo_engine_t* engine,
                                  uint64_t request_id) {
    if (!engine) return;
    cast(engine)->thumbs().cancel(request_id);
}

// ---------------------------------------------------------------------------
// Frame acquisition (called by the plugin's texture callback)
// ---------------------------------------------------------------------------

PHOTO_API bool photo_slot_acquire_latest(photo_engine_t* engine,
                                         uint64_t slot_id,
                                         photo_frame_view_t* out) {
    if (!engine || !out) return false;
    *out = photo_frame_view_t{};

    auto* slot = cast(engine)->slots().get(slot_id);
    if (!slot) return false;

    auto fp = slot->acquire_view();
    if (!fp) return false;

    // Heap-allocated holder keeps the FrameBuffer alive for the borrow
    // duration. Destroyed by photo_slot_release.
    auto* holder = new photo::FrameHolder{std::move(fp)};

    out->bgra        = holder->frame->bgra.data();
    out->width       = holder->frame->width;
    out->height      = holder->frame->height;
    out->stride      = holder->frame->stride;
    out->release_ctx = holder;

    return true;
}

PHOTO_API void photo_slot_release(photo_engine_t* /*engine*/, void* release_ctx) {
    if (!release_ctx) return;
    delete reinterpret_cast<photo::FrameHolder*>(release_ctx);
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

PHOTO_API size_t photo_poll_events(photo_engine_t* engine,
                                   photo_event_t* out, size_t cap) {
    if (!engine || !out || cap == 0) return 0;
    return cast(engine)->events().pop_n(out, cap);
}

// ---------------------------------------------------------------------------
// Import + catalog — M3 implements.
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_import_path(photo_engine_t* /*engine*/,
                                     const char* /*path_utf8*/,
                                     uint32_t /*flags*/) {
    return 0;
}

PHOTO_API uint64_t photo_rescan(photo_engine_t* /*engine*/, uint32_t /*flags*/) {
    return 0;
}

// ---------------------------------------------------------------------------
// ML — M6 implements.
// ---------------------------------------------------------------------------

PHOTO_API int32_t photo_provider_probe(photo_engine_t* /*engine*/,
                                       int32_t /*provider*/) {
    return PHOTO_STATUS_UNSUPPORTED;
}

PHOTO_API uint64_t photo_face_scan(photo_engine_t* /*engine*/,
                                   uint64_t /*asset_id*/, uint32_t /*flags*/) {
    return 0;
}

// ---------------------------------------------------------------------------
// Clustering — M7 implements.
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_face_approve(photo_engine_t* /*engine*/,
                                      uint64_t /*cluster_id*/,
                                      uint64_t /*embedding_id*/) {
    return 0;
}

PHOTO_API uint64_t photo_face_reject(photo_engine_t* /*engine*/,
                                     uint64_t /*cluster_id*/,
                                     uint64_t /*embedding_id*/) {
    return 0;
}

PHOTO_API uint64_t photo_cluster_rebuild(photo_engine_t* /*engine*/,
                                         uint32_t /*flags*/) {
    return 0;
}

// ---------------------------------------------------------------------------
// TEST-ONLY hook (M1).
//
// Publishes a solid-color frame into a slot. The texture-harness uses this
// before M2's request/decode pipeline lands. Removed in M2 — do not depend
// on it from production code. Wrapped in extern "C" because the symbol is
// intentionally not declared in photo_core.h.
// ---------------------------------------------------------------------------

extern "C" PHOTO_API void photo_test_publish_solid(photo_engine_t* engine,
                                                   uint64_t slot_id,
                                                   uint8_t r, uint8_t g,
                                                   uint8_t b, uint8_t a) {
    if (!engine) return;
    auto* slot = cast(engine)->slots().get(slot_id);
    if (!slot) return;
    slot->publish_solid_color(b, g, r, a);
}
