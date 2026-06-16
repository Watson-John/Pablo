// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/pipeline.h"

#include <algorithm>
#include <optional>
#include <vector>

#include <opencv2/core.hpp>

#include "dedup/cluster.h"
#include "dedup/decode.h"
#include "dedup/embed.h"
#include "dedup/index.h"
#include "dedup/ingest.h"
#include "dedup/log.h"
#include "dedup/parallel.h"

namespace dedup {
namespace {

// Pick the exact-group representative we actually embed: the highest-quality
// copy (RAW first, then largest). All members fold into its cluster later.
size_t pick_representative(const std::vector<size_t>& group,
                           const std::vector<ImageRecord>& recs) {
    size_t best = group.front();
    double best_score = -1.0;
    for (size_t idx : group) {
        const ImageRecord& r = recs[idx];
        double s = static_cast<double>(r.size_bytes) + (is_raw_format(r.format) ? 1e15 : 0.0);
        if (s > best_score) { best_score = s; best = idx; }
    }
    return best;
}

// Index the embedded representatives and cluster (SSCD edges + exact-group
// edges). Shared by run_scan and recluster_only.
void recluster(const Config& cfg, Store& store, ScanStats& stats) {
    std::vector<Neighbor> edges;

    // SSCD edges — only when embeddings exist. In hash-only mode (embed disabled)
    // there are none, and clustering proceeds purely from the exact/perceptual
    // hash groups below.
    auto embedded = store.embedded_images();
    if (!embedded.empty()) {
        const int dim = store.vectors().dim();
        std::vector<float> matrix = store.vectors().load_all();
        std::vector<float> packed(static_cast<size_t>(embedded.size()) * dim);
        std::vector<int64_t> ids(embedded.size());
        size_t m = 0;
        for (const auto& r : embedded) {
            const size_t off = static_cast<size_t>(r.vec_row) * dim;
            if (r.vec_row < 0 || off + dim > matrix.size()) continue;  // skip orphan
            std::copy_n(matrix.data() + off, dim, packed.data() + m * dim);
            ids[m] = r.id;
            ++m;
        }
        packed.resize(m * dim);
        ids.resize(m);

        auto index = make_index(dim);
        index->add(packed.data(), static_cast<int64_t>(m));
        edges = build_neighbor_edges(*index, packed.data(), ids, cfg.k,
                                     static_cast<float>(cfg.threshold), cfg.mutual_knn,
                                     cfg.score_norm, static_cast<float>(cfg.score_norm_beta));
    } else {
        LOG_INFO("recluster: no embeddings — clustering from exact/perceptual-hash "
                 "groups only (hash-only mode)");
    }

    // Fold exact duplicates back in: a star edge from each duplicate to its
    // representative (score 1.0 so the time-guard never drops them).
    for (auto& [id, rep] : store.dup_edges()) {
        int64_t a = id, b = rep;
        if (a == b) continue;
        if (a > b) std::swap(a, b);
        edges.push_back({a, b, 1.0f});
    }

    auto by_id = store.all_by_id();
    std::vector<Cluster> clusters = cluster_edges(edges, by_id, cfg);
    store.replace_clusters(clusters);

    stats.clusters = clusters.size();
    for (const auto& c : clusters) {
        stats.images_in_clusters += c.members.size();
        if (c.flagged_oversize) ++stats.flagged_oversize;
    }
}

// Decode + embed everything in `needing`, in batches. Resumable: each vector is
// persisted as it is produced, so an interrupted run continues where it stopped.
void embed_missing(const Config& cfg, Store& store,
                   std::vector<ImageRecord>& needing, ScanStats& stats) {
    if (needing.empty()) {
        LOG_INFO("embed: all representatives already embedded — skipping");
        return;
    }
    if (!Embedder::available()) {
        throw std::runtime_error(
            "embedding required for " + std::to_string(needing.size()) +
            " image(s) but this build has no ONNX Runtime — rebuild with "
            "-DONNXRUNTIME_ROOT=<dist>");
    }

    Embedder embedder(cfg);
    const int dim = embedder.dim();
    const int batch = std::max(1, cfg.batch_size);
    const int threads = resolve_threads(cfg.decode_threads);

    for (size_t start = 0; start < needing.size(); start += batch) {
        const size_t end = std::min(needing.size(), start + batch);
        const size_t n = end - start;

        // Parallel decode the chunk.
        std::vector<std::optional<cv::Mat>> decoded(n);
        parallel_for(n, threads, [&](size_t i) {
            decoded[i] = decode_for_embedding(needing[start + i], cfg);
        });

        std::vector<cv::Mat> mats;
        std::vector<int64_t> ids;
        mats.reserve(n);
        ids.reserve(n);
        for (size_t i = 0; i < n; ++i) {
            if (decoded[i]) {
                mats.push_back(std::move(*decoded[i]));
                ids.push_back(needing[start + i].id);
            } else {
                ++stats.decode_failures;
            }
        }
        if (mats.empty()) continue;

        std::vector<float> vecs = embedder.embed_batch(mats);
        for (size_t i = 0; i < ids.size(); ++i) {
            store.set_embedding(ids[i], vecs.data() + i * dim, dim);
            ++stats.newly_embedded;
        }
        store.vectors().flush();
        LOG_INFO("embed: " << stats.newly_embedded << "/" << needing.size()
                           << " (failures: " << stats.decode_failures << ")");
    }
}

}  // namespace

ScanStats run_scan(const Config& cfg, Store& store) {
    ScanStats stats;

    // Stage 1 — enumerate.
    std::vector<ImageRecord> records = enumerate_images(cfg);
    stats.enumerated = records.size();
    if (records.empty()) {
        LOG_WARN("scan: no images found under the configured roots");
        return stats;
    }

    // Stage 2 — exact-dupe pre-filter (content hash + pHash).
    if (cfg.exact_content_hash) compute_content_hashes(records, cfg);
    for (auto& r : records) {
        store.upsert_image(r);                       // assigns r.id
        if (!r.content_hash.empty()) store.update_hash(r.id, r.content_hash);
    }
    ExactGroups exact = exact_duplicate_pass(records, cfg);
    stats.exact_groups = exact.groups.size();

    // Persist pHash + duplicate-of links; representatives stay embeddable.
    for (auto& r : records) {
        if (r.phash_valid) store.update_phash(r.id, r.phash);
    }
    for (const auto& group : exact.groups) {
        const size_t rep = pick_representative(group, records);
        const int64_t rep_id = records[rep].id;
        for (size_t idx : group) {
            if (idx != rep) store.set_dup_of(records[idx].id, rep_id);
        }
    }

    // Stages 3–4 — decode + embed the representatives (resumable). Skipped in
    // hash-only mode (embed.enabled=false) — for low-end PCs / a fast first pass.
    if (cfg.embed_enabled) {
        std::vector<ImageRecord> needing = store.images_needing_embedding();
        stats.already_embedded = store.embedded_images().size();
        embed_missing(cfg, store, needing, stats);
    } else {
        LOG_INFO("scan: hash-only mode (embed disabled) — skipping SSCD embedding");
    }

    // Stages 5–6 — index + cluster.
    recluster(cfg, store, stats);

    LOG_INFO("scan complete: " << stats.enumerated << " enumerated, "
             << stats.newly_embedded << " newly embedded, " << stats.clusters
             << " cluster(s) covering " << stats.images_in_clusters << " image(s)");
    return stats;
}

ScanStats recluster_only(const Config& cfg, Store& store) {
    ScanStats stats;
    stats.already_embedded = store.embedded_images().size();
    recluster(cfg, store, stats);
    return stats;
}

}  // namespace dedup
