// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Core value types shared across the pipeline stages. Kept dependency-free
// (no OpenCV / FAISS / ORT here) so every header can include this cheaply.

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace dedup {

// One enumerated file on disk plus everything the cheap (pre-embedding) stages
// learn about it. Mirrors the `images` row in the SQLite store.
struct ImageRecord {
    int64_t id = 0;             // SQLite rowid (0 = not yet persisted)
    std::string path;           // absolute path, UTF-8
    uint64_t size_bytes = 0;
    int64_t mtime_ns = 0;       // last-modified, nanoseconds since epoch
    std::string format;         // lowercase extension without dot ("jpg", "cr2")

    // Stage 2 — exact-duplicate pre-filter.
    std::string content_hash;   // XXH3-128 hex (32 chars); byte-identical detection
    uint64_t phash = 0;         // 64-bit pHash; 0 = not computed
    bool phash_valid = false;

    // Stage 4 — embedding bookkeeping.
    bool embedded = false;
    int64_t vec_row = -1;       // row index into the flat vector store (-1 = none)

    // Stage 6 — clustering result.
    int64_t cluster_id = -1;    // -1 = singleton / unassigned
};

// A retrieved neighbour edge: `other` is similar to some query image with the
// given cosine similarity (dot product of L2-normalized embeddings).
struct Neighbor {
    int64_t a = 0;              // query image id
    int64_t b = 0;             // neighbour image id
    float score = 0.0f;        // cosine similarity in [-1, 1]
};

// A near-duplicate cluster: a connected set of images plus the suggested keeper
// (highest-resolution / RAW-preferred). The pipeline NEVER deletes — discards
// are the non-keeper members, surfaced to the review UI.
struct Cluster {
    int64_t id = 0;
    std::vector<int64_t> members;   // image ids
    int64_t suggested_keeper = 0;   // image id of the proposed keep
    bool flagged_oversize = false;  // tripped max_cluster_size (transitive-drift smell)
};

}  // namespace dedup
