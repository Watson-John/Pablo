// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 6: turn the thresholded neighbour graph into duplicate clusters.
//
// Union-find over the surviving edges yields connected components. Two known
// failure modes are guarded:
//   * Transitive drift (A~B~C chaining unrelated images into one mega-cluster):
//     optional mutual-kNN edge filter + an oversize-cluster flag.
//   * Keeper choice: we pre-select the highest-value member (RAW first, then
//     resolution/byte-size) so the reviewer's default action is safe.
//
// Nothing here deletes — clusters are advisory until the reviewer acts.

#pragma once

#include <cstdint>
#include <unordered_map>
#include <vector>

#include "dedup/config.h"
#include "dedup/types.h"

namespace dedup {

// Group `edges` into clusters. `records_by_id` supplies the metadata used to
// pick each cluster's suggested keeper. Singletons are omitted from the result.
std::vector<Cluster> cluster_edges(
    const std::vector<Neighbor>& edges,
    const std::unordered_map<int64_t, ImageRecord>& records_by_id,
    const Config& cfg);

// Minimal disjoint-set with path compression + union by size. Exposed for
// testing and reuse.
class UnionFind {
public:
    explicit UnionFind(size_t n) : parent_(n), size_(n, 1) {
        for (size_t i = 0; i < n; ++i) parent_[i] = i;
    }
    size_t find(size_t x) {
        while (parent_[x] != x) { parent_[x] = parent_[parent_[x]]; x = parent_[x]; }
        return x;
    }
    void unite(size_t a, size_t b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (size_[a] < size_[b]) std::swap(a, b);
        parent_[b] = a;
        size_[a] += size_[b];
    }
private:
    std::vector<size_t> parent_;
    std::vector<size_t> size_;
};

}  // namespace dedup
