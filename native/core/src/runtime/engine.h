// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// engine.h — composition root for the native core.
//
// Engine owns the slot store, the event ring, and (in later milestones) the
// scheduler / cache / catalog / ML runtime. M1 holds the slot+event subset
// only.

#pragma once

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"
#include "thumb/thumb_service.h"

#ifdef PHOTO_HAVE_SQLITE
#include "catalog/catalog.h"
#include "semantic/semantic_search.h"
#include "semantic/semantic_service.h"
#endif

#ifdef PHOTO_HAVE_FACES
#include "faces/face_service.h"
#endif

namespace photo {

class ThumbCache;

class Engine {
public:
    // Create from a (validated) configuration. May throw on fatal init.
    // Wrapped by photo_engine_create which returns nullptr on failure.
    static std::unique_ptr<Engine> create(const photo_config_t& cfg);

    ~Engine();

    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    SlotStore&    slots()        { return slots_; }
    EventRing&    events()       { return events_; }
    JobSystem&    jobs()         { return jobs_; }
    ThumbService& thumbs()       { return thumbs_; }
#ifdef PHOTO_HAVE_SQLITE
    // The durable asset catalog, or nullptr if SQLite init failed.
    catalog::Catalog* catalog()  { return catalog_.get(); }

    // Recursively import `path` on the idle lane: upsert every image file into
    // the catalog and emit IMPORT_PROGRESS / IMPORT_COMPLETE. Returns a request
    // id (0 if there is no catalog).
    uint64_t import_path(const std::string& path);
    // Re-walk every recorded import root, upsert changes, and prune assets
    // whose backing file is gone. Returns a request id.
    uint64_t rescan();
    // Snapshot of catalog assets (hidden excluded) for Dart hydration.
    std::vector<catalog::AssetRecord> list_assets() const;
    // Source path for an asset id, or "" if unknown. Locked, so it is safe to
    // call concurrently with an in-flight import.
    std::string path_for_asset(int64_t asset_id) const;
    // Stored EXIF metadata for an asset (locked); nullopt if none.
    std::optional<exif::AssetMetadata> asset_metadata(int64_t asset_id) const;
    // Every geotagged asset (locked) — drives the map.
    std::vector<catalog::Catalog::GeoPoint> list_geotagged() const;
    // Manual geotag override (locked). set with lat/lon, or clear to fall back to
    // EXIF GPS. Takes precedence in list_geotagged().
    void set_geo(int64_t asset_id, double lat, double lon);
    void clear_geo(int64_t asset_id);

    // Albums (all locked). create_album stamps the creation time itself.
    int64_t create_album(const std::string& name);
    void    rename_album(int64_t album_id, const std::string& name);
    void    delete_album(int64_t album_id);
    void    set_album_cover(int64_t album_id, int64_t cover_asset_id);
    void    add_to_album(int64_t album_id, int64_t asset_id);
    void    remove_from_album(int64_t album_id, int64_t asset_id);
    std::vector<catalog::Catalog::AlbumRecord> list_albums() const;
    std::vector<int64_t> album_members(int64_t album_id) const;

    // Organize state (all locked). Catalog-only — no file write-back (D1).
    void set_starred(int64_t asset_id, bool v);
    void set_rating(int64_t asset_id, int32_t v);
    void set_caption(int64_t asset_id, const std::string& v);
    void set_hidden(int64_t asset_id, bool v);
    void add_tag(int64_t asset_id, const std::string& tag);
    void remove_tag(int64_t asset_id, const std::string& tag);
    std::vector<std::string> tags_for_asset(int64_t asset_id) const;
    // Full asset row (for reading star/rating/caption); nullopt if unknown.
    std::optional<catalog::AssetRecord> asset(int64_t asset_id) const;

    // Folder-level hide (all locked). Hiding records the rule AND sweeps
    // existing assets under the folder hidden; un-hiding sweeps them visible.
    // run_import re-applies the rule to assets (re)imported under a hidden dir.
    void set_folder_hidden(const std::string& path, bool v);
    std::vector<std::string> hidden_folders() const;
    // Paths of individually-hidden assets, for hydrating the UI hide filter.
    std::vector<std::string> hidden_asset_paths() const;

