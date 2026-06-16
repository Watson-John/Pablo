// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/cluster.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>

namespace photo::faces {

namespace {

float cosine(const Embedding& a, const Embedding& b) {
    if (a.size() != b.size() || a.empty()) return -1.0f;
    double dot = 0.0;
    for (size_t i = 0; i < a.size(); ++i) dot += static_cast<double>(a[i]) * b[i];
    return static_cast<float>(dot);  // inputs are L2-normalized
}

}  // namespace

// Average-linkage agglomerative clustering on cosine distance, the eval
// grid-search winner (F1 0.94 at personal-library scale). O(n^2 log n) with a
// dense distance matrix — fine for a personal library's face count; a full
// rebuild runs on the idle lane. Merges the closest pair until the minimum
// average-linkage distance exceeds `merge_distance`.
std::vector<int64_t> cluster_agglomerative(const std::vector<Embedding>& emb,
                                           const ClusterParams& params) {
    const int n = static_cast<int>(emb.size());
    std::vector<int64_t> labels(n, 0);
    if (n == 0) return labels;
    if (n == 1) { labels[0] = 0; return labels; }

    // Active clusters as index lists; pairwise distance cached as the running
    // average-linkage value, updated by the Lance-Williams average rule.
    std::vector<std::vector<int>> members(n);
    for (int i = 0; i < n; ++i) members[i] = {i};

    // dist[i][j] (i<j) average-linkage distance; init = pairwise cos-distance.
    std::vector<std::vector<float>> dist(n, std::vector<float>(n, 0.0f));
    for (int i = 0; i < n; ++i)
        for (int j = i + 1; j < n; ++j)
            dist[i][j] = dist[j][i] = 1.0f - cosine(emb[i], emb[j]);

    std::vector<char> alive(n, 1);
    int alive_count = n;

    while (alive_count > 1) {
        // Find the closest alive pair.
        float best = std::numeric_limits<float>::max();
        int bi = -1, bj = -1;
        for (int i = 0; i < n; ++i) {
            if (!alive[i]) continue;
            for (int j = i + 1; j < n; ++j) {
                if (!alive[j]) continue;
                if (dist[i][j] < best) { best = dist[i][j]; bi = i; bj = j; }
            }
        }
        if (bi < 0 || best > params.merge_distance) break;  // cut reached

        // Merge bj into bi with the average-linkage (Lance-Williams) update:
        // d(bi+bj, k) = (|bi|*d(bi,k) + |bj|*d(bj,k)) / (|bi|+|bj|).
        const float ni = static_cast<float>(members[bi].size());
        const float nj = static_cast<float>(members[bj].size());
        for (int k = 0; k < n; ++k) {
            if (!alive[k] || k == bi || k == bj) continue;
            const float dk = (ni * dist[bi][k] + nj * dist[bj][k]) / (ni + nj);
            dist[bi][k] = dist[k][bi] = dk;
        }
        members[bi].insert(members[bi].end(), members[bj].begin(), members[bj].end());
        alive[bj] = 0;
        --alive_count;
    }

    // Assign contiguous labels; drop clusters below min_cluster_size to -1 only
    // if the caller asked (min>1). Default keeps singletons as their own label.
    int64_t next = 0;
    for (int i = 0; i < n; ++i) {
        if (!alive[i]) continue;
        const bool keep = static_cast<int>(members[i].size()) >= params.min_cluster_size;
        const int64_t lbl = keep ? next++ : -1;
        for (int m : members[i]) labels[m] = lbl;
    }
    return labels;
}

int64_t assign_nearest(const Embedding& e, const std::vector<Embedding>& protos,
                       float merge_distance) {
    int64_t best = -1;
    float best_d = merge_distance;
    for (size_t i = 0; i < protos.size(); ++i) {
        const float d = 1.0f - cosine(e, protos[i]);
        if (d <= best_d) { best_d = d; best = static_cast<int64_t>(i); }
    }
    return best;
}

}  // namespace photo::faces
