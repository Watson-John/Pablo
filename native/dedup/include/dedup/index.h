// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 5: nearest-neighbour search over L2-normalized embeddings.
//
// The vectors are unit-norm, so inner product == cosine similarity. We use an
// EXACT flat index — at 300k×512 the brute-force matrix is ~0.6 GB and a full
// self-query is seconds-to-minutes with BLAS, and exactness avoids the recall
// cliffs an approximate index would introduce near the duplicate threshold.
//
// FAISS (IndexFlatIP) is used when available; otherwise a thread-pooled scalar
// brute-force fallback gives identical results at much lower throughput. NOTE:
// the fallback is a plain dot-product loop, NOT a BLAS/GEMM — for the ~300k
// target, link FAISS (or replace the fallback with cblas_sgemm). See index.cpp.

#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include "dedup/types.h"

namespace dedup {

class SimilarityIndex {
public:
    virtual ~SimilarityIndex() = default;

    // Add `n` row-major, L2-normalized vectors of length dim(). Vector i is
    // assigned internal label i (callers map label -> image id externally).
    virtual void add(const float* data, int64_t n) = 0;

    // For each of the `nq` query rows, return its top-k neighbours as flat
    // arrays (length nq*k): out_labels[i*k + j] / out_scores[i*k + j]. Missing
    // slots are label -1 / score -inf. Self-matches are NOT filtered here.
    virtual void search(const float* queries, int64_t nq, int k,
                        std::vector<int64_t>& out_labels,
                        std::vector<float>& out_scores) const = 0;

    virtual int dim() const = 0;
    virtual int64_t size() const = 0;
};

// Construct the best available index for `dim`-dimensional vectors: FAISS
// IndexFlatIP when compiled in, else the brute-force fallback.
std::unique_ptr<SimilarityIndex> make_index(int dim);

// Build the neighbour edge list: query every vector against the index for its
// top-k, drop self-matches, and keep edges with score >= threshold. Edges are
// de-duplicated (a<b) keeping the max score. When `mutual` is true, only
// reciprocal edges survive (b ∈ kNN(a) AND a ∈ kNN(b)) — this curbs the
// transitive drift that chains unrelated images into one mega-cluster.
// `ids[label]` maps an index label to its image id.
std::vector<Neighbor> build_neighbor_edges(const SimilarityIndex& index,
                                           const float* vectors,
                                           const std::vector<int64_t>& ids,
                                           int k, float threshold, bool mutual);

}  // namespace dedup
