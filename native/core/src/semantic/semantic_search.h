// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// semantic_search.h — cosine ranking over the embedding working set (Stage 9).
//
// Pure, dependency-free. A linear scan is ample at personal-library scale
// (~30k × ~512 floats ≈ a few ms); an ANN index (hnsw/faiss) is a future
// optimization noted in docs/specs/09-search-and-discovery.md.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "catalog/catalog.h"  // Catalog::EmbeddingVec

namespace photo::semantic {

struct SearchHit {
    int64_t asset_id;
    float   score;  // cosine similarity in [-1, 1]
};

// Rank `query` against `items` by cosine similarity, returning the top `cap`
// hits (score-descending). If `candidates` is non-empty, only those asset ids
// are considered (the metadata-filtered subset). Items whose dimensionality does
// not match `query` are ignored. Vectors are assumed L2-normalized; norms are
// applied defensively so an un-normalized input still ranks sanely.
std::vector<SearchHit> cosine_rank(
    const std::vector<float>& query,
    const std::vector<catalog::Catalog::EmbeddingVec>& items,
    const std::vector<int64_t>& candidates, size_t cap);

// ── SidecarIndex — the DISK-resident search index ────────────────────────────
//
// The embedding working set stored outside process RAM: a flat file of
// per-vector int8-quantized embeddings (per-vector symmetric scale), memory-
// mapped at query time. Residency is the OS page cache's problem — the pages
// are clean and file-backed, so they are reclaimed under memory pressure
// instead of pinning heap (at 31k images: ~24 MB file vs 98 MB fp32 heap;
// quantization costs −0.3 % relative mAP, measured). Rebuilt from the catalog
// (the durable fp32 source of truth) whenever stale — the file is a
// per-machine cache in host byte order, never an interchange format.
//
// Layout: 48-byte header
//   [8] magic "PABVIDX1" · u32 dim · u32 row_bytes · u64 row count
//   · u64 model_hash · i64 stamp_count · i64 stamp_max_updated_ns
// then count rows of { i64 asset_id, f32 scale, i8 vec[dim], pad→8 }.
// stamp_* mirror Catalog::embedding_stamp() at build time so a restart can
// adopt the file without re-reading every BLOB.
class SidecarIndex {
public:
    // FNV-1a of "model_id:version:dim" — a model switch invalidates the file.
    static uint64_t model_hash(const std::string& model_id,
                               const std::string& model_version, int dim);

    // Quantize + write atomically (tmp + rename). Rows whose vec size != dim
    // are skipped (stale-model leftovers mid-reindex). False on IO failure.
    static bool write(const std::string& path,
                      const std::vector<catalog::Catalog::EmbeddingVec>& items,
                      int dim, uint64_t model_hash,
                      const catalog::Catalog::EmbeddingStamp& stamp);

    // Open + validate + map (POSIX mmap; whole-file heap read on Windows).
    // nullptr on missing/corrupt/size-mismatched file — caller rebuilds.
    static std::shared_ptr<const SidecarIndex> open(const std::string& path);

    int      dim() const { return dim_; }
    int64_t  count() const { return count_; }
    uint64_t stamp_model_hash() const { return model_hash_; }
    int64_t  stamp_count() const { return stamp_count_; }
    int64_t  stamp_max_updated_ns() const { return stamp_max_updated_ns_; }

    // Same contract as cosine_rank, over the mapped rows (dequantized on the
    // fly). Read-only + lock-free; safe concurrently with other scans.
    std::vector<SearchHit> scan(const std::vector<float>& query,
                                const std::vector<int64_t>& candidates,
                                size_t cap) const;

    ~SidecarIndex();
    SidecarIndex(const SidecarIndex&) = delete;
    SidecarIndex& operator=(const SidecarIndex&) = delete;

private:
    SidecarIndex() = default;
    const uint8_t* rows_ = nullptr;  // first row (inside map_ or heap_)
    size_t   row_bytes_ = 0;
    int      dim_ = 0;
    int64_t  count_ = 0;
    uint64_t model_hash_ = 0;
    int64_t  stamp_count_ = 0;
    int64_t  stamp_max_updated_ns_ = 0;
    void*    map_ = nullptr;  // mmap base (POSIX); nullptr on Windows
    size_t   map_len_ = 0;
    std::vector<uint8_t> heap_;  // Windows fallback storage
};

}  // namespace photo::semantic
