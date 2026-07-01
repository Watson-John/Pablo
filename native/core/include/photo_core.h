/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Pablo contributors.
 *
 * photo_core.h — Pablo native backend C ABI.
 *
 * This header is the single source of truth for the FFI boundary between the
 * Flutter app (Dart) and the native C++20 core. Every Dart-facing symbol the
 * app may call lives here. Anything else is internal and may change without
 * notice.
 *
 * INVARIANTS (enforced everywhere):
 *   1. No image bytes cross this boundary. Pixels live in native memory and
 *      reach the screen through Flutter Texture widgets backed by the
 *      photo_native plugin's per-platform texture registrar.
 *   2. No callbacks from native into Dart. Dart drains an event ring on its
 *      own schedule via photo_poll_events.
 *   3. All structs in this header are POD (plain data, no STL, no inheritance,
 *      no constructors). All enums are sized int32 by convention.
 *   4. All strings are NUL-terminated UTF-8. Strings passed *in* must remain
 *      valid for the duration of the call only — implementations copy what
 *      they need to retain. Strings returned *out* are owned by the engine
 *      and remain valid until the next mutating call on the same engine.
 *   5. Request IDs are monotonically increasing 64-bit integers. ID 0 means
 *      "rejected" (e.g. invalid slot) or "no request"; never a valid ID.
 *   6. Generation tokens are caller-defined uint64s. The engine treats them
 *      opaquely; it never invents them, only echoes them on events and drops
 *      stale results on mismatch.
 *   7. All functions are thread-safe unless explicitly marked otherwise.
 *
 * OWNERSHIP:
 *   - Engine memory is owned by the engine. The plugin's texture callback
 *     calls photo_slot_acquire_latest to borrow a frame view; the borrow
 *     must be returned by exactly one matching photo_slot_release call.
 *   - Event structs returned by photo_poll_events are caller-allocated;
 *     the engine fills them. No owned pointers leave via events.
 *
 * VERSIONING:
 *   - This is ABI version 1 (see PHOTO_ABI_VERSION below). Compatible changes
 *     append fields to the end of POD structs and new enum values to the end
 *     of enums. Breaking changes bump PHOTO_ABI_VERSION and rename symbols
 *     with a _v2 suffix so old + new can coexist during transition.
 */

#ifndef PHOTO_CORE_H
#define PHOTO_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "photo_core_version.h"

#ifdef _WIN32
#  define PHOTO_API __declspec(dllexport)
#else
#  define PHOTO_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------------- */
/* Forward declarations                                                      */
/* ------------------------------------------------------------------------- */

typedef struct photo_engine photo_engine_t;

/* ------------------------------------------------------------------------- */
/* Enumerations                                                              */
/* ------------------------------------------------------------------------- */

typedef enum {
    PHOTO_STATUS_OK            = 0,
    PHOTO_STATUS_INVALID_ARG   = 1,
    PHOTO_STATUS_NOT_FOUND     = 2,
    PHOTO_STATUS_IO_ERROR      = 3,
    PHOTO_STATUS_DECODE_ERROR  = 4,
    PHOTO_STATUS_OUT_OF_MEMORY = 5,
    PHOTO_STATUS_CANCELLED     = 6,
    PHOTO_STATUS_UNSUPPORTED   = 7,
    PHOTO_STATUS_BUSY          = 8,
    PHOTO_STATUS_INTERNAL      = 9,
    PHOTO_STATUS_BAD_STATE     = 10
} photo_status_t;

typedef enum {
    PHOTO_STAGE_PLACEHOLDER32 = 1,
    PHOTO_STAGE_THUMB256      = 2,
    PHOTO_STAGE_FULL          = 3
} photo_stage_t;

/* Bit mask for wanted_stages_mask in photo_thumb_request_fast. */
#define PHOTO_STAGE_MASK_PLACEHOLDER32 (1u << 0)
#define PHOTO_STAGE_MASK_THUMB256      (1u << 1)
#define PHOTO_STAGE_MASK_FULL          (1u << 2)
#define PHOTO_STAGE_MASK_DEFAULT \
    (PHOTO_STAGE_MASK_PLACEHOLDER32 | PHOTO_STAGE_MASK_THUMB256)

typedef enum {
    PHOTO_PRIORITY_INTERACTIVE = 0,  /* on-screen, must satisfy in this frame */
    PHOTO_PRIORITY_VIEWPORT    = 1,  /* in current viewport / short prefetch  */
    PHOTO_PRIORITY_IDLE        = 2   /* background; pre-cache and recache     */
} photo_priority_t;

