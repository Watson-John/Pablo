// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/config.h"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <stdexcept>
#include <thread>

#include <yaml-cpp/yaml.h>

#include "dedup/log.h"

namespace dedup {
namespace {

namespace fs = std::filesystem;

// Read scalar `node[key]` into `out` if present, leaving the default otherwise.
template <typename T>
void get(const YAML::Node& node, const char* key, T& out) {
    if (node && node[key] && !node[key].IsNull()) {
        out = node[key].as<T>();
    }
}

void get_lower_list(const YAML::Node& node, const char* key,
                    std::vector<std::string>& out) {
    if (node && node[key] && node[key].IsSequence()) {
        out.clear();
        for (const auto& e : node[key]) {
            std::string s = e.as<std::string>();
            std::transform(s.begin(), s.end(), s.begin(),
                           [](unsigned char c) { return std::tolower(c); });
            out.push_back(std::move(s));
        }
    }
}

}  // namespace

Config load_config(const std::string& path) {
    Config cfg;
    if (path.empty() || !fs::exists(path)) {
        LOG_DEBUG("no config file at '" << path << "', using defaults + CLI flags");
        return cfg;
    }

    YAML::Node root;
    try {
        root = YAML::LoadFile(path);
    } catch (const std::exception& e) {
        throw std::runtime_error("failed to parse config '" + path + "': " + e.what());
    }

    get_lower_list(root, "extensions", cfg.extensions);
    if (root["roots"] && root["roots"].IsSequence()) {
        cfg.roots.clear();
        for (const auto& e : root["roots"]) cfg.roots.push_back(e.as<std::string>());
    }

    if (const auto ws = root["workspace"]) {
        get(ws, "db", cfg.db_path);
        get(ws, "vectors", cfg.vectors_path);
        get(ws, "quarantine", cfg.quarantine_dir);
    }
    if (const auto em = root["embed"]) {
        get(em, "model", cfg.model_path);
        get(em, "input_size", cfg.input_size);
        get(em, "batch_size", cfg.batch_size);
        get(em, "provider", cfg.provider);
        get(em, "intra_op_threads", cfg.intra_op_threads);
    }
    if (const auto ix = root["index"]) {
        get(ix, "k", cfg.k);
    }
    if (const auto cl = root["cluster"]) {
        get(cl, "threshold", cfg.threshold);
        get(cl, "mutual_knn", cfg.mutual_knn);
        get(cl, "max_cluster_size", cfg.max_cluster_size);
        get(cl, "exif_time_guard", cfg.exif_time_guard);
        get(cl, "exif_time_window_sec", cfg.exif_time_window_sec);
    }
    if (const auto dc = root["decode"]) {
        get(dc, "threads", cfg.decode_threads);
        get(dc, "prefer_embedded_thumb", cfg.prefer_embedded_thumb);
    }
    if (const auto ex = root["exact"]) {
        get(ex, "content_hash", cfg.exact_content_hash);
        get(ex, "phash_hamming", cfg.phash_hamming);
    }
    if (const auto sv = root["server"]) {
        get(sv, "host", cfg.server_host);
        get(sv, "port", cfg.server_port);
    }

    // Default the web dir to a sibling of the config file if not overridden.
    if (cfg.web_dir == "./web") {
        fs::path candidate = fs::path(path).parent_path() / "web";
        if (fs::exists(candidate)) cfg.web_dir = candidate.string();
    }
    return cfg;
}

int resolve_threads(int configured) {
    if (configured > 0) return configured;
    unsigned hc = std::thread::hardware_concurrency();
    return hc > 0 ? static_cast<int>(hc) : 4;
}

}  // namespace dedup
