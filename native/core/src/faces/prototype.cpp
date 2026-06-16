// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/prototype.h"

#include <cmath>

namespace photo::faces {

namespace {

void l2_normalize(Embedding& v) {
    double s = 0.0;
    for (float x : v) s += static_cast<double>(x) * x;
    const float n = static_cast<float>(std::sqrt(s));
    if (n > 1e-12f)
        for (float& x : v) x /= n;
}

float cosine(const Embedding& a, const Embedding& b) {
    if (a.size() != b.size() || a.empty()) return -1.0f;
    double dot = 0.0;
    for (size_t i = 0; i < a.size(); ++i) dot += static_cast<double>(a[i]) * b[i];
    return static_cast<float>(dot);  // both L2-normalized -> dot == cosine
}

// Normalized mean of a running sum over `count` vectors.
Embedding normalized_mean(const Embedding& sum, int count) {
    if (count <= 0 || sum.empty()) return {};
    Embedding mean = sum;
    for (float& x : mean) x /= static_cast<float>(count);
    l2_normalize(mean);
    return mean;
}

}  // namespace

void PrototypeIndex::rebuild(
    const std::unordered_map<int64_t, std::vector<Embedding>>& confirmed) {
    by_person_.clear();
    for (const auto& [pid, vecs] : confirmed) {
        Entry e;
        for (const auto& v : vecs) {
            if (e.sum.empty()) e.sum.assign(v.size(), 0.0f);
            if (v.size() != e.sum.size()) continue;
            for (size_t i = 0; i < v.size(); ++i) e.sum[i] += v[i];
            ++e.count;
        }
        e.mean = normalized_mean(e.sum, e.count);
        by_person_.emplace(pid, std::move(e));
    }
}

void PrototypeIndex::add_confirmed(int64_t person_id, const Embedding& v) {
    Entry& e = by_person_[person_id];
    if (e.sum.empty()) e.sum.assign(v.size(), 0.0f);
    if (v.size() != e.sum.size()) return;
    for (size_t i = 0; i < v.size(); ++i) e.sum[i] += v[i];
    ++e.count;
    e.mean = normalized_mean(e.sum, e.count);
}

void PrototypeIndex::remove(int64_t person_id, const Embedding& v) {
    auto it = by_person_.find(person_id);
    if (it == by_person_.end()) return;
    Entry& e = it->second;
    if (v.size() != e.sum.size() || e.count <= 0) return;
    for (size_t i = 0; i < v.size(); ++i) e.sum[i] -= v[i];
    --e.count;
    if (e.count == 0) by_person_.erase(it);
    else e.mean = normalized_mean(e.sum, e.count);
}

PrototypeIndex::Match PrototypeIndex::nearest(const Embedding& v) const {
    // Seed below the cosine floor [-1,1] so the first real candidate always
    // wins — otherwise an all-negative-cosine index would report "no match"
    // (person_id == -1) even when non-empty, violating the header contract and
    // hiding the true nearest person from the caller's own threshold.
    Match best;
    float best_sim = -2.0f;
    for (const auto& [pid, e] : by_person_) {
        if (e.mean.empty()) continue;
        const float s = cosine(v, e.mean);
        if (s > best_sim) { best_sim = s; best = {pid, s}; }
    }
    return best;
}

std::vector<Embedding> PrototypeIndex::prototypes() const {
    std::vector<Embedding> out;
    out.reserve(by_person_.size());
    for (const auto& [pid, e] : by_person_)
        if (!e.mean.empty()) out.push_back(e.mean);
    return out;
}

std::vector<int64_t> PrototypeIndex::person_ids() const {
    std::vector<int64_t> out;
    out.reserve(by_person_.size());
    for (const auto& [pid, e] : by_person_)
        if (!e.mean.empty()) out.push_back(pid);
    return out;
}

}  // namespace photo::faces