typedef enum {
    PHOTO_EVT_STAGE_READY      = 1,
    PHOTO_EVT_STAGE_FAILED     = 2,
    PHOTO_EVT_IMPORT_PROGRESS  = 3,  /* aux64 = processed, aux64_b = total      */
    /* Terminal import/rescan event. Carries the incremental-rescan summary:
     *   aux64        = added   (new assets inserted)
     *   aux64_b      = updated (existing assets whose file changed)
     *   _reserved[0] = skipped (unchanged files — size+mtime matched, not re-read)
     *   _reserved[1] = removed (rescan-pruned assets whose file is gone)        */
    PHOTO_EVT_IMPORT_COMPLETE  = 4,
    PHOTO_EVT_SCAN_PROGRESS    = 5,
    PHOTO_EVT_CLUSTER_UPDATED  = 6,
    PHOTO_EVT_PROVIDER_PROBED  = 7,
    PHOTO_EVT_LOG              = 8,
    /* Async catalog maintenance (compaction) finished. status is the result. */
    PHOTO_EVT_MAINTENANCE_COMPLETE = 9,
    /* One semantic-embedding job finished (Stage 9). asset_id = the asset;
     * aux64 = 1 (one asset processed); status = per-item result
     * (OK / UNSUPPORTED=skipped / DECODE_ERROR=failed). The Dart indexing
     * controller counts these to drive progress, like SCAN_PROGRESS for faces. */
    PHOTO_EVT_EMBED_PROGRESS   = 10
} photo_event_kind_t;

typedef enum {
    PHOTO_PROVIDER_CPU      = 0,
    PHOTO_PROVIDER_WINML    = 1,
    PHOTO_PROVIDER_DML      = 2,
    PHOTO_PROVIDER_COREML   = 3,
    PHOTO_PROVIDER_CUDA     = 4,
    PHOTO_PROVIDER_OPENVINO = 5
} photo_provider_t;

typedef enum {
    PHOTO_LOG_TRACE = 0,
    PHOTO_LOG_DEBUG = 1,
    PHOTO_LOG_INFO  = 2,
    PHOTO_LOG_WARN  = 3,
    PHOTO_LOG_ERROR = 4
} photo_log_level_t;

/* ------------------------------------------------------------------------- */
/* Configuration                                                             */
/* ------------------------------------------------------------------------- */

/*
 * Engine configuration. Caller fills this and passes to photo_engine_create.
 * The engine copies what it needs; pointers do not need to outlive the call.
 *
 * Zero/NULL fields request engine defaults:
 *   memory_budget_bytes = 256 MiB
 *   disk_budget_bytes   = 16 GiB
 *   decode_threads      = max(2, physical_cores - 1)
 *   io_threads          = 4
 *   ml_threads          = max(1, physical_cores / 2)
 */
typedef struct {
    const char* catalog_path_utf8;   /* SQLite DB path; must be on local FS  */
    const char* cache_path_utf8;     /* LMDB env directory; will be created  */
    const char* models_path_utf8;    /* dir for ML models (M6+); may be NULL */
    uint64_t    memory_budget_bytes; /* memory LRU cap                       */
    uint64_t    disk_budget_bytes;   /* LMDB high-water mark for eviction    */
    uint32_t    decode_threads;
    uint32_t    io_threads;
    uint32_t    ml_threads;
    uint32_t    log_level;           /* photo_log_level_t                    */
    uint32_t    flags;               /* reserved; pass 0                     */
} photo_config_t;

/* ------------------------------------------------------------------------- */
/* Engine lifecycle                                                          */
/* ------------------------------------------------------------------------- */

/*
 * Create an engine. Returns NULL on failure (config invalid, cache path not
 * writable, catalog on a network FS, etc.). Each engine owns its own threads,
 * cache, and catalog; multiple engines may coexist in one process but is not
 * an expected use case.
 *
 * Thread-safety: not safe to call concurrently with itself for the same
 * paths; safe across distinct paths.
 */
PHOTO_API photo_engine_t* photo_engine_create(const photo_config_t* cfg);

/*
 * Destroy an engine. Cancels in-flight work, flushes pending catalog writes,
 * and closes the cache. Blocks until all workers exit. Safe to pass NULL.
 *
 * Thread-safety: must not be called while any other engine call is in flight.
 */
PHOTO_API void photo_engine_destroy(photo_engine_t* engine);

/* Returns a static string. Format: "MAJOR.MINOR.PATCH+gitsha". */
PHOTO_API const char* photo_engine_version(void);

/* ABI version constant for runtime compatibility checks from Dart. */
PHOTO_API uint32_t photo_abi_version(void);

