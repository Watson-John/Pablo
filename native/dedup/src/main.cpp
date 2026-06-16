// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// CLI: `dedup <scan|serve|calibrate> [flags]`.

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "dedup/config.h"
#include "dedup/log.h"
#include "dedup/pipeline.h"
#include "dedup/server.h"
#include "dedup/store.h"

namespace {

using dedup::Config;

struct Args {
    std::string command;
    std::map<std::string, std::string> flags;

    bool has(const std::string& k) const { return flags.count(k) != 0; }
    std::string str(const std::string& k, const std::string& dflt = "") const {
        auto it = flags.find(k);
        return it == flags.end() ? dflt : it->second;
    }
    int integer(const std::string& k, int dflt) const {
        auto it = flags.find(k);
        return it == flags.end() ? dflt : std::atoi(it->second.c_str());
    }
    double number(const std::string& k, double dflt) const {
        auto it = flags.find(k);
        return it == flags.end() ? dflt : std::atof(it->second.c_str());
    }
};

Args parse_args(int argc, char** argv) {
    Args a;
    std::vector<std::string> tok(argv + 1, argv + argc);
    for (size_t i = 0; i < tok.size(); ++i) {
        const std::string& t = tok[i];
        if (t.rfind("--", 0) == 0) {
            std::string key = t.substr(2);
            auto eq = key.find('=');
            if (eq != std::string::npos) {
                a.flags[key.substr(0, eq)] = key.substr(eq + 1);
            } else if (i + 1 < tok.size() && tok[i + 1].rfind("--", 0) != 0) {
                a.flags[key] = tok[++i];
            } else {
                a.flags[key] = "1";  // boolean flag
            }
        } else if (a.command.empty()) {
            a.command = t;
        }
    }
    return a;
}

std::vector<std::string> split_commas(const std::string& s) {
    std::vector<std::string> out;
    std::stringstream ss(s);
    std::string item;
    while (std::getline(ss, item, ',')) {
        if (!item.empty()) out.push_back(item);
    }
    return out;
}

// Apply CLI overrides on top of the loaded config.
void apply_overrides(Config& cfg, const Args& a) {
    if (a.has("roots"))      cfg.roots = split_commas(a.str("roots"));
    if (a.has("extensions")) {
        cfg.extensions = split_commas(a.str("extensions"));
        for (auto& e : cfg.extensions) {
            std::transform(e.begin(), e.end(), e.begin(),
                           [](unsigned char c) { return std::tolower(c); });
        }
    }
    if (a.has("model"))      cfg.model_path = a.str("model");
    if (a.has("provider"))   cfg.provider = a.str("provider");
    if (a.has("db"))         cfg.db_path = a.str("db");
    if (a.has("vectors"))    cfg.vectors_path = a.str("vectors");
    if (a.has("quarantine")) cfg.quarantine_dir = a.str("quarantine");
    if (a.has("web"))        cfg.web_dir = a.str("web");
    if (a.has("threshold"))  cfg.threshold = a.number("threshold", cfg.threshold);
    if (a.has("k"))          cfg.k = a.integer("k", cfg.k);
    if (a.has("batch-size")) cfg.batch_size = a.integer("batch-size", cfg.batch_size);
    if (a.has("input-size")) cfg.input_size = a.integer("input-size", cfg.input_size);
    if (a.has("square"))     cfg.resize_mode = "squash";
    if (a.has("resize-mode")) cfg.resize_mode = a.str("resize-mode");
    if (a.has("threads"))    cfg.decode_threads = a.integer("threads", cfg.decode_threads);
    if (a.has("port"))       cfg.server_port = a.integer("port", cfg.server_port);
    if (a.has("host"))       cfg.server_host = a.str("host");
    if (a.has("mutual-knn")) cfg.mutual_knn = a.str("mutual-knn") != "0";
    if (a.has("algorithm"))  cfg.phash_algo = a.str("algorithm");
    if (a.has("hamming"))    cfg.phash_hamming = a.integer("hamming", cfg.phash_hamming);
    if (a.has("hash-only"))  cfg.embed_enabled = false;   // skip SSCD (low-end PCs)
    if (a.has("no-embed"))   cfg.embed_enabled = false;   // alias
    if (a.has("score-norm")) cfg.score_norm = a.str("score-norm") != "0";
    if (a.has("score-norm-beta")) cfg.score_norm_beta = a.number("score-norm-beta", cfg.score_norm_beta);
}

int usage() {
    std::cout <<
        "pablo-dedup — local near-duplicate photo detection\n\n"
        "USAGE:\n"
        "  dedup scan       [--config f] [--roots a,b] [--threshold t] [--model m] ...\n"
        "  dedup calibrate  [--config f] [--from 0.70] [--to 0.90] [--step 0.02]\n"
        "  dedup serve      [--config f] [--host 127.0.0.1] [--port 8755]\n\n"
        "Common flags: --db --vectors --quarantine --k --batch-size --provider\n"
        "              --extensions jpg,png,cr2 --threads --mutual-knn 0|1 --verbose --quiet\n"
        "Pre-filter:   --algorithm phash|blockmean|average|marr  --hamming N\n"
        "Low-end PCs:  --hash-only   (skip SSCD entirely — no model/GPU needed)\n\n"
        "Never deletes: discards are MOVED to the quarantine directory.\n";
    return 2;
}

int cmd_scan(Config& cfg) {
    dedup::Store store(cfg);
    dedup::ScanStats s = dedup::run_scan(cfg, store);
    std::cout << "\n== scan summary ==\n"
              << "  enumerated:        " << s.enumerated << "\n"
              << "  exact dup groups:  " << s.exact_groups << "\n"
              << "  newly embedded:    " << s.newly_embedded << "\n"
              << "  already embedded:  " << s.already_embedded << "\n"
              << "  decode failures:   " << s.decode_failures << "\n"
              << "  clusters:          " << s.clusters << "\n"
              << "  images in clusters:" << s.images_in_clusters << "\n"
              << "  oversize flagged:  " << s.flagged_oversize << "\n"
              << "\nReview with:  dedup serve --config <your-config>\n";
    return 0;
}

int cmd_calibrate(Config& cfg, const Args& a) {
    const double from = a.number("from", 0.20);
    const double to = a.number("to", 0.60);
    const double step = a.number("step", 0.02);
    dedup::Store store(cfg);
    std::cout << "threshold  clusters  images_in_clusters  oversize\n";
    std::cout << "---------  --------  ------------------  --------\n";
    // Index the steps (t = from + i*step) to avoid float accumulation drift.
    const int steps = static_cast<int>((to - from) / step + 0.5);
    for (int i = 0; i <= steps; ++i) {
        cfg.threshold = from + i * step;
        dedup::ScanStats s = dedup::recluster_only(cfg, store);
        std::printf("%8.3f  %8zu  %18zu  %8zu\n", cfg.threshold, s.clusters,
                    s.images_in_clusters, s.flagged_oversize);
    }
    std::cout << "\nPick a threshold in the gap before cluster/image counts "
                 "balloon (the merge knee).\n"
                 "Then: dedup scan --threshold <t> (re-clusters; no re-embed).\n";
    return 0;
}

int cmd_serve(Config& cfg) {
    dedup::Store store(cfg);
    dedup::serve_review(cfg, store);
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    Args a = parse_args(argc, argv);
    if (a.has("verbose")) dedup::set_log_level(dedup::LogLevel::kDebug);
    else if (a.has("quiet")) dedup::set_log_level(dedup::LogLevel::kWarn);

    if (a.command.empty()) return usage();

    try {
        Config cfg = dedup::load_config(a.str("config"));
        apply_overrides(cfg, a);

        if (a.command == "scan")      return cmd_scan(cfg);
        if (a.command == "calibrate") return cmd_calibrate(cfg, a);
        if (a.command == "serve")     return cmd_serve(cfg);
        std::cerr << "unknown command: " << a.command << "\n\n";
        return usage();
    } catch (const std::exception& e) {
        std::cerr << "[ERROR] " << e.what() << "\n";
        return 1;
    }
}
