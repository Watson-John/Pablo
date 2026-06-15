// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/store.h"

#include <filesystem>
#include <stdexcept>

#include <sqlite3.h>

#include "dedup/log.h"

namespace dedup {
namespace fs = std::filesystem;
namespace {

// RAII prepared statement with a few typed binders/getters.
class Stmt {
public:
    Stmt(sqlite3* db, const std::string& sql) {
        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &s_, nullptr) != SQLITE_OK) {
            throw std::runtime_error(std::string("sqlite prepare: ") + sqlite3_errmsg(db));
        }
    }
    ~Stmt() { if (s_) sqlite3_finalize(s_); }
    Stmt(const Stmt&) = delete;
    Stmt& operator=(const Stmt&) = delete;

    Stmt& bind(int i, int64_t v) { sqlite3_bind_int64(s_, i, v); return *this; }
    Stmt& bind(int i, const std::string& v) {
        sqlite3_bind_text(s_, i, v.c_str(), -1, SQLITE_TRANSIENT); return *this;
    }
    bool step() {  // true while a row is available
        int rc = sqlite3_step(s_);
        if (rc == SQLITE_ROW) return true;
        if (rc == SQLITE_DONE) return false;
        throw std::runtime_error(std::string("sqlite step rc=") + std::to_string(rc));
    }
    void run() { step(); reset(); }
    void reset() { sqlite3_reset(s_); sqlite3_clear_bindings(s_); }

    int64_t col_int(int i) const { return sqlite3_column_int64(s_, i); }
    std::string col_text(int i) const {
        const unsigned char* t = sqlite3_column_text(s_, i);
        return t ? reinterpret_cast<const char*>(t) : std::string{};
    }
    sqlite3_stmt* raw() { return s_; }

private:
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

ImageRecord read_row(const Stmt& q) {
    // Column order: id, path, size, mtime, format, content_hash, phash, vec_row
    ImageRecord r;
    r.id = q.col_int(0);
    r.path = q.col_text(1);
    r.size_bytes = static_cast<uint64_t>(q.col_int(2));
    r.mtime_ns = q.col_int(3);
    r.format = q.col_text(4);
    r.content_hash = q.col_text(5);
    r.phash = static_cast<uint64_t>(q.col_int(6));
    r.phash_valid = r.phash != 0;
    r.vec_row = q.col_int(7);
    r.embedded = r.vec_row >= 0;
    return r;
}

constexpr const char* kSelectCols =
    "id,path,size,mtime,format,content_hash,phash,vec_row";

}  // namespace

// ---------------------------------------------------------------- VectorStore
VectorStore::VectorStore(const std::string& path, int dim) : path_(path), dim_(dim) {
    std::error_code ec;
    if (fs::exists(path_, ec)) {
        const auto bytes = static_cast<int64_t>(fs::file_size(path_, ec));
        const int64_t row_bytes = static_cast<int64_t>(dim_) * sizeof(float);
        rows_ = (row_bytes > 0) ? bytes / row_bytes : 0;
    }
    out_.open(path_, std::ios::binary | std::ios::app);
    if (!out_) throw std::runtime_error("cannot open vector store: " + path_);
}

VectorStore::~VectorStore() = default;

int64_t VectorStore::append(const float* vec) {
    out_.write(reinterpret_cast<const char*>(vec),
               static_cast<std::streamsize>(dim_) * sizeof(float));
    return rows_++;
}

std::vector<float> VectorStore::load_all() {
    out_.flush();
    std::vector<float> data(static_cast<size_t>(rows_) * dim_);
    if (rows_ == 0) return data;
    std::ifstream in(path_, std::ios::binary);
    if (!in) throw std::runtime_error("cannot read vector store: " + path_);
    in.read(reinterpret_cast<char*>(data.data()),
            static_cast<std::streamsize>(data.size()) * sizeof(float));
    return data;
}