/* ------------------------------------------------------------------------- */
/* Slot lifecycle (called by the photo_native plugin, NOT by Dart)           */
/*                                                                           */
/* A slot is a logical render target. Each visible gallery tile has one      */
/* slot for its lifetime. The plugin pairs each slot with a Flutter texture  */
/* registration of equal lifetime. Stage upgrades swap frames within the     */
/* slot; the Flutter texture ID never changes for the slot's life.           */
/* ------------------------------------------------------------------------- */

PHOTO_API uint64_t photo_slot_create(photo_engine_t* engine,
                                     int32_t initial_w, int32_t initial_h);

PHOTO_API void photo_slot_destroy(photo_engine_t* engine, uint64_t slot_id);

/*
 * Bind a generation token to a slot. Any in-flight request whose generation
 * does not equal the slot's current generation will not produce a visible
 * frame and will not emit STAGE_READY events. Used by the UI when a virtualized
 * cell rebinds to a different asset.
 *
 * Thread-safety: callable from any thread. Returns previous generation.
 */
PHOTO_API uint64_t photo_slot_bind_generation(photo_engine_t* engine,
                                              uint64_t slot_id,
                                              uint64_t generation);

/* ------------------------------------------------------------------------- */
/* Thumbnail requests                                                        */
/*                                                                           */
/* The hot path (photo_thumb_request_fast) takes scalars to avoid per-request */
/* heap allocation on the Dart side. The struct variant (photo_thumb_request) */
/* is retained for cold-path callers and future-field additions.              */
/* ------------------------------------------------------------------------- */

/*
 * Hot path: submit a thumbnail request from Dart with zero heap allocation.
 * The path_utf8 buffer must remain valid only for the duration of this call.
 *
 * Returns a non-zero request ID on success, 0 on rejection (invalid slot,
 * empty path, etc.).
 *
 * Thread-safety: callable from any thread. Designed for p99 < 50 us on the
 * Dart caller side.
 */
PHOTO_API uint64_t photo_thumb_request_fast(
    photo_engine_t* engine,
    uint64_t asset_id,
    uint64_t slot_id,
    uint64_t generation,
    const char* path_utf8,
    uint32_t target_w,
    uint32_t target_h,
    uint32_t wanted_stages_mask,
    uint32_t priority,                  /* photo_priority_t */
    uint32_t flags);

/*
 * Cold path / struct variant. Equivalent to photo_thumb_request_fast but
 * accepts a struct for forward field extension. Cost includes one indirection.
 */
typedef struct {
    uint64_t asset_id;
    uint64_t slot_id;
    uint64_t generation;
    const char* path_utf8;
    uint32_t target_w;
    uint32_t target_h;
    uint32_t wanted_stages_mask;
    uint32_t priority;
    uint32_t flags;
    uint32_t _reserved[3];
} photo_thumb_request_t;

PHOTO_API uint64_t photo_thumb_request(photo_engine_t* engine,
                                       const photo_thumb_request_t* req);

/*
 * Cancel a previously submitted thumbnail request. Cancellation is O(1) and
 * advisory: in-flight work that has already produced a frame may still
 * complete; the result will not be presented if the request's generation
 * no longer matches the slot's current generation. Safe to call with an
 * unknown ID.
 */
PHOTO_API void photo_thumb_cancel(photo_engine_t* engine, uint64_t request_id);

/* ------------------------------------------------------------------------- */
/* Frame acquisition (called by the plugin's texture callback)               */
/* ------------------------------------------------------------------------- */

typedef struct {
    const uint8_t* bgra;       /* device-byte-order BGRA, premultiplied alpha */
    uint32_t       width;
    uint32_t       height;
    uint32_t       stride;     /* bytes per row, >= width * 4                 */
    void*          release_ctx; /* opaque; pass to photo_slot_release         */
} photo_frame_view_t;

/*
 * Acquire the latest presentable frame for a slot. The returned view borrows
 * memory owned by the engine. The caller must call photo_slot_release exactly
 * once with the returned release_ctx. Returns false if no frame is yet
 * available; in that case *out is zeroed and release is not required.
 *
 * Thread-safety: callable from any thread. Typically called from the platform
 * texture callback (macOS raster thread / Windows render thread).
 */
PHOTO_API bool photo_slot_acquire_latest(photo_engine_t* engine,
                                         uint64_t slot_id,
                                         photo_frame_view_t* out);

PHOTO_API void photo_slot_release(photo_engine_t* engine, void* release_ctx);

/* ------------------------------------------------------------------------- */
/* Events (pull-based, Dart drains)                                          */
/* ------------------------------------------------------------------------- */

