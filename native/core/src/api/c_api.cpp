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

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
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
// Import + catalog
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_import_path(photo_engine_t* engine,
                                     const char* path_utf8,
                                     uint32_t /*flags*/) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine || !path_utf8 || !*path_utf8) return 0;
    try {
        return cast(engine)->import_path(path_utf8);
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_import_path: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)path_utf8;
    return 0;
#endif
}

PHOTO_API uint64_t photo_rescan(photo_engine_t* engine, uint32_t /*flags*/) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return cast(engine)->rescan();
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_rescan: %s", e.what());
        return 0;
    }
#else
    (void)engine;
    return 0;
#endif
}

PHOTO_API size_t photo_list_assets(photo_engine_t* engine,
                                   photo_asset_t* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto rows = cast(engine)->list_assets();
        const size_t n = rows.size();
        if (out) {
            for (size_t i = 0; i < n && i < cap; ++i) {
                const auto& a = rows[i];
                photo_asset_t& d = out[i];
                d = photo_asset_t{};
                d.asset_id    = static_cast<uint64_t>(a.id);
                d.size        = static_cast<uint64_t>(a.size);
                d.mtime_ns    = static_cast<uint64_t>(a.mtime_ns);
                d.width       = static_cast<uint32_t>(a.width);
                d.height      = static_cast<uint32_t>(a.height);
                d.orientation = static_cast<uint32_t>(a.orientation);
                d.starred     = a.starred ? 1 : 0;
                d.rating      = a.rating;
                d.flags       = a.hidden ? PHOTO_ASSET_FLAG_HIDDEN : 0u;
                std::snprintf(d.path, sizeof(d.path), "%s", a.path.c_str());
            }
        }
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_list_assets: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API int32_t photo_asset_metadata(photo_engine_t* engine,
                                       uint64_t asset_id,
                                       photo_metadata_t* out) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine || !out) return PHOTO_STATUS_INVALID_ARG;
    try {
        auto m = cast(engine)->asset_metadata(static_cast<int64_t>(asset_id));
        if (!m) return PHOTO_STATUS_NOT_FOUND;
        *out = photo_metadata_t{};
        out->asset_id      = asset_id;
        out->width         = m->width;
        out->height        = m->height;
        out->orientation   = m->orientation;
        out->iso           = m->iso;
        out->datetime_unix = m->datetime_unix;
        out->has_gps       = m->has_gps ? 1 : 0;
        out->gps_lat       = m->gps_lat;
        out->gps_lon       = m->gps_lon;
        std::snprintf(out->camera,   sizeof(out->camera),   "%s", m->camera.c_str());
        std::snprintf(out->lens,     sizeof(out->lens),     "%s", m->lens.c_str());
        std::snprintf(out->aperture, sizeof(out->aperture), "%s", m->aperture.c_str());
        std::snprintf(out->shutter,  sizeof(out->shutter),  "%s", m->shutter.c_str());
        std::snprintf(out->focal,    sizeof(out->focal),    "%s", m->focal.c_str());
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_metadata: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)asset_id; (void)out;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API size_t photo_list_geotagged(photo_engine_t* engine,
                                      photo_geopoint_t* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto rows = cast(engine)->list_geotagged();
        const size_t n = rows.size();
        if (out) {
            for (size_t i = 0; i < n && i < cap; ++i) {
                out[i] = photo_geopoint_t{static_cast<uint64_t>(rows[i].asset_id),
                                          rows[i].lat, rows[i].lon};
            }
        }
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_list_geotagged: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// Albums
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_album_create(photo_engine_t* engine,
                                      const char* name_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return cast(engine)->create_album(name_utf8 ? name_utf8 : "");
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_create: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)name_utf8;
    return 0;
#endif
}