// ---------------------------------------------------------------------- Store
Store::Store(const Config& cfg) : vectors_path_(cfg.vectors_path) {
    if (sqlite3_open(cfg.db_path.c_str(), &db_) != SQLITE_OK) {
        throw std::runtime_error(std::string("cannot open db: ") + sqlite3_errmsg(db_));
    }
    exec(db_, "PRAGMA journal_mode=WAL;");
    exec(db_, "PRAGMA synchronous=NORMAL;");
    init_schema();

    // Dimension is fixed once the first embedding is written; we need it now to
    // open the vector store. Read it from a meta row, defaulting to 512.
    int dim = 512;
    {
        Stmt q(db_, "SELECT value FROM meta WHERE key='embed_dim'");
        if (q.step()) dim = static_cast<int>(std::stoll(q.col_text(0)));
    }
    vectors_ = std::make_unique<VectorStore>(cfg.vectors_path, dim);
    LOG_DEBUG("store: db=" << cfg.db_path << " vectors=" << cfg.vectors_path
                           << " dim=" << dim << " rows=" << vectors_->rows());
}

Store::~Store() {
    if (db_) sqlite3_close(db_);
}

void Store::init_schema() {
    exec(db_,
        "CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);"
        "CREATE TABLE IF NOT EXISTS images("
        "  id INTEGER PRIMARY KEY,"
        "  path TEXT UNIQUE NOT NULL,"
        "  size INTEGER, mtime INTEGER, format TEXT,"
        "  content_hash TEXT, phash INTEGER DEFAULT 0,"
        "  vec_row INTEGER DEFAULT -1,"
        "  dup_of INTEGER DEFAULT -1);"
        "CREATE INDEX IF NOT EXISTS idx_images_vec ON images(vec_row);"
        "CREATE INDEX IF NOT EXISTS idx_images_dup ON images(dup_of);"
        "CREATE TABLE IF NOT EXISTS cluster_members("
        "  cluster_id INTEGER NOT NULL,"
        "  image_id INTEGER NOT NULL,"
        "  is_keeper INTEGER DEFAULT 0,"
        "  flagged_oversize INTEGER DEFAULT 0);"
        "CREATE INDEX IF NOT EXISTS idx_cm_cluster ON cluster_members(cluster_id);"
        "CREATE TABLE IF NOT EXISTS actions("
        "  id INTEGER PRIMARY KEY,"
        "  image_id INTEGER NOT NULL,"
        "  action TEXT NOT NULL,"
        "  dest TEXT,"
        "  ts INTEGER);");
}

void Store::upsert_image(ImageRecord& rec) {
    Stmt up(db_,
        "INSERT INTO images(path,size,mtime,format) VALUES(?,?,?,?) "
        "ON CONFLICT(path) DO UPDATE SET size=excluded.size,"
        " mtime=excluded.mtime, format=excluded.format");
    up.bind(1, rec.path).bind(2, static_cast<int64_t>(rec.size_bytes))
      .bind(3, rec.mtime_ns).bind(4, rec.format);
    up.run();

    Stmt sel(db_, "SELECT id,vec_row FROM images WHERE path=?");
    sel.bind(1, rec.path);
    if (sel.step()) {
        rec.id = sel.col_int(0);
        rec.vec_row = sel.col_int(1);
        rec.embedded = rec.vec_row >= 0;
    }
}

void Store::update_hash(int64_t id, const std::string& content_hash) {
    Stmt s(db_, "UPDATE images SET content_hash=? WHERE id=?");
    s.bind(1, content_hash).bind(2, id).run();
}

void Store::update_phash(int64_t id, uint64_t phash) {
    Stmt s(db_, "UPDATE images SET phash=? WHERE id=?");
    s.bind(1, static_cast<int64_t>(phash)).bind(2, id).run();
}

void Store::set_embedding(int64_t id, const float* vec, int dim) {
    // First embedding on a fresh store: record the model's dim (and adopt it for
    // the vector file, which was opened at the default before the model loaded).
    if (vectors_->rows() == 0) {
        if (dim != vectors_->dim()) {
            vectors_ = std::make_unique<VectorStore>(vectors_path_, dim);
        }
        Stmt m(db_, "INSERT OR REPLACE INTO meta(key,value) VALUES('embed_dim',?)");
        m.bind(1, std::to_string(dim)).run();
    }
    if (dim != vectors_->dim()) {
        throw std::runtime_error("embedding dim mismatch: model=" + std::to_string(dim) +
                                 " store=" + std::to_string(vectors_->dim()) +
                                 " (delete the vectors file to re-embed at a new dim)");
    }
    int64_t row = vectors_->append(vec);
    Stmt s(db_, "UPDATE images SET vec_row=? WHERE id=?");
    s.bind(1, row).bind(2, id).run();
}