typedef struct {
    uint32_t kind;            /* photo_event_kind_t                       */
    uint32_t stage;           /* photo_stage_t (where applicable)         */
    int32_t  status;          /* photo_status_t (where applicable)        */
    uint32_t width;
    uint32_t height;
    uint64_t request_id;
    uint64_t asset_id;
    uint64_t slot_id;
    uint64_t generation;
    uint64_t aux64;           /* event-kind dependent payload             */
    uint64_t aux64_b;
    uint32_t _reserved[2];
} photo_event_t;

/*
 * Drain up to `cap` events into `out`. Returns the number written. Drains in
 * FIFO order. Safe to call from one thread only (designed as SPSC: Dart pump
 * is the single consumer).
 */
PHOTO_API size_t photo_poll_events(photo_engine_t* engine,
                                   photo_event_t* out,
                                   size_t cap);

/* ------------------------------------------------------------------------- */
/* Import and catalog                                                        */
/* ------------------------------------------------------------------------- */

/*
 * Begin importing photos from a path. If the path is a file, imports that
 * one asset; if a directory, recurses. Returns a non-zero job ID; progress
 * is reported via PHOTO_EVT_IMPORT_PROGRESS and PHOTO_EVT_IMPORT_COMPLETE
 * events whose request_id matches the returned job ID.
 *
 * flags: reserved; pass 0.
 */
PHOTO_API uint64_t photo_import_path(photo_engine_t* engine,
                                     const char* path_utf8,
                                     uint32_t flags);

/*
 * Re-scan all previously imported locations for changes (added/removed/modified
 * files). Returns a job ID. Progress events as above.
 */
PHOTO_API uint64_t photo_rescan(photo_engine_t* engine, uint32_t flags);

/*
 * One catalog asset row, for hydrating the Dart library after import. The
 * engine-assigned asset_id is stable across runs (unlike a path hash), so face
 * data and the thumbnail cache stay valid across restarts. `path` is a
 * NUL-terminated absolute path; the buffer holds a full Linux PATH_MAX (4096).
 */
typedef struct {
    uint64_t asset_id;
    uint64_t size;          /* bytes                                          */
    uint64_t mtime_ns;      /* last-modified, ns since epoch                  */
    uint32_t width;         /* 0 until a metadata/codec pass fills it         */
    uint32_t height;
    uint32_t orientation;   /* EXIF orientation 1..8                          */
    int32_t  starred;       /* 0/1                                            */
    int32_t  rating;        /* 0..5                                           */
    uint32_t flags;         /* bit0: hidden                                   */
    uint32_t _reserved[3];
    char     path[4096];
} photo_asset_t;

#define PHOTO_ASSET_FLAG_HIDDEN (1u << 0)

/*
 * List catalog assets (hidden excluded), ordered by path. Fills up to `cap`
 * rows into `out` and returns the TOTAL count available — grow and re-call if
 * it exceeds `cap`, mirroring the photo_face_list_* calls. Synchronous.
 */
PHOTO_API size_t photo_list_assets(photo_engine_t* engine,
                                   photo_asset_t* out, size_t cap);

/*
 * EXIF metadata for an asset, extracted on import and stored in the catalog.
 * Strings are libexif-formatted (e.g. aperture "f/2.8"); empty if absent.
 */
typedef struct {
    uint64_t asset_id;
    int32_t  width;
    int32_t  height;
    int32_t  orientation;     /* 1..8                                        */
    int32_t  iso;
    int64_t  datetime_unix;   /* DateTimeOriginal, unix seconds; 0 if absent  */
    int32_t  has_gps;         /* 0/1                                          */
    int32_t  _pad;
    double   gps_lat;
    double   gps_lon;
    char     camera[128];     /* "Make Model"                                 */
    char     lens[128];
    char     aperture[32];
    char     shutter[32];
    char     focal[32];
} photo_metadata_t;

/*
 * Read stored EXIF metadata for an asset into *out. Returns PHOTO_STATUS_OK,
 * PHOTO_STATUS_NOT_FOUND if the asset has no metadata row, or an error code.
 * Synchronous.
 */
PHOTO_API int32_t photo_asset_metadata(photo_engine_t* engine,
                                       uint64_t asset_id,
                                       photo_metadata_t* out);

/* A geotagged asset: its id and decimal-degree coordinates. */
typedef struct {
    uint64_t asset_id;
    double   lat;
    double   lon;
} photo_geopoint_t;

/*
 * List every geotagged asset (those with GPS EXIF). Fills up to `cap` rows and
 * returns the TOTAL count available — grow and re-call if it exceeds `cap`.
 * Synchronous. Drives the map.
 */