PHOTO_API int32_t photo_album_rename(photo_engine_t* engine, uint64_t album_id,
                                     const char* name_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->rename_album(static_cast<int64_t>(album_id),
                                   name_utf8 ? name_utf8 : "");
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_rename: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)album_id; (void)name_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_album_delete(photo_engine_t* engine, uint64_t album_id) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->delete_album(static_cast<int64_t>(album_id));
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_delete: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)album_id;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_album_set_cover(photo_engine_t* engine, uint64_t album_id,
                                        uint64_t cover_asset_id) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->set_album_cover(static_cast<int64_t>(album_id),
                                      static_cast<int64_t>(cover_asset_id));
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_set_cover: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)album_id; (void)cover_asset_id;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_album_add(photo_engine_t* engine, uint64_t album_id,
                                  uint64_t asset_id) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->add_to_album(static_cast<int64_t>(album_id),
                                   static_cast<int64_t>(asset_id));
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_add: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)album_id; (void)asset_id;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_album_remove(photo_engine_t* engine, uint64_t album_id,
                                     uint64_t asset_id) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->remove_from_album(static_cast<int64_t>(album_id),
                                        static_cast<int64_t>(asset_id));
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_remove: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)album_id; (void)asset_id;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API size_t photo_album_list(photo_engine_t* engine,
                                  photo_album_t* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto rows = cast(engine)->list_albums();
        const size_t n = rows.size();
        if (out) {
            for (size_t i = 0; i < n && i < cap; ++i) {
                const auto& a = rows[i];
                photo_album_t& d = out[i];
                d = photo_album_t{};
                d.album_id = static_cast<uint64_t>(a.id);
                d.cover_asset_id =
                    a.cover_asset_id > 0 ? static_cast<uint64_t>(a.cover_asset_id) : 0;
                d.count = a.count;
                d.created = a.created;
                std::snprintf(d.name, sizeof(d.name), "%s", a.name.c_str());
            }
        }
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_list: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API size_t photo_album_members(photo_engine_t* engine, uint64_t album_id,
                                     uint64_t* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto ids = cast(engine)->album_members(static_cast<int64_t>(album_id));
        const size_t n = ids.size();
        if (out) {
            for (size_t i = 0; i < n && i < cap; ++i)
                out[i] = static_cast<uint64_t>(ids[i]);
        }
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_album_members: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)album_id; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API size_t photo_smart_recent(photo_engine_t* engine, int32_t limit,
                                    uint64_t* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto ids = cast(engine)->recent_assets(limit);
        const size_t n = ids.size();
        if (out)
            for (size_t i = 0; i < n && i < cap; ++i)
                out[i] = static_cast<uint64_t>(ids[i]);
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_smart_recent: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)limit; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API size_t photo_smart_starred(photo_engine_t* engine, uint64_t* out,
                                     size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto ids = cast(engine)->starred_assets();
        const size_t n = ids.size();
        if (out)
            for (size_t i = 0; i < n && i < cap; ++i)
                out[i] = static_cast<uint64_t>(ids[i]);
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_smart_starred: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// Organize state — star / rating / caption / tags (catalog-only).
// ---------------------------------------------------------------------------

#ifdef PHOTO_HAVE_SQLITE
namespace {
template <typename Fn>
int32_t organize_mutate(photo_engine_t* engine, const char* what, Fn fn) {
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        fn(cast(engine));
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "%s: %s", what, e.what());
        return PHOTO_STATUS_INTERNAL;
    }
}

// Pack strings into a NUL-separated buffer ("a\0b\0…"); return total bytes
// needed (grow-and-recall protocol shared by the hidden-list getters).
size_t fill_nul_list(const std::vector<std::string>& items, char* out,
                     size_t cap) {
    size_t total = 0;
    for (const auto& s : items) total += s.size() + 1;
    if (out && cap > 0) {
        size_t pos = 0;
        for (const auto& s : items) {
            const size_t need = s.size() + 1;
            if (pos + need > cap) break;
            std::memcpy(out + pos, s.data(), s.size());
            out[pos + s.size()] = '\0';
            pos += need;
        }
    }
    return total;
}
}  // namespace
#endif

PHOTO_API int32_t photo_asset_set_starred(photo_engine_t* engine,
                                          uint64_t asset_id, int32_t starred) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_asset_set_starred", [&](photo::Engine* e) {
        e->set_starred(static_cast<int64_t>(asset_id), starred != 0);
    });
#else
    (void)engine; (void)asset_id; (void)starred;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_set_rating(photo_engine_t* engine,
                                         uint64_t asset_id, int32_t rating) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_asset_set_rating", [&](photo::Engine* e) {
        e->set_rating(static_cast<int64_t>(asset_id), rating);
    });
#else
    (void)engine; (void)asset_id; (void)rating;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_set_caption(photo_engine_t* engine,
                                          uint64_t asset_id,
                                          const char* caption_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_asset_set_caption", [&](photo::Engine* e) {
        e->set_caption(static_cast<int64_t>(asset_id),
                       caption_utf8 ? std::string(caption_utf8) : std::string{});
    });