    // Smart collections (all locked). Recent = `limit` newest by import_time.
    std::vector<int64_t> recent_assets(int limit) const;
    std::vector<int64_t> starred_assets() const;

    // Maintenance. catalog_stats() is synchronous/locked. compact_catalog()
    // runs VACUUM on the idle lane (it can be slow) and emits
    // PHOTO_EVT_MAINTENANCE_COMPLETE; returns a request id (0 if no catalog).
    // catalog_checkpoint() flushes the WAL (cheap; pre-copy helper).
    catalog::Catalog::Stats catalog_stats() const;
    uint64_t compact_catalog();
    // Synchronous checkpoint + VACUUM (locked) — for the on-exit cleanup, which
    // must finish before the process tears down (the async lane wouldn't).
    void     compact_catalog_sync();
    void     catalog_checkpoint();

    // Relocate: rebase every stored path from old_prefix to new_prefix (locked,
    // transactional). Validates new_prefix exists on disk first. Returns rows
    // rewritten, or -1 if new_prefix does not exist.
    int64_t rebase_paths(const std::string& old_prefix,
                         const std::string& new_prefix);

    // ── Semantic search & discovery (Stage 9) ───────────────────────────────
    // Schedule embedding for one asset on the idle lane (lowest priority, so it
    // never preempts interactive thumbnails). Decode+embed runs off-lock; the
    // resulting row is persisted under catalog_mu_. Emits PHOTO_EVT_EMBED_PROGRESS
    // (status = per-item result). Returns a request id (0 if no catalog).
    uint64_t embedding_scan(int64_t asset_id);
    // Asset ids that still need embedding for the ACTIVE model — the resume
    // queue (no row, pending, or a done row from a different model). limit<0 =
    // no cap. Locked.
    std::vector<int64_t> pending_embedding_ids(int limit = -1) const;
    catalog::Catalog::EmbeddingCounts embedding_counts() const;   // progress UI
    void retry_failed_embeddings();                               // explicit retry
    std::optional<catalog::Catalog::EmbeddingRecord> get_embedding(
        int64_t asset_id) const;
    int         embedding_dim() const;       // active model's vector length
    std::string embedding_model_id() const;  // active model id (for diagnostics)
    // (asset_id, 0xRRGGBB) for every embedded asset — drives colour search.
    std::vector<std::pair<int64_t, int32_t>> dominant_colors() const;
    // Text-query embedding (pure CPU, no lock) + cosine ranking over the done
    // embeddings. `candidates` (if non-empty) restricts to a metadata-filtered
    // subset; results are score-descending, capped at `cap`.
    std::vector<float> embed_text(const std::string& query) const;
    std::vector<semantic::SearchHit> semantic_search(
        const std::vector<float>& query,
        const std::vector<int64_t>& candidates, size_t cap) const;
    // Reclaim ONNX-session RAM (semantic::kRelease* mask): the UI calls this
    // when the indexing queue drains (image tower) and on search idle timeout
    // (text tower). Next embed/search transparently reloads.
    void release_semantic_sessions(uint32_t mask);
    // Re-probe the models dir and swap the embedder in (call after the
    // first-run model download lands — no app restart needed). Returns the
    // active model's dim. A model change re-queues stale embedding rows.
    int reload_semantic();

    // Saved searches (all locked). query_json is opaque to the engine.
    int64_t create_saved_search(const std::string& name,
                                const std::string& query_json);
    void    delete_saved_search(int64_t id);
    std::vector<catalog::Catalog::SavedSearchRecord> list_saved_searches() const;
    std::optional<catalog::Catalog::SavedSearchRecord> get_saved_search(
        int64_t id) const;
#endif
#ifdef PHOTO_HAVE_FACES
    faces::FaceService& faces()  { return faces_; }
#endif

    const std::filesystem::path& catalog_path() const { return catalog_path_; }
    const std::filesystem::path& cache_path()   const { return cache_path_; }
    const std::filesystem::path& models_path()  const { return models_path_; }

