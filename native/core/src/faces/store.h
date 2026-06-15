// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// store.h — face persistence: SQLite tables (face, person) in the Pablo catalog
// + a flat float32 vector file for embeddings, mirroring dedup's Store/VectorStore.
// Embedding is the expensive stage, so it runs ONCE per face; the vec_row links a
// face row to its vector. Vectors live in a separate mmap-friendly file to keep
// the catalog small and queryable.

#pragma once

#include <cstdint>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "faces/types.h"

struct sqlite3;  // fwd

namespace photo::faces {

// Append-only flat store of fixed-width float32 rows (the embedding matrix).
// Shared shape with dedup::VectorStore; kept local so faces own their file.
class VectorStore {
public:
    VectorStore(const std::string& path, int dim);
    ~VectorStore();

    int dim() const { return dim_; }
    int64_t rows() const { return rows_; }

    int64_t append(const float* vec);          // returns row index
    std::vector<float> load_all();             // rows()*dim() row-major
    Embedding row(int64_t r);                  // one vector by row index
    void flush() { out_.flush(); }

private:
    std::string path_;
    int dim_;
    int64_t rows_ = 0;
    std::ofstream out_;
};

class FaceStore {
public:
    // Opens (creates) the face tables in the catalog at `catalog_path` and the
    // sibling vectors file. `dim` is the embedder dimension (512 AuraFace).
    FaceStore(const std::string& catalog_path, int dim);
    ~FaceStore();

    FaceStore(const FaceStore&) = delete;
    FaceStore& operator=(const FaceStore&) = delete;

    // --- faces ---
    // Insert a detected+embedded face; stores its vector, sets rec.id + vec_row.
    void insert_face(FaceRecord& rec, const float* vec);
    // Faces already recorded for an asset (so a re-scan is idempotent/skips).
    std::vector<FaceRecord> faces_for_asset(int64_t asset_id) const;
    bool asset_scanned(int64_t asset_id) const;
    void set_cluster(int64_t face_id, int64_t cluster_id);
    void set_person(int64_t face_id, int64_t person_id);
    void set_confirmed(int64_t face_id, bool confirmed);
    std::optional<FaceRecord> face_by_id(int64_t face_id) const;

    // All faces with embeddings, vec_row populated (for a full re-cluster).
    std::vector<FaceRecord> all_faces() const;

    // --- read-back queries (UI) ---
    // Members of one cluster, ordered by quality desc.
    std::vector<FaceRecord> faces_for_cluster(int64_t cluster_id) const;
    // Faces assigned to a person, optionally only suggestions (confirmed=0).
    std::vector<FaceRecord> faces_for_person(int64_t person_id, bool only_suggestions) const;
    // One summary row per unconfirmed cluster: {cluster_id, count, cover_face_id}.
    struct ClusterSummary { int64_t cluster_id; int32_t count; int64_t cover_face_id; };
    std::vector<ClusterSummary> unconfirmed_clusters() const;
    // Highest-quality face id for a person (avatar cover); -1 if none.
    int64_t cover_face_for_person(int64_t person_id) const;

    // --- people ---
    int64_t create_person();                         // returns new person id
    void rename_person(int64_t person_id, const std::string& name);
    void set_person_count(int64_t person_id, int32_t total, int32_t confirmed);
    std::vector<Person> all_people() const;
    // person_id -> confirmed embeddings, to rebuild the prototype index on load.
    std::unordered_map<int64_t, std::vector<Embedding>> confirmed_by_person();

    // --- vectors ---
    VectorStore& vectors() { return *vectors_; }

private:
    sqlite3* db_ = nullptr;
    std::string vectors_path_;
    std::unique_ptr<VectorStore> vectors_;
    void init_schema();
};

}  // namespace photo::faces