#else
    (void)engine; (void)asset_id; (void)caption_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_set_hidden(photo_engine_t* engine,
                                         uint64_t asset_id, int32_t hidden) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_asset_set_hidden", [&](photo::Engine* e) {
        e->set_hidden(static_cast<int64_t>(asset_id), hidden != 0);
    });
#else
    (void)engine; (void)asset_id; (void)hidden;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_folder_set_hidden(photo_engine_t* engine,
                                          const char* path_utf8, int32_t hidden) {
#ifdef PHOTO_HAVE_SQLITE
    if (!path_utf8 || !*path_utf8) return PHOTO_STATUS_INVALID_ARG;
    return organize_mutate(engine, "photo_folder_set_hidden", [&](photo::Engine* e) {
        e->set_folder_hidden(path_utf8, hidden != 0);
    });
#else
    (void)engine; (void)path_utf8; (void)hidden;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API size_t photo_hidden_folders(photo_engine_t* engine, char* out,
                                      size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return fill_nul_list(cast(engine)->hidden_folders(), out, cap);
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_hidden_folders: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API size_t photo_hidden_assets(photo_engine_t* engine, char* out,
                                     size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return fill_nul_list(cast(engine)->hidden_asset_paths(), out, cap);
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_hidden_assets: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API int32_t photo_catalog_stats(photo_engine_t* engine,
                                      photo_catalog_stats_t* out) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine || !out) return PHOTO_STATUS_INVALID_ARG;
    try {
        const auto s = cast(engine)->catalog_stats();
        out->page_count = s.page_count;
        out->freelist_count = s.freelist_count;
        out->page_size = s.page_size;
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_catalog_stats: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)out;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API uint64_t photo_catalog_compact(photo_engine_t* engine) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return cast(engine)->compact_catalog();
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_catalog_compact: %s", e.what());
        return 0;
    }
#else
    (void)engine;
    return 0;
#endif
}

PHOTO_API int32_t photo_catalog_compact_sync(photo_engine_t* engine) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_catalog_compact_sync",
                           [&](photo::Engine* e) { e->compact_catalog_sync(); });
#else
    (void)engine;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_catalog_checkpoint(photo_engine_t* engine) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_catalog_checkpoint",
                           [&](photo::Engine* e) { e->catalog_checkpoint(); });
#else
    (void)engine;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_library_rebase(photo_engine_t* engine,
                                       const char* old_prefix_utf8,
                                       const char* new_prefix_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine || !old_prefix_utf8 || !new_prefix_utf8)
        return PHOTO_STATUS_INVALID_ARG;
    try {
        const int64_t n =
            cast(engine)->rebase_paths(old_prefix_utf8, new_prefix_utf8);
        return n < 0 ? PHOTO_STATUS_NOT_FOUND : PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_library_rebase: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)old_prefix_utf8; (void)new_prefix_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_organize(photo_engine_t* engine, uint64_t asset_id,
                                       photo_organize_t* out) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine || !out) return PHOTO_STATUS_INVALID_ARG;
    try {
        auto a = cast(engine)->asset(static_cast<int64_t>(asset_id));
        if (!a) return PHOTO_STATUS_NOT_FOUND;
        *out = photo_organize_t{};
        out->starred = a->starred ? 1 : 0;
        out->rating = a->rating;
        std::snprintf(out->caption, sizeof(out->caption), "%s", a->caption.c_str());
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_organize: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)asset_id; (void)out;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_add_tag(photo_engine_t* engine, uint64_t asset_id,
                                      const char* tag_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!tag_utf8 || !*tag_utf8) return PHOTO_STATUS_INVALID_ARG;
    return organize_mutate(engine, "photo_asset_add_tag", [&](photo::Engine* e) {
        e->add_tag(static_cast<int64_t>(asset_id), tag_utf8);
    });
#else
    (void)engine; (void)asset_id; (void)tag_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_asset_remove_tag(photo_engine_t* engine,
                                         uint64_t asset_id, const char* tag_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!tag_utf8) return PHOTO_STATUS_INVALID_ARG;
    return organize_mutate(engine, "photo_asset_remove_tag", [&](photo::Engine* e) {
        e->remove_tag(static_cast<int64_t>(asset_id), tag_utf8);
    });