PHOTO_API size_t photo_list_geotagged(photo_engine_t* engine,
                                      photo_geopoint_t* out, size_t cap);

/* ------------------------------------------------------------------------- */
/* Albums — user-created collections.                                        */
/* ------------------------------------------------------------------------- */

typedef struct {
    uint64_t album_id;
    uint64_t cover_asset_id;  /* 0 if unset / empty                          */
    int32_t  count;           /* member count                                */
    int32_t  _pad;
    int64_t  created;         /* ns since epoch                              */
    char     name[128];
} photo_album_t;

/* Create an album; returns its id (0 on failure / no catalog). */
PHOTO_API uint64_t photo_album_create(photo_engine_t* engine,
                                      const char* name_utf8);
/* The mutators return photo_status_t (0 == OK). */
PHOTO_API int32_t photo_album_rename(photo_engine_t* engine, uint64_t album_id,
                                     const char* name_utf8);
PHOTO_API int32_t photo_album_delete(photo_engine_t* engine, uint64_t album_id);
PHOTO_API int32_t photo_album_set_cover(photo_engine_t* engine, uint64_t album_id,
                                        uint64_t cover_asset_id);
PHOTO_API int32_t photo_album_add(photo_engine_t* engine, uint64_t album_id,
                                  uint64_t asset_id);
PHOTO_API int32_t photo_album_remove(photo_engine_t* engine, uint64_t album_id,
                                     uint64_t asset_id);

/* List all albums (ordered by creation). Fills up to `cap`, returns total. */
PHOTO_API size_t photo_album_list(photo_engine_t* engine,
                                  photo_album_t* out, size_t cap);
/* Member asset ids of one album, in order. Fills up to `cap`, returns total. */
PHOTO_API size_t photo_album_members(photo_engine_t* engine, uint64_t album_id,
                                     uint64_t* out, size_t cap);

/* ------------------------------------------------------------------------- */
/* Smart collections — seeded virtual views (hidden assets excluded).         */
/*                                                                           */
/* Return asset-id arrays (the UI resolves ids → paths), mirroring            */
/* photo_album_members: fill up to `cap` and return the TOTAL available.      */
/* "All photos" reuses photo_list_assets, so it needs no call here.           */
/* ------------------------------------------------------------------------- */

/* The `limit` most-recently-imported asset ids, newest first. */
PHOTO_API size_t photo_smart_recent(photo_engine_t* engine, int32_t limit,
                                    uint64_t* out, size_t cap);
/* Every starred asset id. */
PHOTO_API size_t photo_smart_starred(photo_engine_t* engine,
                                     uint64_t* out, size_t cap);

/* ------------------------------------------------------------------------- */
/* Organize state — star / rating / caption / tags.                          */
/*                                                                           */
/* All catalog-only: per DECISIONS D1, user-authored metadata is NOT written  */
/* back to the original files in v1. The mutators return photo_status_t.      */
/* ------------------------------------------------------------------------- */

PHOTO_API int32_t photo_asset_set_starred(photo_engine_t* engine,
                                          uint64_t asset_id, int32_t starred);
PHOTO_API int32_t photo_asset_set_rating(photo_engine_t* engine,
                                         uint64_t asset_id, int32_t rating);
PHOTO_API int32_t photo_asset_set_caption(photo_engine_t* engine,
                                          uint64_t asset_id,
                                          const char* caption_utf8);
/* Hide/unhide a single asset (excludes it from photo_list_assets). */
PHOTO_API int32_t photo_asset_set_hidden(photo_engine_t* engine,
                                         uint64_t asset_id, int32_t hidden);

/* ------------------------------------------------------------------------- */
/* Folder-level hide.                                                         */
/*                                                                           */
/* Hiding a folder records a persistent rule (assets re-imported beneath it   */
/* stay hidden) AND sweeps existing assets at/under it hidden; un-hiding      */
/* sweeps them visible. Matched on a separator boundary so /a/photos never    */
/* matches /a/photoshop.                                                      */
/* ------------------------------------------------------------------------- */

PHOTO_API int32_t photo_folder_set_hidden(photo_engine_t* engine,
                                          const char* path_utf8, int32_t hidden);
/*
 * Hidden folder paths as NUL-separated UTF-8 ("/a\0/b\0…"). Fills up to `cap`
 * bytes into `out` and returns the TOTAL bytes needed — grow and re-call.
 */
PHOTO_API size_t photo_hidden_folders(photo_engine_t* engine,
                                      char* out, size_t cap);
/*
 * Paths of individually-hidden assets as NUL-separated UTF-8. Same buffer
 * protocol. photo_list_assets excludes hidden assets, so this is how the UI
 * hydrates its hide filter on startup.
 */
