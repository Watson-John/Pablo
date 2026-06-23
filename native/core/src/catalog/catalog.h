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

    // Per-asset EXIF metadata (asset_metadata table), populated on import.
    void upsert_metadata(int64_t asset_id, const exif::AssetMetadata& m);
    std::optional<exif::AssetMetadata> get_metadata(int64_t asset_id) const;

    // (asset_id, lat, lon) for every geotagged asset — drives the map.
    struct GeoPoint {
        int64_t asset_id;
        double  lat;
        double  lon;
    };
    std::vector<GeoPoint> geotagged() const;

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

private:
    void migrate();

    sqlite3* db_ = nullptr;
};

}  // namespace photo::catalog
