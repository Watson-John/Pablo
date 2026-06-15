// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/store.h"

#include <filesystem>
#include <stdexcept>

#ifdef FACES_HAVE_SQLITE
#include <sqlite3.h>
#endif

namespace photo::faces {
namespace fs = std::filesystem;

// ---------------------------------------------------------------- VectorStore
VectorStore::VectorStore(const std::string& path, int dim) : path_(path), dim_(dim) {
    std::error_code ec;
    if (fs::exists(path_, ec)) {
        const auto bytes = static_cast<int64_t>(fs::file_size(path_, ec));
        const int64_t row_bytes = static_cast<int64_t>(dim_) * sizeof(float);
        rows_ = (row_bytes > 0) ? bytes / row_bytes : 0;
    }
    out_.open(path_, std::ios::binary | std::ios::app);
    if (!out_) throw std::runtime_error("cannot open face vector store: " + path_);
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
    if (!in) throw std::runtime_error("cannot read face vector store: " + path_);
    in.read(reinterpret_cast<char*>(data.data()),
            static_cast<std::streamsize>(data.size()) * sizeof(float));
    return data;
}

Embedding VectorStore::row(int64_t r) {
    if (r < 0 || r >= rows_) return {};
    out_.flush();
    std::ifstream in(path_, std::ios::binary);
    if (!in) return {};
    in.seekg(r * static_cast<std::streamoff>(dim_) * sizeof(float));
    Embedding v(dim_);
    in.read(reinterpret_cast<char*>(v.data()),
            static_cast<std::streamsize>(dim_) * sizeof(float));
    return v;
}

// ------------------------------------------------------------------ FaceStore
#ifdef FACES_HAVE_SQLITE
namespace {

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
    Stmt& bind(int i, double v) { sqlite3_bind_double(s_, i, v); return *this; }
    Stmt& bind(int i, const std::string& v) {
        sqlite3_bind_text(s_, i, v.c_str(), -1, SQLITE_TRANSIENT); return *this;
    }
    bool step() {
        int rc = sqlite3_step(s_);
        if (rc == SQLITE_ROW) return true;
        if (rc == SQLITE_DONE) return false;
        throw std::runtime_error(std::string("sqlite step rc=") + std::to_string(rc));
    }
    void run() { step(); reset(); }
    void reset() { sqlite3_reset(s_); sqlite3_clear_bindings(s_); }
    int64_t col_int(int i) const { return sqlite3_column_int64(s_, i); }
    double col_dbl(int i) const { return sqlite3_column_double(s_, i); }
    std::string col_text(int i) const {
        const unsigned char* t = sqlite3_column_text(s_, i);
        return t ? reinterpret_cast<const char*>(t) : std::string{};
    }
    sqlite3* db() const { return db_; }
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

// face columns (positional; keep in sync with read_face):
constexpr const char* kFaceCols =
    "id,asset_id,x,y,w,h,"
    "lm0,lm1,lm2,lm3,lm4,lm5,lm6,lm7,lm8,lm9,"
    "det_score,quality,vec_row,cluster_id,person_id,confirmed";

FaceRecord read_face(const Stmt& q) {
    FaceRecord r;
    r.id = q.col_int(0);
    r.asset_id = q.col_int(1);
    r.box = {static_cast<float>(q.col_dbl(2)), static_cast<float>(q.col_dbl(3)),
             static_cast<float>(q.col_dbl(4)), static_cast<float>(q.col_dbl(5))};
    for (int k = 0; k < 10; ++k) r.landmarks[k] = static_cast<float>(q.col_dbl(6 + k));
    r.det_score = static_cast<float>(q.col_dbl(16));
    r.quality = static_cast<float>(q.col_dbl(17));
    r.vec_row = q.col_int(18);
    r.cluster_id = q.col_int(19);
    r.person_id = q.col_int(20);
    r.confirmed = q.col_int(21) != 0;
    return r;
}

}  // namespace

FaceStore::FaceStore(const std::string& catalog_path, int dim)
    : vectors_path_(catalog_path + ".faces.vec") {
    if (sqlite3_open(catalog_path.c_str(), &db_) != SQLITE_OK)
        throw std::runtime_error(std::string("cannot open catalog: ") + sqlite3_errmsg(db_));
    exec(db_, "PRAGMA journal_mode=WAL;");
    exec(db_, "PRAGMA synchronous=NORMAL;");
    init_schema();
    vectors_ = std::make_unique<VectorStore>(vectors_path_, dim);
}

FaceStore::~FaceStore() { if (db_) sqlite3_close(db_); }

void FaceStore::init_schema() {
    exec(db_,
         "CREATE TABLE IF NOT EXISTS face("
         " id INTEGER PRIMARY KEY,"
         " asset_id INTEGER NOT NULL,"
         " x REAL, y REAL, w REAL, h REAL,"
         " lm0 REAL, lm1 REAL, lm2 REAL, lm3 REAL, lm4 REAL,"
         " lm5 REAL, lm6 REAL, lm7 REAL, lm8 REAL, lm9 REAL,"
         " det_score REAL, quality REAL,"
         " vec_row INTEGER DEFAULT -1,"
         " cluster_id INTEGER DEFAULT -1,"
         " person_id INTEGER DEFAULT -1,"
         " confirmed INTEGER DEFAULT 0);"
         "CREATE INDEX IF NOT EXISTS face_asset ON face(asset_id);"
         "CREATE INDEX IF NOT EXISTS face_person ON face(person_id);"
         "CREATE INDEX IF NOT EXISTS face_cluster ON face(cluster_id);"
         "CREATE TABLE IF NOT EXISTS person("
         " id INTEGER PRIMARY KEY,"
         " name TEXT DEFAULT '',"
         " prototype_row INTEGER DEFAULT -1,"
         " face_count INTEGER DEFAULT 0,"
         " confirmed_count INTEGER DEFAULT 0,"
         " confirmed INTEGER DEFAULT 0);");
}

void FaceStore::insert_face(FaceRecord& rec, const float* vec) {
    rec.vec_row = vectors_->append(vec);
    Stmt q(db_,
           "INSERT INTO face(asset_id,x,y,w,h,"
           "lm0,lm1,lm2,lm3,lm4,lm5,lm6,lm7,lm8,lm9,"
           "det_score,quality,vec_row,cluster_id,person_id,confirmed)"
           " VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)");
    q.bind(1, rec.asset_id);
    q.bind(2, (double)rec.box.x).bind(3, (double)rec.box.y)
     .bind(4, (double)rec.box.w).bind(5, (double)rec.box.h);
    for (int k = 0; k < 10; ++k) q.bind(6 + k, (double)rec.landmarks[k]);
    q.bind(16, (double)rec.det_score).bind(17, (double)rec.quality)
     .bind(18, rec.vec_row).bind(19, rec.cluster_id).bind(20, rec.person_id)
     .bind(21, (int64_t)(rec.confirmed ? 1 : 0));
    q.run();
    rec.id = sqlite3_last_insert_rowid(db_);
}

std::vector<FaceRecord> FaceStore::faces_for_asset(int64_t asset_id) const {
    std::vector<FaceRecord> out;
    Stmt q(db_, (std::string("SELECT ") + kFaceCols + " FROM face WHERE asset_id=?").c_str());
    q.bind(1, asset_id);
    while (q.step()) out.push_back(read_face(q));
    return out;
}

bool FaceStore::asset_scanned(int64_t asset_id) const {
    Stmt q(db_, "SELECT 1 FROM face WHERE asset_id=? LIMIT 1");
    q.bind(1, asset_id);
    return q.step();
}

void FaceStore::set_cluster(int64_t face_id, int64_t cluster_id) {
    Stmt q(db_, "UPDATE face SET cluster_id=? WHERE id=?");
    q.bind(1, cluster_id).bind(2, face_id).run();
}

void FaceStore::set_person(int64_t face_id, int64_t person_id) {
    Stmt q(db_, "UPDATE face SET person_id=? WHERE id=?");
    q.bind(1, person_id).bind(2, face_id).run();
}

void FaceStore::set_confirmed(int64_t face_id, bool confirmed) {
    Stmt q(db_, "UPDATE face SET confirmed=? WHERE id=?");
    q.bind(1, (int64_t)(confirmed ? 1 : 0)).bind(2, face_id).run();
}

std::vector<FaceRecord> FaceStore::faces_for_cluster(int64_t cluster_id) const {
    std::vector<FaceRecord> out;
    Stmt q(db_, (std::string("SELECT ") + kFaceCols +
                 " FROM face WHERE cluster_id=? ORDER BY quality DESC").c_str());
    q.bind(1, cluster_id);
    while (q.step()) out.push_back(read_face(q));
    return out;
}

std::vector<FaceRecord> FaceStore::faces_for_person(int64_t person_id,
                                                    bool only_suggestions) const {
    std::vector<FaceRecord> out;
    const std::string sql = std::string("SELECT ") + kFaceCols +
        " FROM face WHERE person_id=?" +
        (only_suggestions ? " AND confirmed=0" : "") + " ORDER BY quality DESC";
    Stmt q(db_, sql.c_str());
    q.bind(1, person_id);
    while (q.step()) out.push_back(read_face(q));
    return out;
}

std::vector<FaceStore::ClusterSummary> FaceStore::unconfirmed_clusters() const {
    // One row per cluster that has no confirmed person, with its size and the
    // highest-quality member as the cover.
    std::vector<ClusterSummary> out;
    Stmt q(db_,
           "SELECT cluster_id, COUNT(*) AS n, "
           "       (SELECT id FROM face f2 WHERE f2.cluster_id=f.cluster_id "
           "        ORDER BY quality DESC LIMIT 1) AS cover "
           "FROM face f WHERE cluster_id>=0 AND confirmed=0 "
           "GROUP BY cluster_id ORDER BY n DESC");
    while (q.step())
        out.push_back({q.col_int(0), static_cast<int32_t>(q.col_int(1)), q.col_int(2)});
    return out;
}

int64_t FaceStore::cover_face_for_person(int64_t person_id) const {
    Stmt q(db_, "SELECT id FROM face WHERE person_id=? ORDER BY quality DESC LIMIT 1");
    q.bind(1, person_id);
    return q.step() ? q.col_int(0) : -1;
}

std::optional<FaceRecord> FaceStore::face_by_id(int64_t face_id) const {
    Stmt q(db_, (std::string("SELECT ") + kFaceCols + " FROM face WHERE id=?").c_str());
    q.bind(1, face_id);
    if (q.step()) return read_face(q);
    return std::nullopt;
}

std::vector<FaceRecord> FaceStore::all_faces() const {
    std::vector<FaceRecord> out;
    Stmt q(db_, (std::string("SELECT ") + kFaceCols +
                 " FROM face WHERE vec_row>=0 ORDER BY id").c_str());
    while (q.step()) out.push_back(read_face(q));
    return out;
}

int64_t FaceStore::create_person() {
    Stmt q(db_, "INSERT INTO person(name) VALUES('')");
    q.run();
    return sqlite3_last_insert_rowid(db_);
}

void FaceStore::rename_person(int64_t person_id, const std::string& name) {
    Stmt q(db_, "UPDATE person SET name=? WHERE id=?");
    q.bind(1, name).bind(2, person_id).run();
}

void FaceStore::set_person_count(int64_t person_id, int32_t total, int32_t confirmed) {
    Stmt q(db_, "UPDATE person SET face_count=?, confirmed_count=?, confirmed=? WHERE id=?");
    q.bind(1, (int64_t)total).bind(2, (int64_t)confirmed)
     .bind(3, (int64_t)(confirmed > 0 ? 1 : 0)).bind(4, person_id).run();
}

std::vector<Person> FaceStore::all_people() const {
    std::vector<Person> out;
    Stmt q(db_, "SELECT id,name,prototype_row,face_count,confirmed_count,confirmed FROM person");
    while (q.step()) {
        Person p;
        p.id = q.col_int(0);
        p.name = q.col_text(1);
        p.prototype_row = q.col_int(2);
        p.face_count = static_cast<int32_t>(q.col_int(3));
        p.confirmed_count = static_cast<int32_t>(q.col_int(4));
        p.confirmed = q.col_int(5) != 0;
        out.push_back(std::move(p));
    }
    return out;
}

std::unordered_map<int64_t, std::vector<Embedding>> FaceStore::confirmed_by_person() {
    std::unordered_map<int64_t, std::vector<Embedding>> out;
    Stmt q(db_, "SELECT person_id,vec_row FROM face WHERE person_id>=0 AND vec_row>=0");
    while (q.step())
        out[q.col_int(0)].push_back(vectors_->row(q.col_int(1)));
    return out;
}

#else  // !FACES_HAVE_SQLITE — faces persistence needs the catalog (M5 dependency)

FaceStore::FaceStore(const std::string&, int) {
    throw std::runtime_error("face persistence requires SQLite "
                             "(rebuild with FACES_HAVE_SQLITE)");
}
FaceStore::~FaceStore() = default;
void FaceStore::insert_face(FaceRecord&, const float*) {}
std::vector<FaceRecord> FaceStore::faces_for_asset(int64_t) const { return {}; }
bool FaceStore::asset_scanned(int64_t) const { return false; }
void FaceStore::set_cluster(int64_t, int64_t) {}
void FaceStore::set_person(int64_t, int64_t) {}
void FaceStore::set_confirmed(int64_t, bool) {}
std::optional<FaceRecord> FaceStore::face_by_id(int64_t) const { return std::nullopt; }
std::vector<FaceRecord> FaceStore::all_faces() const { return {}; }
std::vector<FaceRecord> FaceStore::faces_for_cluster(int64_t) const { return {}; }
std::vector<FaceRecord> FaceStore::faces_for_person(int64_t, bool) const { return {}; }
std::vector<FaceStore::ClusterSummary> FaceStore::unconfirmed_clusters() const { return {}; }
int64_t FaceStore::cover_face_for_person(int64_t) const { return -1; }
int64_t FaceStore::create_person() { return -1; }
void FaceStore::rename_person(int64_t, const std::string&) {}
void FaceStore::set_person_count(int64_t, int32_t, int32_t) {}
std::vector<Person> FaceStore::all_people() const { return {}; }
std::unordered_map<int64_t, std::vector<Embedding>> FaceStore::confirmed_by_person() {
    return {};
}
void FaceStore::init_schema() {}

#endif  // FACES_HAVE_SQLITE

}  // namespace photo::faces