PHOTO_API size_t photo_hidden_assets(photo_engine_t* engine,
                                     char* out, size_t cap);

/* ------------------------------------------------------------------------- */
/* Maintenance — compaction, stats, checkpoint.                               */
/* ------------------------------------------------------------------------- */

typedef struct {
    int64_t page_count;      /* pages currently in the DB file              */
    int64_t freelist_count;  /* unused pages reclaimable by VACUUM          */
    int64_t page_size;       /* bytes per page (DB size ≈ page_count*size)  */
} photo_catalog_stats_t;

/* Read catalog size stats into *out. Returns photo_status_t. Synchronous. */
PHOTO_API int32_t photo_catalog_stats(photo_engine_t* engine,
                                      photo_catalog_stats_t* out);
/*
 * Checkpoint the WAL then VACUUM, on the idle lane (VACUUM can be slow).
 * Returns a request id; emits PHOTO_EVT_MAINTENANCE_COMPLETE on completion.
 */
PHOTO_API uint64_t photo_catalog_compact(photo_engine_t* engine);
/* Synchronous checkpoint + VACUUM (blocks until done). For on-exit cleanup,
 * where the async lane wouldn't finish before the process tears down. */
PHOTO_API int32_t photo_catalog_compact_sync(photo_engine_t* engine);
/* Flush the WAL into the main DB and truncate it (cheap; pre-copy helper). */
PHOTO_API int32_t photo_catalog_checkpoint(photo_engine_t* engine);

/* ------------------------------------------------------------------------- */
/* Relocate — rebase asset paths after the photo library moved on disk.       */
/* ------------------------------------------------------------------------- */
/*
 * Rewrite every stored path at/under old_prefix to sit under new_prefix
 * instead, preserving asset ids so faces/albums/tags survive the move.
 * new_prefix must exist on disk. Returns photo_status_t (NOT_FOUND when the new
 * root is missing). Synchronous + transactional.
 */
PHOTO_API int32_t photo_library_rebase(photo_engine_t* engine,
                                       const char* old_prefix_utf8,
                                       const char* new_prefix_utf8);

/* Star / rating / caption for one asset. */
typedef struct {
    int32_t starred;   /* 0/1                                                */
    int32_t rating;    /* 0..5                                               */
    char    caption[512];
} photo_organize_t;

PHOTO_API int32_t photo_asset_organize(photo_engine_t* engine, uint64_t asset_id,
                                       photo_organize_t* out);

PHOTO_API int32_t photo_asset_add_tag(photo_engine_t* engine, uint64_t asset_id,
                                      const char* tag_utf8);
PHOTO_API int32_t photo_asset_remove_tag(photo_engine_t* engine,
                                         uint64_t asset_id, const char* tag_utf8);

/*
 * Tags of an asset as NUL-separated UTF-8 ("tag1\0tag2\0…"). Fills up to `cap`
 * bytes into `out` and returns the TOTAL bytes needed — grow and re-call if it
 * exceeds `cap`.
 */
PHOTO_API size_t photo_asset_tags(photo_engine_t* engine, uint64_t asset_id,
                                  char* out, size_t cap);

/* ------------------------------------------------------------------------- */
/* ML (added in M6)                                                          */
/* ------------------------------------------------------------------------- */

/*
 * Probe whether a provider is usable on this machine. Results are cached
 * per (provider, driver_version, gpu_uuid, ort_version). Synchronous; bounded
 * to ~2s per probe. Returns photo_status_t.
 */
PHOTO_API int32_t photo_provider_probe(photo_engine_t* engine,
                                       int32_t provider);

/*
 * Schedule a face scan for an asset. Detection -> alignment -> embedding,
 * with results stored in the catalog. Emits PHOTO_EVT_SCAN_PROGRESS while
 * running. Returns a job ID.
 */
PHOTO_API uint64_t photo_face_scan(photo_engine_t* engine,
                                   uint64_t asset_id,
                                   uint32_t flags);

/* ------------------------------------------------------------------------- */
/* Clustering (added in M7)                                                  */
/* ------------------------------------------------------------------------- */

PHOTO_API uint64_t photo_face_approve(photo_engine_t* engine,
                                      uint64_t cluster_id,
                                      uint64_t embedding_id);

PHOTO_API uint64_t photo_face_reject(photo_engine_t* engine,
                                     uint64_t cluster_id,
                                     uint64_t embedding_id);

/*
 * Trigger a full HDBSCAN rebuild. Expensive (minutes on a large library).
 * Runs in the idle lane. Emits PHOTO_EVT_CLUSTER_UPDATED on completion.
 */