void Store::set_dup_of(int64_t id, int64_t rep_id) {
    Stmt s(db_, "UPDATE images SET dup_of=? WHERE id=?");
    s.bind(1, rep_id).bind(2, id).run();
}

std::vector<std::pair<int64_t, int64_t>> Store::dup_edges() const {
    std::vector<std::pair<int64_t, int64_t>> out;
    Stmt q(db_, "SELECT id,dup_of FROM images WHERE dup_of >= 0");
    while (q.step()) out.emplace_back(q.col_int(0), q.col_int(1));
    return out;
}

std::unordered_map<int64_t, ImageRecord> Store::all_by_id() const {
    std::unordered_map<int64_t, ImageRecord> out;
    Stmt q(db_, std::string("SELECT ") + kSelectCols + " FROM images ORDER BY id");
    while (q.step()) {
        ImageRecord r = read_row(q);
        out.emplace(r.id, std::move(r));
    }
    return out;
}

std::vector<ImageRecord> Store::images_needing_embedding() const {
    std::vector<ImageRecord> out;
    Stmt q(db_, std::string("SELECT ") + kSelectCols +
                " FROM images WHERE vec_row < 0 AND dup_of < 0 ORDER BY id");
    while (q.step()) out.push_back(read_row(q));
    return out;
}

std::vector<ImageRecord> Store::embedded_images() const {
    std::vector<ImageRecord> out;
    Stmt q(db_, std::string("SELECT ") + kSelectCols +
                " FROM images WHERE vec_row >= 0 ORDER BY id");
    while (q.step()) out.push_back(read_row(q));
    return out;
}

std::unordered_map<int64_t, ImageRecord> Store::embedded_by_id() const {
    std::unordered_map<int64_t, ImageRecord> out;
    for (auto& r : embedded_images()) out.emplace(r.id, std::move(r));
    return out;
}

void Store::replace_clusters(const std::vector<Cluster>& clusters) {
    exec(db_, "BEGIN");
    exec(db_, "DELETE FROM cluster_members");
    Stmt ins(db_,
        "INSERT INTO cluster_members(cluster_id,image_id,is_keeper,flagged_oversize)"
        " VALUES(?,?,?,?)");
    for (const auto& c : clusters) {
        for (int64_t id : c.members) {
            ins.bind(1, c.id).bind(2, id)
               .bind(3, static_cast<int64_t>(id == c.suggested_keeper ? 1 : 0))
               .bind(4, static_cast<int64_t>(c.flagged_oversize ? 1 : 0));
            ins.run();
        }
    }
    exec(db_, "COMMIT");
}

std::vector<Cluster> Store::load_clusters() const {
    std::vector<Cluster> out;
    Stmt q(db_,
        "SELECT cluster_id,image_id,is_keeper,flagged_oversize"
        " FROM cluster_members ORDER BY cluster_id,image_id");
    Cluster cur;
    cur.id = -1;
    while (q.step()) {
        int64_t cid = q.col_int(0), img = q.col_int(1);
        bool keeper = q.col_int(2) != 0, oversize = q.col_int(3) != 0;
        if (cid != cur.id) {
            if (cur.id != -1) out.push_back(cur);
            cur = Cluster{};
            cur.id = cid;
        }
        cur.members.push_back(img);
        if (keeper) cur.suggested_keeper = img;
        if (oversize) cur.flagged_oversize = true;
    }
    if (cur.id != -1) out.push_back(cur);
    return out;
}

std::optional<ImageRecord> Store::image_by_id(int64_t id) const {
    Stmt q(db_, std::string("SELECT ") + kSelectCols + " FROM images WHERE id=?");
    q.bind(1, id);
    if (q.step()) return read_row(q);
    return std::nullopt;
}

void Store::record_quarantine(int64_t id, const std::string& dest) {
    Stmt s(db_,
        "INSERT INTO actions(image_id,action,dest,ts) VALUES(?,?,?,strftime('%s','now'))");
    s.bind(1, id).bind(2, std::string("quarantine")).bind(3, dest).run();
}

}  // namespace dedup