#else
    (void)engine; (void)asset_id; (void)tag_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API size_t photo_asset_tags(photo_engine_t* engine, uint64_t asset_id,
                                  char* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const auto tags = cast(engine)->tags_for_asset(static_cast<int64_t>(asset_id));
        size_t total = 0;
        for (const auto& t : tags) total += t.size() + 1;  // each tag + NUL
        if (out && cap > 0) {
            size_t pos = 0;
            for (const auto& t : tags) {
                const size_t need = t.size() + 1;
                if (pos + need > cap) break;
                std::memcpy(out + pos, t.data(), t.size());
                out[pos + t.size()] = '\0';
                pos += need;
            }
        }
        return total;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_tags: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)asset_id; (void)out; (void)cap;
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// Non-destructive edits.
// ---------------------------------------------------------------------------

PHOTO_API size_t photo_asset_get_edits(photo_engine_t* engine, uint64_t asset_id,
                                       char* out, size_t cap) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        const std::string s =
            cast(engine)->get_edits(static_cast<int64_t>(asset_id));
        const size_t need = s.size() + 1;  // include the NUL terminator
        if (out && cap > 0) {
            const size_t n = std::min(s.size(), cap - 1);
            std::memcpy(out, s.data(), n);
            out[n] = '\0';
        }
        return need;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_get_edits: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)asset_id; (void)out; (void)cap;
    return 0;
#endif
}

PHOTO_API uint64_t photo_asset_set_edits(photo_engine_t* engine,
                                         uint64_t asset_id,
                                         const char* spec_utf8) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return cast(engine)->set_edits(static_cast<int64_t>(asset_id),
                                       spec_utf8 ? spec_utf8 : "");
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_set_edits: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)asset_id; (void)spec_utf8;
    return 0;
#endif
}

