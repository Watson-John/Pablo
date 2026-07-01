// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// catalog.h — the durable asset catalog: a SQLite `asset` table that is the
// source of truth for which files are in the library and their identity
// (asset_id ⇄ path), file stats, dimensions, and user-authored organize state
// (star / rating / caption / hidden). Import/rescan write it; the face pipeline
// keys off the same asset ids (the `face.asset_id` column references
// `asset.id`); the UI reads it back through the C ABI.
//
// The catalog opens its own connection to the Pablo DB file. The face tables
// (faces/store.cpp) live in the same file on a separate connection; WAL keeps
// the two consistent. Consolidating onto a single shared connection (per
// DECISIONS D9's single-writer lane) is a later, behavior-neutral refactor.

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "exif/exif.h"  // AssetMetadata (a pure, libexif-free struct)

struct sqlite3;  // fwd; the full header is an implementation detail

namespace photo::catalog {

// One row of the `asset` table. POD-ish; the catalog fills `id` on upsert.
struct AssetRecord {
    int64_t     id = 0;            // catalog primary key == asset_id everywhere
    std::string path;             // absolute path, UNIQUE
    std::string folder;           // parent directory (for the Folders view)
    std::string filename;         // leaf name
    int64_t     size = 0;         // bytes
    int64_t     mtime_ns = 0;     // last-modified, ns since epoch
    std::string content_hash;     // optional; populated lazily (dedup, M-later)
    int32_t     width = 0;
    int32_t     height = 0;
    int32_t     orientation = 1;  // EXIF orientation 1..8
    std::string format;           // "jpeg", "png", "heic", …
    int64_t     import_time = 0;  // ns since epoch when first imported
    bool        starred = false;
    int32_t     rating = 0;       // 0..5
    std::string caption;
    bool        hidden = false;
};

// Owns one SQLite connection to the catalog DB. Thread-compatible, not
// thread-safe: callers serialize writes through the engine's job lanes. All
// methods throw std::runtime_error on SQLite failure (the C ABI layer wraps).
class Catalog {
public:
    // Opens (creating) the DB at `db_path`, applies pragmas, and migrates the
    // schema to the current version. Throws on open failure.
    explicit Catalog(const std::string& db_path);
    ~Catalog();

    Catalog(const Catalog&) = delete;
    Catalog& operator=(const Catalog&) = delete;

    bool     ok() const { return db_ != nullptr; }
    sqlite3* db() const { return db_; }  // for the future shared-connection move

    // Insert by unique path, or update the file-derived fields of an existing
    // row (user fields — star/rating/caption/hidden — are preserved across a
    // re-import). Returns the asset id and sets rec.id.
    int64_t upsert_asset(AssetRecord& rec);

    std::optional<AssetRecord> asset_by_id(int64_t id) const;
    std::optional<AssetRecord> asset_by_path(const std::string& path) const;
    // Source path for an asset id, or "" if unknown. The hot lookup the face
    // scan and decode paths need.
    std::string                path_by_id(int64_t id) const;

    // All assets ordered by path (hidden ones excluded unless include_hidden).
    std::vector<AssetRecord> list_assets(bool include_hidden = false) const;
    int64_t                  count() const;

    // Lightweight (path → size, mtime_ns) projection of every asset, for
    // incremental-rescan change detection — avoids loading full AssetRecords
    // just to compare file stats. Includes hidden assets (rescan sees all).
    struct FileStat { int64_t size; int64_t mtime_ns; };
    std::unordered_map<std::string, FileStat> file_stats() const;

    // Organize state (wired to the UI in a later stage; cheap to land now).
    void set_starred(int64_t id, bool v);
    void set_rating(int64_t id, int32_t v);
    void set_caption(int64_t id, const std::string& v);
    void set_hidden(int64_t id, bool v);

    // Remove an asset row (file ops / rescan-removed). Face rows referencing it
    // are left to the face subsystem to reconcile.
    void remove_asset(int64_t id);

    // Import roots — the folders the user imported. rescan re-walks these to
    // pick up files added/removed outside the app.
    void                     add_import_root(const std::string& path);
    std::vector<std::string> import_roots() const;