PHOTO_API uint64_t photo_cluster_rebuild(photo_engine_t* engine, uint32_t flags);

/*
 * Promote an unconfirmed cluster into a named person: confirms every face in
 * `cluster_id` into a person named `name_utf8`, merging into an existing person
 * of the same name or creating a new one. Runs in the idle lane; emits
 * PHOTO_EVT_CLUSTER_UPDATED on completion. Returns a request id.
 */
PHOTO_API uint64_t photo_face_name_cluster(photo_engine_t* engine,
                                           int64_t cluster_id,
                                           const char* name_utf8);

/* ------------------------------------------------------------------------- */
/* Face read-back (UI queries) — synchronous, metadata only.                 */
/*                                                                           */
/* No image bytes cross the boundary (the app invariant): a face carries its */
/* asset_id + source-pixel box, and the UI renders it by clipping the asset  */
/* thumbnail to that box via the existing texture pipeline. All list_* calls */
/* fill up to `cap` rows into the caller's buffer and return the TOTAL count */
/* available (which may exceed `cap` — grow and re-call), mirroring          */
/* photo_poll_events.                                                        */
/* ------------------------------------------------------------------------- */

/* A person = a confirmed/named cluster. `name` is NUL-terminated UTF-8. */
typedef struct {
    uint64_t person_id;
    int64_t  cluster_id;        /* representative cluster, -1 if none        */
    uint64_t cover_face_id;     /* best face for the avatar (highest quality)*/
    int32_t  face_count;
    int32_t  confirmed_count;
    int32_t  confirmed;         /* 0/1                                       */
    int32_t  _pad;
    char     name[128];
} photo_person_t;

/* One face row: detection metadata + cluster/person links. */
typedef struct {
    uint64_t face_id;
    uint64_t asset_id;
    int64_t  cluster_id;        /* -1 = unassigned                           */
    int64_t  person_id;         /* -1 = unconfirmed                          */
    float    box_x, box_y, box_w, box_h;   /* source-image pixels            */
    float    det_score;
    float    quality;
    int32_t  confirmed;         /* 0 = suggestion, 1 = user-confirmed        */
    int32_t  _pad;
} photo_face_t;

/* Confirmed/named people. */
PHOTO_API size_t photo_face_list_people(photo_engine_t* engine,
                                        photo_person_t* out, size_t cap);

/* Unconfirmed cluster buckets (the "unnamed faces" groups), as person rows
 * (person_id == 0, cluster_id set, name empty). */
PHOTO_API size_t photo_face_list_clusters(photo_engine_t* engine,
                                          photo_person_t* out, size_t cap);

/* Members of one cluster (confirmed + suggested), highest quality first. */
PHOTO_API size_t photo_face_list_cluster_faces(photo_engine_t* engine,
                                               int64_t cluster_id,
                                               photo_face_t* out, size_t cap);

/* Unconfirmed (suggested) faces for a person — the suggest-and-confirm queue. */
PHOTO_API size_t photo_face_list_suggestions(photo_engine_t* engine,
                                             uint64_t person_id,
                                             photo_face_t* out, size_t cap);

/* Faces detected in one asset (drives the info-panel People tab). */
PHOTO_API size_t photo_face_list_for_asset(photo_engine_t* engine,
                                           uint64_t asset_id,
                                           photo_face_t* out, size_t cap);

/* Name (or rename) a person. Returns photo_status_t. */
PHOTO_API int32_t photo_face_name_person(photo_engine_t* engine,
                                         uint64_t person_id,
                                         const char* name_utf8);

/* ------------------------------------------------------------------------- */
/* Semantic search & discovery (Stage 9).                                    */
/*                                                                           */
/* A retrieval index of per-asset embeddings (the `embedding` catalog table)  */
/* plus saved searches. Embeddings are produced by a SWAPPABLE model — the    */
/* dependency-free deterministic colour backend by default, the real ONNX     */
/* model (siglip2 / PE-Core) when its files are present. Every row records the */
/* producing model so a switch re-queues stale rows. No image bytes cross the  */
/* boundary; the query→image ranking is done natively over stored vectors.     */
/* ------------------------------------------------------------------------- */

/*
 * Schedule embedding for one asset on the idle lane. Emits PHOTO_EVT_EMBED_PROGRESS
 * on completion. Returns a request id (0 if no catalog / no embedder). Idempotent
 * at the pipeline level: callers build the work list from photo_embedding_pending.
 */
PHOTO_API uint64_t photo_embedding_scan(photo_engine_t* engine, uint64_t asset_id);

/* Embedding progress counts for the indexing UI. `total` is all non-hidden
 * assets; `pending` includes assets with no row yet. */
