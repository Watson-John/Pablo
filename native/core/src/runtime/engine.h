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
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "edit/edit_spec.h"
#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"
#include "thumb/thumb_service.h"

#ifdef PHOTO_HAVE_SQLITE
#include "catalog/catalog.h"
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

    // ── Non-destructive edit stack ─────────────────────────────────────────
    // The serialized `key=value;` spec for an asset, "" if none. Locked read.
    std::string get_edits(int64_t asset_id) const;
    // Persist the spec (catalog write first, then swap the in-memory COW map) and
    // return the new content_rev. An identity spec clears the edit and returns 0.
    // The caller (Dart) rebinds the visible slot's generation off this rev so the
    // gallery tile repaints — native has no asset→slot index by design.
    uint64_t set_edits(int64_t asset_id, const std::string& spec);
    // Clear the saved edit (revert to original). Same as set_edits("").
    void     revert_edits(int64_t asset_id);
    // Current content_rev for an asset (0 = unedited).
    uint64_t content_rev(int64_t asset_id) const;
#endif

    // Live preview: parse `spec_str` and render it transiently to the slot on the
    // interactive lane (no cache, no catalog). Available without a catalog, so it
    // sits outside the SQLite guard. No-op without libvips.
    void preview_edits(uint64_t slot_id, uint64_t generation,
                       const std::string& path, uint32_t target_w,
                       uint32_t target_h, const std::string& spec_str);

    // Export `spec` over a full-res decode of `src` to `dst` on the idle lane
    // (async). Returns a request id; emits PHOTO_EVT_EXPORT_COMPLETE. No catalog
    // needed, so these sit outside the SQLite guard. 0 on immediate rejection.
    uint64_t export_path(const std::string& src, const std::string& dst,
                         const std::string& spec_str, int quality);
    uint64_t save_layered(const std::string& src, const std::string& dst,
                          const std::string& spec_str);

    // Red-eye auto-detect: decode `path`, look up this asset's stored eye
    // landmarks (from the face scan), and return a red-eye brush Region for every
    // eye that actually contains a red pupil. The caller adds them to the edit
    // spec (same non-destructive path as manual dabs). `spec_str` is the caller's
    // CURRENT working edit spec: landmarks live in original-image space, so when
    // the spec has geometry (crop/rotate/straighten) each region is mapped into
    // the post-geometry space the retouch render uses; eyes cropped out of frame
    // are dropped, never misplaced. Empty without the face models (Linux/Windows
    // plugins) or when no eye is red. Synchronous — the caller invokes it off the
    // UI thread if the decode cost matters.
    std::vector<edit::Region> detect_redeye(int64_t asset_id,
                                            const std::string& path,
                                            const std::string& spec_str = "");
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

    // ── In-memory edit map (copy-on-write) ──────────────────────────────────
    // asset_id → {content_rev, parsed spec}. Render workers read it via an atomic
    // shared_ptr load (std::atomic_load free function — the std::atomic<shared_ptr>
    // specialization isn't available on libc++); mutations rebuild a fresh map and
    // atomic-store it under edits_write_mu_. This keeps the thumbnail hot path off
    // SQLite and off the spec parser, with no writer-starvation under scroll.
    using EditMap = std::unordered_map<int64_t, edit::EditEntry>;
    std::shared_ptr<const EditMap> edits_{std::make_shared<const EditMap>()};
    std::mutex edits_write_mu_;
    // Request-id source for async export / layered-save (catalog-independent).
    std::atomic<uint64_t> next_export_id_{1};
    // Lookup injected into ThumbService (lock-free read of the COW snapshot).
    edit::EditEntry edit_lookup(int64_t asset_id) const;

public:
    // Asset ids that currently have a (non-identity) saved edit — for the
    // gallery's "edited" badge. Reads the lock-free COW snapshot, so it is cheap
    // and available with or without a catalog.
    std::vector<int64_t> edited_asset_ids() const;

private:
    // Rebuild the map with one entry set (entry != nullptr) or erased (nullptr).
    void store_edit_entry(int64_t asset_id, const edit::EditEntry* entry);

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