PHOTO_API int32_t photo_asset_revert(photo_engine_t* engine, uint64_t asset_id) {
#ifdef PHOTO_HAVE_SQLITE
    return organize_mutate(engine, "photo_asset_revert", [&](photo::Engine* e) {
        e->revert_edits(static_cast<int64_t>(asset_id));
    });
#else
    (void)engine; (void)asset_id;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API uint64_t photo_asset_content_rev(photo_engine_t* engine,
                                           uint64_t asset_id) {
#ifdef PHOTO_HAVE_SQLITE
    if (!engine) return 0;
    try {
        return cast(engine)->content_rev(static_cast<int64_t>(asset_id));
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_content_rev: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)asset_id;
    return 0;
#endif
}

PHOTO_API uint64_t photo_asset_export(photo_engine_t* engine,
                                      const char* src_path_utf8,
                                      const char* dst_path_utf8,
                                      const char* spec_utf8,
                                      int32_t quality) {
#ifdef PHOTO_HAVE_VIPS
    if (!engine || !src_path_utf8 || !dst_path_utf8) return 0;
    try {
        return cast(engine)->export_path(src_path_utf8, dst_path_utf8,
                                         spec_utf8 ? spec_utf8 : "", quality);
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_export: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)src_path_utf8; (void)dst_path_utf8;
    (void)spec_utf8; (void)quality;
    return 0;
#endif
}

PHOTO_API uint64_t photo_asset_save_layered(photo_engine_t* engine,
                                            const char* src_path_utf8,
                                            const char* dst_path_utf8,
                                            const char* spec_utf8) {
#ifdef PHOTO_HAVE_VIPS
    if (!engine || !src_path_utf8 || !dst_path_utf8) return 0;
    try {
        return cast(engine)->save_layered(src_path_utf8, dst_path_utf8,
                                          spec_utf8 ? spec_utf8 : "");
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_save_layered: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)src_path_utf8; (void)dst_path_utf8; (void)spec_utf8;
    return 0;
#endif
}

PHOTO_API size_t photo_list_edited_assets(photo_engine_t* engine,
                                          uint64_t* out, size_t cap) {
    if (!engine) return 0;
    try {
        const auto ids = cast(engine)->edited_asset_ids();
        const size_t n = ids.size();
        if (out)
            for (size_t i = 0; i < n && i < cap; ++i)
                out[i] = static_cast<uint64_t>(ids[i]);
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_list_edited_assets: %s", e.what());
        return 0;
    }
}

PHOTO_API int32_t photo_asset_preview_edits(photo_engine_t* engine,
                                            uint64_t slot_id,
                                            uint64_t generation,
                                            const char* path_utf8,
                                            uint32_t target_w,
                                            uint32_t target_h,
                                            const char* spec_utf8) {
#ifdef PHOTO_HAVE_VIPS
    if (!engine || !path_utf8 || !*path_utf8) return PHOTO_STATUS_INVALID_ARG;
    try {
        cast(engine)->preview_edits(slot_id, generation, path_utf8,
                                    target_w, target_h,
                                    spec_utf8 ? spec_utf8 : "");
        return PHOTO_STATUS_OK;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_preview_edits: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)slot_id; (void)generation; (void)path_utf8;
    (void)target_w; (void)target_h; (void)spec_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

PHOTO_API int32_t photo_redeye_auto_supported(void) {
#if defined(PHOTO_HAVE_FACES)
    return 1;
#else
    return 0;
#endif
}

PHOTO_API size_t photo_asset_detect_redeye(photo_engine_t* engine,
                                           uint64_t asset_id,
                                           const char* path_utf8,
                                           const char* spec_utf8,
                                           photo_region_t* out, size_t cap) {
    if (!engine || !path_utf8) return 0;
    try {
        const auto regs = cast(engine)->detect_redeye(
            static_cast<int64_t>(asset_id), path_utf8,
            spec_utf8 ? spec_utf8 : "");
        const size_t n = regs.size();
        if (out)
            for (size_t i = 0; i < n && i < cap; ++i) {
                out[i].x = regs[i].x;
                out[i].y = regs[i].y;
                out[i].r = regs[i].r;
            }
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_asset_detect_redeye: %s", e.what());
        return 0;
    }
}

// ---------------------------------------------------------------------------
// ML — M6 implements.
// ---------------------------------------------------------------------------

PHOTO_API int32_t photo_provider_probe(photo_engine_t* /*engine*/,
                                       int32_t /*provider*/) {
    return PHOTO_STATUS_UNSUPPORTED;
}

PHOTO_API uint64_t photo_face_scan(photo_engine_t* engine,
                                   uint64_t asset_id, uint32_t flags) {
#if defined(PHOTO_HAVE_FACES) && defined(PHOTO_HAVE_SQLITE)
    if (!engine) return 0;
    try {
        auto* eng = cast(engine);
        if (!eng->catalog()) return 0;
        // Locked lookup: safe against a concurrent import holding the catalog.
        const std::string path = eng->path_for_asset(static_cast<int64_t>(asset_id));
        if (path.empty()) {
            PHOTO_LOGF(PHOTO_LOG_WARN,
                       "photo_face_scan: no catalog asset %llu",
                       static_cast<unsigned long long>(asset_id));
            return 0;
        }
        return eng->faces().submit_scan(asset_id, path.c_str(), flags);
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_face_scan: %s", e.what());
        return 0;
    }
#else
    // Without the catalog there is no asset_id -> path mapping; callers drive
    // the pipeline through the photo_face_scan_path hook instead.
    (void)engine; (void)asset_id; (void)flags;
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// Clustering — M7.
// ---------------------------------------------------------------------------

PHOTO_API uint64_t photo_face_approve(photo_engine_t* engine,
                                      uint64_t cluster_id,
                                      uint64_t embedding_id) {
#ifdef PHOTO_HAVE_FACES
    if (!engine) return 0;
    try { return cast(engine)->faces().approve(cluster_id, embedding_id); }
    catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_face_approve: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)cluster_id; (void)embedding_id;
    return 0;
#endif
}

PHOTO_API uint64_t photo_face_reject(photo_engine_t* engine,
                                     uint64_t cluster_id,
                                     uint64_t embedding_id) {
#ifdef PHOTO_HAVE_FACES
    if (!engine) return 0;
    try { return cast(engine)->faces().reject(cluster_id, embedding_id); }
    catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_face_reject: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)cluster_id; (void)embedding_id;
    return 0;
#endif
}

PHOTO_API uint64_t photo_cluster_rebuild(photo_engine_t* engine,
                                         uint32_t flags) {
#ifdef PHOTO_HAVE_FACES
    if (!engine) return 0;
    try { return cast(engine)->faces().rebuild_clusters(flags); }
    catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_cluster_rebuild: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)flags;
    return 0;
#endif
}

PHOTO_API uint64_t photo_face_name_cluster(photo_engine_t* engine,
                                           int64_t cluster_id,
                                           const char* name_utf8) {
#ifdef PHOTO_HAVE_FACES
    if (!engine) return 0;
    try {
        return cast(engine)->faces().name_cluster(
            cluster_id, name_utf8 ? std::string(name_utf8) : std::string{});
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_face_name_cluster: %s", e.what());
        return 0;
    }
#else
    (void)engine; (void)cluster_id; (void)name_utf8;
    return 0;
#endif
}

