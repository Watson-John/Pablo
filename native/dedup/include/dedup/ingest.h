// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 1–2: enumerate the library and run the exact-duplicate pre-filter.
//
//   1. Recursive walk -> ImageRecord per file (path, size, mtime, format).
//   2. XXH3-128 content hash  -> byte-identical files collapse to one group.
//      OpenCV pHash           -> trivial re-saves (re-compressed copies) group
//                                within a small Hamming distance.
//
// The exact pass is cheap and runs before the expensive decode+embed, so
// obvious duplicates never reach the model.

#pragma once

#include <algorithm>
#include <bit>
#include <cstdint>
#include <string>
#include <vector>

#include "dedup/config.h"
#include "dedup/types.h"

namespace dedup {

// Recursively enumerate `cfg.roots`, keeping files whose lowercase extension is
// in `cfg.extensions`. Fills path/size/mtime/format. Does not hash or decode.
std::vector<ImageRecord> enumerate_images(const Config& cfg);

// XXH3-128 of the file's bytes, as a 32-char lowercase hex string. Streams the
// file so arbitrarily large RAWs cost only a fixed buffer. Empty string on I/O
// error.
std::string content_hash_file(const std::string& path);

// Populate `content_hash` for every record, in parallel (cfg.decode_threads).
void compute_content_hashes(std::vector<ImageRecord>& records, const Config& cfg);

// Result of the exact-duplicate pass: a partition of record indices into groups
// that are byte-identical or near-identical re-saves. Groups of size 1 are
// omitted. Indices refer into the `records` vector passed in.
struct ExactGroups {
    std::vector<std::vector<size_t>> groups;
    size_t byte_identical_pairs = 0;
    size_t phash_pairs = 0;
};

// Group byte-identical files (same content_hash) and, optionally, near-identical
// re-saves (pHash within cfg.phash_hamming). Requires content_hash populated;
// computes pHash on demand for the survivors.
ExactGroups exact_duplicate_pass(std::vector<ImageRecord>& records, const Config& cfg);

// Hamming distance between two equal-width perceptual hashes (byte-wise popcount;
// compares min(len) bytes so mixed widths degrade gracefully).
inline int hamming(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    const size_t n = std::min(a.size(), b.size());
    int d = 0;
    for (size_t i = 0; i < n; ++i) d += std::popcount(static_cast<unsigned>(a[i] ^ b[i]));
    return d;
}

}  // namespace dedup