    uint64_t memory_budget_bytes() const { return memory_budget_; }
    uint64_t disk_budget_bytes()   const { return disk_budget_; }

private:
    Engine(std::filesystem::path catalog_path,
           std::filesystem::path cache_path,
           std::filesystem::path models_path,
           uint64_t memory_budget,
           uint64_t disk_budget,
           uint32_t decode_threads);

#ifdef PHOTO_HAVE_SQLITE
    // Body of an import/rescan job: walk `roots`, upsert image files, emit
    // progress, and (rescan only) prune assets whose file no longer exists.
    void run_import(uint64_t request_id, std::vector<std::string> roots,
                    bool prune);
#endif

    // Owned thumbnail cache. Declared first so it is destroyed last — after
    // the job system's workers, which reference it through ThumbService.
    std::unique_ptr<ThumbCache> cache_;

#ifdef PHOTO_HAVE_SQLITE
    // The asset catalog (SQLite). Declared before the job system / services so
    // it outlives any worker that touches it. nullptr if SQLite init failed.
    std::unique_ptr<catalog::Catalog> catalog_;
    // Serializes catalog access across the import job thread and the (Dart pump
    // thread) read calls. SQLite's serialized mode protects single statements;
    // this guards our multi-statement sequences (e.g. upsert's insert+select).
    mutable std::mutex                catalog_mu_;
    // Serializes import/rescan jobs. run_import deliberately releases
    // catalog_mu_ during its filesystem walk (so reads aren't blocked), so
    // without this two concurrent import/rescan jobs on the worker pool could
    // interleave their snapshot→diff→apply→prune phases. Held for a whole job.
    std::mutex                        import_mu_;
    std::atomic<uint64_t>             next_import_id_{1};
    // The semantic embedder: the real ONNX model when present, else the
    // dependency-free deterministic backend. Constructed at engine start and
    // hot-swappable via reload_semantic (after the first-run model download).
    // Accessed through std::atomic_load/store free functions (libc++ has no
    // std::atomic<shared_ptr>); every caller takes a local copy so a reload
    // can never free a service out from under an in-flight embed.
    std::shared_ptr<semantic::SemanticService> semantic_;
    std::shared_ptr<semantic::SemanticService> semantic_service() const {
        return std::atomic_load(&semantic_);
    }
    std::shared_ptr<semantic::SemanticService> make_semantic_service() const;
    // Semantic-search working set: a DISK-resident int8 sidecar file
    // (cache_path/semantic_index.bin), memory-mapped — so queries neither
    // re-read N BLOBs out of SQLite (≈100 MB copied per search at 30k assets)
    // nor pin a ~100 MB fp32 heap; the OS page cache owns residency and
    // reclaims the (clean, file-backed) pages under memory pressure. Searches
    // rank against an immutable mapping snapshot taken outside catalog_mu_;
    // any engine-side embedding write bumps the generation and clears the
    // pointer, and the next search lazily rebuilds the file from the catalog
    // (the durable fp32 source of truth). Across restarts the file is adopted
    // without a rebuild when its stamp matches Catalog::embedding_stamp().
    // The generation counter closes the lost-invalidation race: a search that
    // read the DB before a concurrent write must not publish a stale index.
    // Only the pointer swap is under semantic_index_mu_ — never the SQLite
    // read, the file write, or the ranking scan.
    mutable std::shared_ptr<const semantic::SidecarIndex> sidecar_;
    mutable uint64_t                                      sidecar_built_gen_ = 0;
    mutable std::mutex                                    semantic_index_mu_;
    mutable std::atomic<uint64_t>                         semantic_index_gen_{0};
    void invalidate_semantic_index();
#endif

    SlotStore                 slots_;
    // Sized for scroll bursts: dozens of visible tiles each emit several
    // stage-ready events, plus face-scan progress. A small ring overflowed and
    // dropped stage upgrades, leaving thumbnails stuck on the placeholder.
    EventRing                 events_{16384};
    JobSystem                 jobs_;
    ThumbService              thumbs_;
#ifdef PHOTO_HAVE_FACES
    faces::FaceService        faces_;
#endif

    std::filesystem::path     catalog_path_;
    std::filesystem::path     cache_path_;
    std::filesystem::path     models_path_;
    uint64_t                  memory_budget_;
    uint64_t                  disk_budget_;
};

}  // namespace photo
