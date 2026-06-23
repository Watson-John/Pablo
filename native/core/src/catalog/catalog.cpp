// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "catalog/catalog.h"

#include <stdexcept>
#include <string>

#ifdef PHOTO_HAVE_SQLITE
#include <sqlite3.h>
#endif

namespace photo::catalog {

#ifdef PHOTO_HAVE_SQLITE
namespace {

// Minimal RAII prepared-statement + exec helpers. Mirrors the helper in
// faces/store.cpp; candidate for extraction to a shared util/sqlite.h once the
// two stores consolidate onto one connection (DECISIONS D9).
class Stmt {
public:
    Stmt(sqlite3* db, const char* sql) : db_(db) {
        if (sqlite3_prepare_v2(db, sql, -1, &s_, nullptr) != SQLITE_OK)
            throw std::runtime_error(std::string("sqlite prepare: ") + sqlite3_errmsg(db));
    }
    ~Stmt() { if (s_) sqlite3_finalize(s_); }
    Stmt(const Stmt&) = delete;
    Stmt& operator=(const Stmt&) = delete;

    Stmt& bind(int i, int64_t v) { sqlite3_bind_int64(s_, i, v); return *this; }
    Stmt& bind(int i, const std::string& v) {
        sqlite3_bind_text(s_, i, v.c_str(), -1, SQLITE_TRANSIENT); return *this;
    }
    bool step() {
        int rc = sqlite3_step(s_);
        if (rc == SQLITE_ROW) return true;
        if (rc == SQLITE_DONE) return false;
        throw std::runtime_error(std::string("sqlite step: ") + sqlite3_errmsg(db_));
    }
    void run() { step(); reset(); }
    void reset() { sqlite3_reset(s_); sqlite3_clear_bindings(s_); }
    int64_t col_int(int i) const { return sqlite3_column_int64(s_, i); }
    std::string col_text(int i) const {
        const unsigned char* t = sqlite3_column_text(s_, i);
        return t ? reinterpret_cast<const char*>(t) : std::string{};
    }

private:
    sqlite3* db_;
    sqlite3_stmt* s_ = nullptr;
};

void exec(sqlite3* db, const char* sql) {
    char* err = nullptr;
    if (sqlite3_exec(db, sql, nullptr, nullptr, &err) != SQLITE_OK) {
        std::string m = err ? err : "unknown";
        sqlite3_free(err);
        throw std::runtime_error("sqlite exec: " + m);
    }
}

int64_t user_version(sqlite3* db) {
    Stmt q(db, "PRAGMA user_version");
    return q.step() ? q.col_int(0) : 0;
}

// Positional column list shared by every full-row read; keep in sync with
// read_asset().
constexpr const char* kAssetCols =
    "id,path,folder,filename,size,mtime_ns,content_hash,"
    "width,height,orientation,format,import_time,starred,rating,caption,hidden";

AssetRecord read_asset(const Stmt& q) {
    AssetRecord r;
    r.id           = q.col_int(0);
    r.path         = q.col_text(1);
    r.folder       = q.col_text(2);
    r.filename     = q.col_text(3);
    r.size         = q.col_int(4);
    r.mtime_ns     = q.col_int(5);
    r.content_hash = q.col_text(6);
    r.width        = static_cast<int32_t>(q.col_int(7));
    r.height       = static_cast<int32_t>(q.col_int(8));
    r.orientation  = static_cast<int32_t>(q.col_int(9));
    r.format       = q.col_text(10);
    r.import_time  = q.col_int(11);
    r.starred      = q.col_int(12) != 0;
    r.rating       = static_cast<int32_t>(q.col_int(13));
    r.caption      = q.col_text(14);
    r.hidden       = q.col_int(15) != 0;
    return r;
}

}  // namespace

Catalog::Catalog(const std::string& db_path) {
    if (sqlite3_open(db_path.c_str(), &db_) != SQLITE_OK) {
        std::string m = sqlite3_errmsg(db_);
        sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error("cannot open catalog: " + m);
    }
    exec(db_, "PRAGMA journal_mode=WAL;");
    exec(db_, "PRAGMA synchronous=NORMAL;");
    exec(db_, "PRAGMA foreign_keys=ON;");
    // Two connections (catalog + faces) write this file; wait rather than fail
    // on the rare overlap.
    exec(db_, "PRAGMA busy_timeout=5000;");
    migrate();
}

Catalog::~Catalog() { if (db_) sqlite3_close(db_); }

void Catalog::migrate() {
    // Versioned, additive migrations. Each future stage bumps the version and
    // appends its tables (album/tag/edit_stack/asset_metadata) here.
    if (user_version(db_) < 1) {
        exec(db_,
             "CREATE TABLE IF NOT EXISTS asset("
             " id INTEGER PRIMARY KEY,"
             " path TEXT NOT NULL UNIQUE,"
             " folder TEXT NOT NULL DEFAULT '',"
             " filename TEXT NOT NULL DEFAULT '',"
             " size INTEGER NOT NULL DEFAULT 0,"
             " mtime_ns INTEGER NOT NULL DEFAULT 0,"
             " content_hash TEXT DEFAULT '',"
             " width INTEGER DEFAULT 0,"
             " height INTEGER DEFAULT 0,"
             " orientation INTEGER DEFAULT 1,"
             " format TEXT DEFAULT '',"
             " import_time INTEGER NOT NULL DEFAULT 0,"
             " starred INTEGER DEFAULT 0,"
             " rating INTEGER DEFAULT 0,"
             " caption TEXT DEFAULT '',"
             " hidden INTEGER DEFAULT 0);"
             "CREATE INDEX IF NOT EXISTS asset_folder ON asset(folder);"
             "PRAGMA user_version=1;");
    }
    if (user_version(db_) < 2) {
        // Import roots — the folders a rescan re-walks.
        exec(db_,
             "CREATE TABLE IF NOT EXISTS import_root(path TEXT PRIMARY KEY);"
             "PRAGMA user_version=2;");
    }
}

int64_t Catalog::upsert_asset(AssetRecord& rec) {
    // File-derived fields are refreshed on conflict; user fields (starred,
    // rating, caption, hidden) and import_time are intentionally left intact.
    Stmt q(db_,
           "INSERT INTO asset(path,folder,filename,size,mtime_ns,content_hash,"
           "width,height,orientation,format,import_time)"
           " VALUES(?,?,?,?,?,?,?,?,?,?,?)"
           " ON CONFLICT(path) DO UPDATE SET"
           "  folder=excluded.folder, filename=excluded.filename,"
           "  size=excluded.size, mtime_ns=excluded.mtime_ns,"
           "  content_hash=excluded.content_hash,"
           "  width=excluded.width, height=excluded.height,"
           "  orientation=excluded.orientation, format=excluded.format");
    q.bind(1, rec.path).bind(2, rec.folder).bind(3, rec.filename)
     .bind(4, rec.size).bind(5, rec.mtime_ns).bind(6, rec.content_hash)
     .bind(7, (int64_t)rec.width).bind(8, (int64_t)rec.height)
     .bind(9, (int64_t)rec.orientation).bind(10, rec.format)
     .bind(11, rec.import_time);
    q.run();

    Stmt id(db_, "SELECT id FROM asset WHERE path=?");
    id.bind(1, rec.path);
    rec.id = id.step() ? id.col_int(0) : 0;
    return rec.id;
}

std::optional<AssetRecord> Catalog::asset_by_id(int64_t id) const {
    Stmt q(db_, (std::string("SELECT ") + kAssetCols + " FROM asset WHERE id=?").c_str());
    q.bind(1, id);
    if (q.step()) return read_asset(q);
    return std::nullopt;
}

std::optional<AssetRecord> Catalog::asset_by_path(const std::string& path) const {
    Stmt q(db_, (std::string("SELECT ") + kAssetCols + " FROM asset WHERE path=?").c_str());
    q.bind(1, path);
    if (q.step()) return read_asset(q);
    return std::nullopt;
}

std::string Catalog::path_by_id(int64_t id) const {
    Stmt q(db_, "SELECT path FROM asset WHERE id=?");
    q.bind(1, id);
    return q.step() ? q.col_text(0) : std::string{};
}

std::vector<AssetRecord> Catalog::list_assets(bool include_hidden) const {
    std::vector<AssetRecord> out;
    const std::string sql = std::string("SELECT ") + kAssetCols + " FROM asset" +
        (include_hidden ? "" : " WHERE hidden=0") + " ORDER BY path";
    Stmt q(db_, sql.c_str());
    while (q.step()) out.push_back(read_asset(q));
    return out;
}

int64_t Catalog::count() const {
    Stmt q(db_, "SELECT COUNT(*) FROM asset");
    return q.step() ? q.col_int(0) : 0;
}

void Catalog::set_starred(int64_t id, bool v) {
    Stmt q(db_, "UPDATE asset SET starred=? WHERE id=?");
    q.bind(1, (int64_t)(v ? 1 : 0)).bind(2, id).run();
}

void Catalog::set_rating(int64_t id, int32_t v) {
    Stmt q(db_, "UPDATE asset SET rating=? WHERE id=?");
    q.bind(1, (int64_t)v).bind(2, id).run();
}

void Catalog::set_caption(int64_t id, const std::string& v) {
    Stmt q(db_, "UPDATE asset SET caption=? WHERE id=?");
    q.bind(1, v).bind(2, id).run();
}

void Catalog::set_hidden(int64_t id, bool v) {
    Stmt q(db_, "UPDATE asset SET hidden=? WHERE id=?");
    q.bind(1, (int64_t)(v ? 1 : 0)).bind(2, id).run();
}

void Catalog::remove_asset(int64_t id) {
    Stmt q(db_, "DELETE FROM asset WHERE id=?");
    q.bind(1, id).run();
}

void Catalog::add_import_root(const std::string& path) {
    Stmt q(db_, "INSERT OR IGNORE INTO import_root(path) VALUES(?)");
    q.bind(1, path).run();
}

std::vector<std::string> Catalog::import_roots() const {
    std::vector<std::string> out;
    Stmt q(db_, "SELECT path FROM import_root ORDER BY path");
    while (q.step()) out.push_back(q.col_text(0));
    return out;
}

#else  // !PHOTO_HAVE_SQLITE — the catalog requires SQLite.

Catalog::Catalog(const std::string&) {
    throw std::runtime_error("asset catalog requires SQLite "
                             "(rebuild with PHOTO_HAVE_SQLITE)");
}
Catalog::~Catalog() = default;
void Catalog::migrate() {}
int64_t Catalog::upsert_asset(AssetRecord&) { return 0; }
std::optional<AssetRecord> Catalog::asset_by_id(int64_t) const { return std::nullopt; }
std::optional<AssetRecord> Catalog::asset_by_path(const std::string&) const { return std::nullopt; }
std::string Catalog::path_by_id(int64_t) const { return {}; }
std::vector<AssetRecord> Catalog::list_assets(bool) const { return {}; }
int64_t Catalog::count() const { return 0; }
void Catalog::set_starred(int64_t, bool) {}
void Catalog::set_rating(int64_t, int32_t) {}
void Catalog::set_caption(int64_t, const std::string&) {}
void Catalog::set_hidden(int64_t, bool) {}
void Catalog::remove_asset(int64_t) {}
void Catalog::add_import_root(const std::string&) {}
std::vector<std::string> Catalog::import_roots() const { return {}; }

#endif  // PHOTO_HAVE_SQLITE

}  // namespace photo::catalog
