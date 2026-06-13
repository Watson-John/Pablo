// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Orchestrates the stages end-to-end (the `dedup scan` command):
//   enumerate -> exact-dupe -> decode+embed (resumable) -> index -> cluster.
// Each call persists to the workspace so a re-run skips finished work.

#pragma once

#include <cstdint>

#include "dedup/config.h"
#include "dedup/store.h"

namespace dedup {

struct ScanStats {
    size_t enumerated = 0;
    size_t exact_groups = 0;
    size_t newly_embedded = 0;
    size_t already_embedded = 0;
    size_t decode_failures = 0;
    size_t clusters = 0;
    size_t images_in_clusters = 0;
    size_t flagged_oversize = 0;
};

// Run the full sweep. `store` holds persisted state across runs. Throws on
// unrecoverable setup errors (bad config, missing model when embedding is
// required); per-file decode errors are counted, not fatal.
ScanStats run_scan(const Config& cfg, Store& store);

// Re-cluster from already-persisted embeddings without re-embedding — used by
// the calibration helper to sweep thresholds cheaply.
ScanStats recluster_only(const Config& cfg, Store& store);

}  // namespace dedup