    // ── Folder-level hide (hidden_folder table) ─────────────────────────────
    // A hidden folder forces every asset at or under its path to hidden on
    // (re)import; un-hiding sweeps those assets back to visible. Per-asset
    // set_hidden is the finer-grained toggle. Paths are matched on a separator
    // boundary so /a/photos never matches /a/photoshop.
    void add_hidden_folder(const std::string& path);     // INSERT OR IGNORE
    void remove_hidden_folder(const std::string& path);  // DELETE only
    std::vector<std::string> hidden_folders() const;     // sorted
    // True if `path` is at or under any hidden folder.
    bool is_path_hidden(const std::string& path) const;
    // Set hidden=v on every asset at or under `folder` (the un-/hide sweep).
    void set_assets_hidden_under(const std::string& folder, bool v);
    // Paths of every individually-hidden asset — for hydrating the UI's hide
    // filter (list_assets excludes hidden, so it can't surface these).
    std::vector<std::string> hidden_asset_paths() const;

    // ── Smart collections (seeded virtual views; hidden excluded) ────────────
    // The `limit` most-recently-imported asset ids, newest first.
    std::vector<int64_t> recent_assets(int limit) const;
    // Every starred asset id.
    std::vector<int64_t> starred_assets() const;

    // ── Maintenance ─────────────────────────────────────────────────────────
    struct Stats {
        int64_t page_count = 0;      // pages currently in the DB file
        int64_t freelist_count = 0;  // unused pages reclaimable by VACUUM
        int64_t page_size = 0;       // bytes per page
    };
    Stats stats() const;
    // Flush the WAL into the main DB (truncating it) then VACUUM to reclaim
    // freelist pages. Slow on a big DB — run off the UI thread (idle lane).
    void compact();
    // Flush the WAL into the main DB and truncate it (cheap; used before a file
    // copy so the DB is self-contained without its -wal/-shm sidecars).
    void checkpoint();

    // ── Relocate (rebase asset paths) ───────────────────────────────────────
    // Rewrite every stored path (asset.path/folder, import_root, hidden_folder)
    // that is at or under `old_prefix` to sit under `new_prefix` instead — in
    // one transaction, preserving asset ids so faces/albums/tags survive a moved
    // library. Separator-aware (so /a/old never catches /a/older). Returns the
    // number of asset rows rewritten.
    int64_t rebase_paths(const std::string& old_prefix,
                         const std::string& new_prefix);

    // Per-asset EXIF metadata (asset_metadata table), populated on import.
    void upsert_metadata(int64_t asset_id, const exif::AssetMetadata& m);
    std::optional<exif::AssetMetadata> get_metadata(int64_t asset_id) const;

    // (asset_id, lat, lon) for every geotagged asset — drives the map. Unions the
    // manual geo_override table (priority) with EXIF GPS from asset_metadata.
    struct GeoPoint {
        int64_t asset_id;
        double  lat;
        double  lon;
    };
    std::vector<GeoPoint> geotagged() const;

    // ── Manual geotag (geo_override table) ──────────────────────────────────
    // User-placed coordinates that take precedence over EXIF GPS and survive a
    // rescan (which refreshes asset_metadata from the file). Picasa's manual
    // geotag / drag-onto-map. Coordinates are decimal degrees.
    void set_geo_override(int64_t asset_id, double lat, double lon);  // INSERT OR REPLACE
    void clear_geo_override(int64_t asset_id);                        // DELETE
    std::optional<GeoPoint> geo_override_for(int64_t asset_id) const;
    // Effective coordinates for one asset (override first, then EXIF); nullopt if
    // the asset is not geotagged at all.
    std::optional<GeoPoint> geo_for_asset(int64_t asset_id) const;

    // ── Albums — user-created collections (album + album_member tables) ──────
    struct AlbumRecord {
        int64_t     id;
        std::string name;
        int64_t     cover_asset_id;  // -1 if unset / empty
        int32_t     count;           // member count
        int64_t     created;         // ns since epoch
    };

    int64_t create_album(const std::string& name, int64_t created);
    void    rename_album(int64_t album_id, const std::string& name);
    void    delete_album(int64_t album_id);          // also drops its members
    void    set_album_cover(int64_t album_id, int64_t cover_asset_id);
    // Append asset to the album (idempotent — no duplicate membership).
    void    add_to_album(int64_t album_id, int64_t asset_id);
    void    remove_from_album(int64_t album_id, int64_t asset_id);

    std::vector<AlbumRecord> list_albums() const;           // ordered by created
    std::vector<int64_t>     album_members(int64_t album_id) const;  // by position

    // ── Tags (tag + asset_tag tables) ───────────────────────────────────────
    void add_tag(int64_t asset_id, const std::string& tag);     // creates if new
    void remove_tag(int64_t asset_id, const std::string& tag);
    std::vector<std::string> tags_for_asset(int64_t asset_id) const;  // sorted
    std::vector<int64_t>     assets_with_tag(const std::string& tag) const;

private:
    void migrate();

    sqlite3* db_ = nullptr;
};

}  // namespace photo::catalog
