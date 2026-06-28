// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/cluster.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <unordered_map>
#include <vector>

#include "dedup/decode.h"  // is_raw_format
#include "dedup/log.h"

namespace dedup {
namespace {

// Higher score == better keeper. We have no decoded pixel dims in the record,
// so byte size stands in for resolution; RAW masters always win. (A future
// pass could store width*height for an exact resolution comparison.)
double keeper_score(const ImageRecord& r) {
    double s = static_cast<double>(r.size_bytes);
    if (is_raw_format(r.format)) s += 1e15;  // RAW dominates re-encoded copies
    return s;
}

// Burst-shot / photo-series guard. Real archival duplicates (rescans, re-exports
// of one picture) are typically FAR apart in capture time, whereas burst frames
// that merely share a backdrop sit near the threshold AND seconds apart. So when
// enabled we drop borderline edges whose endpoints are temporally close.
// NOTE: uses filesystem mtime as a proxy until EXIF capture-time parsing lands.
bool fails_time_guard(const Neighbor& e,
                      const std::unordered_map<int64_t, ImageRecord>& by_id,
                      const Config& cfg) {
    if (!cfg.exif_time_guard) return false;
    constexpr double kBorderlineMargin = 0.05;
    if (e.score >= cfg.threshold + kBorderlineMargin) return false;  // confident
    auto ia = by_id.find(e.a), ib = by_id.find(e.b);
    if (ia == by_id.end() || ib == by_id.end()) return false;
    const int64_t window_ns = static_cast<int64_t>(cfg.exif_time_window_sec) * 1000000000LL;
    const int64_t dt = std::llabs(ia->second.mtime_ns - ib->second.mtime_ns);
    return dt <= window_ns;  // close in time + borderline -> likely a burst frame
}

}  // namespace

std::vector<Cluster> cluster_edges(
    const std::vector<Neighbor>& edges,
    const std::unordered_map<int64_t, ImageRecord>& records_by_id,
    const Config& cfg) {

    // Compact the ids that actually appear in an edge into [0, m).
    std::unordered_map<int64_t, size_t> idx_of;
    std::vector<int64_t> id_of;
    auto intern = [&](int64_t id) -> size_t {
        auto it = idx_of.find(id);
        if (it != idx_of.end()) return it->second;
        size_t k = id_of.size();
        idx_of.emplace(id, k);
        id_of.push_back(id);
        return k;
    };

    size_t guarded = 0;
    std::vector<std::pair<size_t, size_t>> kept;
    kept.reserve(edges.size());
    for (const auto& e : edges) {
        if (fails_time_guard(e, records_by_id, cfg)) { ++guarded; continue; }
        kept.emplace_back(intern(e.a), intern(e.b));
    }

    UnionFind uf(id_of.size());
    for (auto& [u, v] : kept) uf.unite(u, v);

    // Gather components.
    std::unordered_map<size_t, std::vector<int64_t>> comps;
    for (size_t i = 0; i < id_of.size(); ++i) comps[uf.find(i)].push_back(id_of[i]);

    std::vector<Cluster> clusters;
    int64_t next_id = 1;
    size_t oversize = 0;
    for (auto& [root, members] : comps) {
        if (members.size() < 2) continue;
        std::sort(members.begin(), members.end());

        Cluster c;
        c.id = next_id++;
        c.members = std::move(members);

        // Suggested keeper.
        int64_t best = c.members.front();
        double best_score = -1.0;
        for (int64_t id : c.members) {
            auto it = records_by_id.find(id);
            double s = (it != records_by_id.end()) ? keeper_score(it->second) : 0.0;
            if (s > best_score) { best_score = s; best = id; }
        }
        c.suggested_keeper = best;

        if (static_cast<int>(c.members.size()) > cfg.max_cluster_size) {
            c.flagged_oversize = true;
            ++oversize;
            LOG_WARN("cluster " << c.id << " has " << c.members.size()
                     << " members (> max_cluster_size=" << cfg.max_cluster_size
                     << ") — possible transitive drift; flagged for manual review");
        }
        clusters.push_back(std::move(c));
    }

    std::sort(clusters.begin(), clusters.end(),
              [](const Cluster& a, const Cluster& b) {
                  return a.members.size() > b.members.size();
              });
    // Re-number after the size sort so ids are stable/presentation-ordered.
    for (size_t i = 0; i < clusters.size(); ++i) clusters[i].id = static_cast<int64_t>(i + 1);

    LOG_INFO("cluster: " << clusters.size() << " near-duplicate cluster(s)"
             << (guarded ? ", " + std::to_string(guarded) + " edge(s) dropped by time-guard" : "")
             << (oversize ? ", " + std::to_string(oversize) + " oversize" : ""));
    return clusters;
}

}  // namespace dedup