typedef struct {
    int64_t done;
    int64_t pending;
    int64_t processing;
    int64_t failed;
    int64_t skipped;
    int64_t total;
} photo_embed_counts_t;
PHOTO_API int32_t photo_embedding_counts(photo_engine_t* engine,
                                         photo_embed_counts_t* out);

/*
 * Asset ids that still need embedding for the ACTIVE model — the resume queue.
 * Fills up to `cap` and returns the TOTAL available (grow + re-call). limit<0
 * means no server-side cap.
 */
PHOTO_API size_t photo_embedding_pending(photo_engine_t* engine, int32_t limit,
                                         uint64_t* out, size_t cap);

/* Flip every failed embedding back to pending (an explicit "retry failed"). */
PHOTO_API int32_t photo_embedding_retry_failed(photo_engine_t* engine);

/* (asset_id, dominant colour 0xRRGGBB) for every embedded asset — drives colour
 * search. Fills up to `cap`, returns the TOTAL available (grow + re-call). */
typedef struct {
    uint64_t asset_id;
    int32_t  rgb;    /* 0xRRGGBB */
    int32_t  _pad;
} photo_asset_color_t;
PHOTO_API size_t photo_embedding_colors(photo_engine_t* engine,
                                        photo_asset_color_t* out, size_t cap);

/*
 * Embed a text query into the active model's vector space. Writes up to `cap`
 * floats into `out_vec` and returns the model dimensionality (which may exceed
 * `cap` — grow + re-call). Returns 0 if there is no embedder.
 */
PHOTO_API uint32_t photo_embed_text(photo_engine_t* engine,
                                    const char* query_utf8,
                                    float* out_vec, uint32_t cap);

/* One ranked search result. */
typedef struct {
    uint64_t asset_id;
    float    score;   /* cosine similarity in [-1, 1] */
    float    _pad;
} photo_search_hit_t;

/*
 * Cosine-rank `query_vec` (dim floats) over the done embeddings, optionally
 * restricted to `candidates` (n_candidates asset ids; NULL/0 = all). Fills up
 * to `cap` hits (score-descending) into `out` and returns the number written.
 */
PHOTO_API size_t photo_semantic_search(photo_engine_t* engine,
                                       const float* query_vec, uint32_t dim,
                                       const uint64_t* candidates,
                                       size_t n_candidates,
                                       photo_search_hit_t* out, size_t cap);

/* Bit mask for photo_semantic_release_sessions. */
#define PHOTO_SEMANTIC_RELEASE_IMAGE (1u << 0)
#define PHOTO_SEMANTIC_RELEASE_TEXT  (1u << 1)

/*
 * Reclaim the RAM of lazily-loaded semantic inference sessions. The UI calls
 * this with ..._IMAGE when the embedding-indexing queue drains (the image
 * tower holds ~hundreds of MB only needed while indexing) and with ..._TEXT
 * after a search idle timeout. Safe concurrently with in-flight embeds (they
 * complete on their own reference); the next embed/search transparently
 * reloads from disk (~1 s). No-op for the deterministic backend.
 */
PHOTO_API void photo_semantic_release_sessions(photo_engine_t* engine,
                                               uint32_t mask);

/*
 * Re-probe the models directory and swap the semantic embedder in — call after
 * the first-run model download lands so real text→image search activates
 * without an app restart. In-flight embeds finish on the old service. Returns
 * the active model's dimensionality (0 if no engine). A model change re-queues
 * stale embedding rows via photo_embedding_pending.
 */
PHOTO_API int32_t photo_semantic_reload(photo_engine_t* engine);

/* Saved searches (saved_search table). query_json is opaque UTF-8. */
typedef struct {
    uint64_t id;
    int64_t  created;   /* ns since epoch */
    char     name[128];
} photo_saved_search_t;

PHOTO_API uint64_t photo_saved_search_create(photo_engine_t* engine,
                                             const char* name_utf8,
                                             const char* query_json_utf8);
PHOTO_API int32_t  photo_saved_search_delete(photo_engine_t* engine, uint64_t id);
/* List saved searches (newest first). Fills up to `cap`, returns TOTAL. */
PHOTO_API size_t   photo_saved_search_list(photo_engine_t* engine,
                                           photo_saved_search_t* out, size_t cap);
/*
 * The opaque query_json of one saved search into `out` (NUL-terminated UTF-8).
 * Returns the TOTAL bytes needed (grow + re-call), mirroring photo_asset_tags.
 */
PHOTO_API size_t   photo_saved_search_query(photo_engine_t* engine, uint64_t id,
                                            char* out, size_t cap);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif /* PHOTO_CORE_H */
