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
    std::vector<std::string> extensions;

    // Workspace (persisted state — embedding runs once).
    std::string db_path = "./dedup.db";
    std::string vectors_path = "./vectors.f32";
    std::string quarantine_dir = "./quarantine";

    // Embedding.
    std::string model_path = "./models/sscd_disc_mixup.onnx";
    int input_size = 288;
    int batch_size = 64;
    std::string provider = "cpu";   // "cpu" | "cuda"
    int intra_op_threads = 0;       // 0 = ORT default

    // Indexing.
    int k = 20;

    // Clustering.
    double threshold = 0.80;
    bool mutual_knn = true;
    int max_cluster_size = 400;
    bool exif_time_guard = false;
    int exif_time_window_sec = 5;

    // Decode / throughput.
    int decode_threads = 0;         // 0 = hardware_concurrency
    bool prefer_embedded_thumb = true;

    // Exact-duplicate pre-filter.
    bool exact_content_hash = true;
    int phash_hamming = 6;

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
