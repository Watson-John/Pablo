// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// cluster.h — agglomerative clustering of face embeddings (the eval grid-search
// winner: average-linkage, cosine distance, F1 0.94 at personal-library scale).
// Pure C++ + OpenCV; no ORT. Two entry points: a full rebuild over all
// embeddings, and online assignment of one new face to existing clusters.

#pragma once

#include <cstdint>
#include <vector>

#include "faces/types.h"

namespace photo::faces {

struct ClusterParams {
    // Cosine-distance threshold to stop merging (1 - cosine_similarity).
    // Tuned in eval/experiments/cluster_gridsearch.py; agglomerative cut at
    // ~0.45 cos-distance was the CV optimum. Persisted so the UI can expose a
    // "looser/tighter grouping" control later.
    float merge_distance = 0.45f;
    int   min_cluster_size = 1;   // singletons allowed; UI hides size-1 noise
};

// Full average-linkage agglomerative clustering. `embeddings[i]` is the
// L2-normalized vector for face `i`; returns a cluster label per face
// (contiguous from 0; -1 never used — singletons get their own label).
std::vector<int64_t> cluster_agglomerative(const std::vector<Embedding>& embeddings,
                                           const ClusterParams& params);

// Online assignment: nearest existing prototype within `merge_distance`, else
// -1 (caller opens a new cluster). Cheap path taken on every scan so the user
// sees grouping immediately without a full rebuild.
int64_t assign_nearest(const Embedding& embedding,
                       const std::vector<Embedding>& prototypes,
                       float merge_distance);

}  // namespace photo::faces
