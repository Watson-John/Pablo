// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/index.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#include "dedup/log.h"
#include "dedup/parallel.h"

#ifdef DEDUP_HAVE_FAISS
#include <faiss/IndexFlat.h>
#endif

namespace dedup {
namespace {

#ifdef DEDUP_HAVE_FAISS
// FAISS exact inner-product index. Vectors are unit-norm, so IP == cosine.
class FaissFlatIndex final : public SimilarityIndex {
public:
    explicit FaissFlatIndex(int d) : index_(d), dim_(d) {}

    void add(const float* data, int64_t n) override { index_.add(n, data); }

    void search(const float* queries, int64_t nq, int k,
                std::vector<int64_t>& labels,
                std::vector<float>& scores) const override {
        labels.assign(static_cast<size_t>(nq) * k, -1);
        scores.assign(static_cast<size_t>(nq) * k,
                      -std::numeric_limits<float>::infinity());
        static_assert(sizeof(faiss::idx_t) == sizeof(int64_t));
        index_.search(nq, queries, k, scores.data(),
                      reinterpret_cast<faiss::idx_t*>(labels.data()));
    }

    int dim() const override { return dim_; }
    int64_t size() const override { return index_.ntotal; }

private:
    faiss::IndexFlatIP index_;
    int dim_;
};
#endif  // DEDUP_HAVE_FAISS

// Exact brute-force IP search. Identical results to FAISS at lower throughput;
// queries are independent so we fan them across the thread pool.
class BruteForceIndex final : public SimilarityIndex {
public:
    explicit BruteForceIndex(int d) : dim_(d) {}

    void add(const float* data, int64_t n) override {
        data_.insert(data_.end(), data, data + static_cast<size_t>(n) * dim_);
        n_ += n;
    }

    void search(const float* queries, int64_t nq, int k,
                std::vector<int64_t>& labels,
                std::vector<float>& scores) const override {
        labels.assign(static_cast<size_t>(nq) * k, -1);
        scores.assign(static_cast<size_t>(nq) * k,
                      -std::numeric_limits<float>::infinity());
        const int kk = std::min<int>(k, static_cast<int>(n_));
        parallel_for(static_cast<size_t>(nq), 0, [&](size_t qi) {
            const float* q = queries + qi * dim_;
            // (score, label) heap of size kk, smallest-score on top.
            std::vector<std::pair<float, int64_t>> top;
            top.reserve(kk + 1);
            auto cmp = [](const auto& a, const auto& b) { return a.first > b.first; };
            for (int64_t j = 0; j < n_; ++j) {
                const float* v = data_.data() + static_cast<size_t>(j) * dim_;
                float dot = 0.0f;
                for (int d = 0; d < dim_; ++d) dot += q[d] * v[d];
                if (static_cast<int>(top.size()) < kk) {
                    top.emplace_back(dot, j);
                    std::push_heap(top.begin(), top.end(), cmp);
                } else if (dot > top.front().first) {
                    std::pop_heap(top.begin(), top.end(), cmp);
                    top.back() = {dot, j};
                    std::push_heap(top.begin(), top.end(), cmp);
                }
            }
            std::sort_heap(top.begin(), top.end(), cmp);  // descending score
            for (size_t r = 0; r < top.size(); ++r) {
                labels[qi * k + r] = top[r].second;
                scores[qi * k + r] = top[r].first;
            }
        });
    }

    int dim() const override { return dim_; }
    int64_t size() const override { return n_; }

private:
    std::vector<float> data_;
    int dim_;
    int64_t n_ = 0;
};

}  // namespace

std::unique_ptr<SimilarityIndex> make_index(int dim) {
#ifdef DEDUP_HAVE_FAISS
    LOG_DEBUG("index: FAISS IndexFlatIP (dim=" << dim << ")");
    return std::make_unique<FaissFlatIndex>(dim);
#else
    LOG_DEBUG("index: brute-force fallback (dim=" << dim << ")");
    return std::make_unique<BruteForceIndex>(dim);
#endif
}

std::vector<Neighbor> build_neighbor_edges(const SimilarityIndex& index,
                                           const float* vectors,
                                           const std::vector<int64_t>& ids,
                                           int k, float threshold, bool mutual,
                                           bool score_norm, float norm_beta) {
    const int64_t n = static_cast<int64_t>(ids.size());
    if (n == 0) return {};

    // Score normalization needs a deeper neighbour list to estimate each image's
    // background similarity from the tail; otherwise just the top-k for edges.
    constexpr int kNormK = 64, kNormSkip = 8;
    const int search_k = score_norm ? std::max(k, kNormK) : k;

    std::vector<int64_t> labels;
    std::vector<float> scores;
    index.search(vectors, n, search_k, labels, scores);

    // Background score b[i]: mean similarity over neighbour ranks [skip, search_k)
    // — the confusable-but-different tail, skipping the top few likely true dups.
    std::vector<float> bg;
    if (score_norm && search_k > kNormSkip) {
        bg.assign(static_cast<size_t>(n), 0.0f);
        for (int64_t i = 0; i < n; ++i) {
            double sum = 0.0; int cnt = 0;
            for (int j = kNormSkip; j < search_k; ++j) {
                const float s = scores[static_cast<size_t>(i) * search_k + j];
                if (labels[static_cast<size_t>(i) * search_k + j] < 0) continue;
                sum += s; ++cnt;
            }
            bg[i] = cnt ? static_cast<float>(sum / cnt) : 0.0f;
        }
    }

    // Collect each directed hit as an undirected (a<b) candidate. The number of
    // times a given (a,b) appears tells us reciprocity: 2 = mutual (each is in
    // the other's top-k), 1 = one-directional.
    std::vector<Neighbor> edges;
    edges.reserve(static_cast<size_t>(n) * 2);
    for (int64_t i = 0; i < n; ++i) {
        for (int j = 0; j < k; ++j) {  // edges only from the top-k
            const int64_t label = labels[static_cast<size_t>(i) * search_k + j];
            if (label < 0 || label == i) continue;  // padding / self-match
            float s = scores[static_cast<size_t>(i) * search_k + j];
            if (!bg.empty()) s -= norm_beta * (bg[i] + bg[label]) * 0.5f;  // stretch
            if (s < threshold) continue;
            int64_t a = ids[i], b = ids[label];
            if (a == b) continue;
            if (a > b) std::swap(a, b);
            edges.push_back({a, b, s});
        }
    }

    std::sort(edges.begin(), edges.end(), [](const Neighbor& x, const Neighbor& y) {
        if (x.a != y.a) return x.a < y.a;
        if (x.b != y.b) return x.b < y.b;
        return x.score > y.score;
    });

    // Collapse each (a,b) run: keep max score (first after the sort) and the
    // run length as the reciprocity count.
    std::vector<Neighbor> out;
    out.reserve(edges.size());
    size_t dropped_nonmutual = 0;
    for (size_t i = 0; i < edges.size();) {
        size_t j = i + 1;
        while (j < edges.size() && edges[j].a == edges[i].a && edges[j].b == edges[i].b) ++j;
        const size_t run = j - i;
        if (mutual && run < 2) {
            ++dropped_nonmutual;
        } else {
            out.push_back(edges[i]);  // highest score in the run
        }
        i = j;
    }
    LOG_INFO("index: " << out.size() << " neighbour edge(s) at threshold "
                       << threshold << (mutual ? " (mutual-kNN; dropped "
                       + std::to_string(dropped_nonmutual) + " one-directional)" : ""));
    return out;
}

}  // namespace dedup
