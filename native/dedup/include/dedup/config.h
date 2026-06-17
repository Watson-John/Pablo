// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Typed view over config.yaml. Loaded once at startup; CLI flags may override
// individual fields (see main.cpp).

#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace dedup {

struct Config {
    // Inputs.
    std::vector<std::string> roots;
    // Non-empty default so `dedup scan --roots ...` works with no config file.
    // A YAML `extensions:` list fully replaces this (loader clears before fill).
    std::vector<std::string> extensions = {
        "jpg", "jpeg", "png", "tif", "tiff", "webp", "heic",
        "cr2", "cr3", "nef", "arw", "dng", "raf", "rw2",
    };

    // Workspace (persisted state — embedding runs once).
    std::string db_path = "./dedup.db";
    std::string vectors_path = "./vectors.f32";
    std::string quarantine_dir = "./quarantine";

    // Embedding.
    bool embed_enabled = true;      // false = hash-only mode (skip SSCD; no model
                                    // / GPU needed — for low-end PCs or a fast pass)
    std::string model_path = "./models/sscd_disc_mixup.onnx";
    int input_size = 288;
    int batch_size = 64;
    std::string provider = "cpu";   // "cpu" | "cuda" | "coreml"
    int intra_op_threads = 0;       // 0 = ORT default

    // Indexing.
    int k = 20;
    // Score normalization (descriptor stretching): suppress hub images before
    // thresholding. Off by default (marginal on small sets; grows with library
    // size). Shifts the score scale — re-calibrate the threshold when enabling.
    bool score_norm = false;
    double score_norm_beta = 1.0;

    // Clustering. Default 0.35 sits between the measured true-pair median (~0.43)
    // and the random-pair ceiling (~0.13) — calibrate per library with `calibrate`.
    // (The brief's 0.80 starting point empirically finds almost nothing on SSCD.)
    double threshold = 0.35;
    bool mutual_knn = true;
    int max_cluster_size = 400;
    bool exif_time_guard = false;
    int exif_time_window_sec = 5;

    // Decode / throughput.
    int decode_threads = 0;         // 0 = hardware_concurrency
    bool prefer_embedded_thumb = true;
    // Pre-embedding geometry: "crop" = resize short side then center-crop (loses
    // borders); "squash" = resize straight to a square (keeps all content, warps
    // aspect). Squash can help heavily-cropped near-dupes.
    std::string resize_mode = "crop";

    // Exact-duplicate pre-filter.
    bool exact_content_hash = true;
    // Perceptual-hash algorithm for trivial re-saves. All are Hamming-compared.
    //   phash    — 64-bit DCT (default; robust to gamma/compression)
    //   blockmean— 256-bit block-mean (finer; fewer false collisions)
    //   average  — 64-bit mean (fastest, weakest)
    //   marr     — 576-bit Marr-Hildreth (edge-based, very fine)
    std::string phash_algo = "phash";
    int phash_hamming = 6;          // absolute Hamming cutoff; scale up for wider
                                    // hashes (≈ phash 6 / blockmean 24 / marr 50)

    // Review server.
    std::string server_host = "127.0.0.1";
    int server_port = 8755;

    // Resolved at load time: directory containing the static review UI.
    std::string web_dir = "./web";
};

// Parse `path` (YAML). Throws std::runtime_error on a malformed file. A missing
// file yields defaults (so `dedup scan --roots ...` works with no config).
Config load_config(const std::string& path);

// Number of worker threads to use given a config field (0 -> hardware default).
int resolve_threads(int configured);

}  // namespace dedup