// ---------------------------------------------------------------------------
// Face read-back (UI queries). Each fills up to `cap` POD rows and returns the
// total count available (mirrors photo_poll_events). Synchronous.
// ---------------------------------------------------------------------------

#ifdef PHOTO_HAVE_FACES
namespace {
template <typename Row, typename Fn>
size_t fill_rows(photo_engine_t* engine, Row* out, size_t cap, Fn query,
                 const char* what) {
    if (!engine) return 0;
    try {
        const auto rows = query(cast(engine));
        const size_t n = rows.size();
        if (out) for (size_t i = 0; i < n && i < cap; ++i) out[i] = rows[i];
        return n;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "%s: %s", what, e.what());
        return 0;
    }
}
}  // namespace
#endif

PHOTO_API size_t photo_face_list_people(photo_engine_t* engine,
                                        photo_person_t* out, size_t cap) {
#ifdef PHOTO_HAVE_FACES
    return fill_rows(engine, out, cap,
                     [](photo::Engine* e) { return e->faces().list_people(); },
                     "photo_face_list_people");
#else
    (void)engine; (void)out; (void)cap; return 0;
#endif
}

PHOTO_API size_t photo_face_list_clusters(photo_engine_t* engine,
                                          photo_person_t* out, size_t cap) {
#ifdef PHOTO_HAVE_FACES
    return fill_rows(engine, out, cap,
                     [](photo::Engine* e) { return e->faces().list_clusters(); },
                     "photo_face_list_clusters");
#else
    (void)engine; (void)out; (void)cap; return 0;
#endif
}

PHOTO_API size_t photo_face_list_cluster_faces(photo_engine_t* engine,
                                               int64_t cluster_id,
                                               photo_face_t* out, size_t cap) {
#ifdef PHOTO_HAVE_FACES
    return fill_rows(engine, out, cap,
                     [cluster_id](photo::Engine* e) {
                         return e->faces().list_cluster_faces(cluster_id);
                     },
                     "photo_face_list_cluster_faces");
#else
    (void)engine; (void)cluster_id; (void)out; (void)cap; return 0;
#endif
}

PHOTO_API size_t photo_face_list_suggestions(photo_engine_t* engine,
                                             uint64_t person_id,
                                             photo_face_t* out, size_t cap) {
#ifdef PHOTO_HAVE_FACES
    return fill_rows(engine, out, cap,
                     [person_id](photo::Engine* e) {
                         return e->faces().list_suggestions(person_id);
                     },
                     "photo_face_list_suggestions");
#else
    (void)engine; (void)person_id; (void)out; (void)cap; return 0;
#endif
}

PHOTO_API size_t photo_face_list_for_asset(photo_engine_t* engine,
                                           uint64_t asset_id,
                                           photo_face_t* out, size_t cap) {
#ifdef PHOTO_HAVE_FACES
    return fill_rows(engine, out, cap,
                     [asset_id](photo::Engine* e) {
                         return e->faces().list_for_asset(asset_id);
                     },
                     "photo_face_list_for_asset");
#else
    (void)engine; (void)asset_id; (void)out; (void)cap; return 0;
#endif
}

PHOTO_API int32_t photo_face_name_person(photo_engine_t* engine,
                                         uint64_t person_id,
                                         const char* name_utf8) {
#ifdef PHOTO_HAVE_FACES
    if (!engine) return PHOTO_STATUS_INVALID_ARG;
    try {
        const bool ok = cast(engine)->faces().name_person(
            person_id, name_utf8 ? std::string(name_utf8) : std::string{});
        return ok ? PHOTO_STATUS_OK : PHOTO_STATUS_BAD_STATE;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "photo_face_name_person: %s", e.what());
        return PHOTO_STATUS_INTERNAL;
    }
#else
    (void)engine; (void)person_id; (void)name_utf8;
    return PHOTO_STATUS_UNSUPPORTED;
#endif
}

// ---------------------------------------------------------------------------
// TEST-ONLY hook (M1).
//
// Publishes a solid-color frame into a slot. The texture-harness uses this
// before M2's request/decode pipeline lands. Wrapped in extern "C" because the
// symbol is intentionally not declared in photo_core.h.
// (photo_face_scan now resolves asset_id -> path via the catalog, so the former
// photo_face_scan_path hook has been removed.)
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
