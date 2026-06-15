// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Persistence: SQLite metadata + a flat float32 vector file.
//
// Embedding is the expensive stage, so it must run ONCE. The store records
// which images are already embedded (and where their vector lives) so a re-run
// resumes instead of recomputing. Vectors live in a separate mmap-friendly file
// rather than as DB blobs to keep `dedup.db` small and queryable.

#pragma once

#include <cstdint>
#include <fstream>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "dedup/config.h"
#include "dedup/types.h"

struct sqlite3;  // fwd

namespace dedup {

// Append-only flat store of fixed-width float32 rows (the embedding matrix).
class VectorStore {
public:
    VectorStore(const std::string& path, int dim);
    ~VectorStore();

    int dim() const { return dim_; }
    int64_t rows() const { return rows_; }

    // Append one vector (length dim()); returns its row index.
    int64_t append(const float* vec);

    // Load the entire matrix into a contiguous, row-major buffer (rows()*dim()).
    // Flushes pending appends first.
    std::vector<float> load_all();

    void flush() { out_.flush(); }

private:
    std::string path_;
    int dim_;
    int64_t rows_ = 0;
    std::ofstream out_;  // append handle (binary)
};

class Store {
public:
    explicit Store(const Config& cfg);
    ~Store();

    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;

    // --- images ---
    // Insert or update by path. Sets rec.id to the rowid. Idempotent: a second
    // call with the same path/size/mtime is a no-op for the heavy columns.
    void upsert_image(ImageRecord& rec);
    void update_hash(int64_t id, const std::string& content_hash);
    void update_phash(int64_t id, const std::vector<uint8_t>& phash);

    // Records the embedding: stores the vector and links image -> vec_row.
    void set_embedding(int64_t id, const float* vec, int dim);

    // Mark `id` as an exact/near-identical duplicate of representative `rep_id`
    // (from the exact-dupe pass). Such images are NOT embedded — they inherit
    // their representative's vector and are folded back into its cluster.
    void set_dup_of(int64_t id, int64_t rep_id);

    // (id, dup_of) pairs for every image flagged as an exact duplicate. Used to
    // reconstruct exact-group edges during clustering (no in-memory state needed
    // on a re-cluster).
    std::vector<std::pair<int64_t, int64_t>> dup_edges() const;

    // Map id -> record for ALL enumerated images (keeper selection / time-guard).
    std::unordered_map<int64_t, ImageRecord> all_by_id() const;

    // Images that still need embedding (no vec_row, not a duplicate), id order.
    std::vector<ImageRecord> images_needing_embedding() const;

    // All images that DO have an embedding, with vec_row populated, id order.
    std::vector<ImageRecord> embedded_images() const;

    // Map id -> record for the embedded set (keeper selection / UI).
    std::unordered_map<int64_t, ImageRecord> embedded_by_id() const;

    // --- vectors ---
    VectorStore& vectors() { return *vectors_; }

    // --- clusters ---
    void replace_clusters(const std::vector<Cluster>& clusters);
    std::vector<Cluster> load_clusters() const;
    std::optional<ImageRecord> image_by_id(int64_t id) const;

    // --- review actions (audit trail; never deletes source files) ---
    // Records that `id` was quarantined to `dest` at the reviewer's request.
    void record_quarantine(int64_t id, const std::string& dest);

private:
    sqlite3* db_ = nullptr;
    std::string vectors_path_;
    std::unique_ptr<VectorStore> vectors_;
    void init_schema();
};

}  // namespace dedup
