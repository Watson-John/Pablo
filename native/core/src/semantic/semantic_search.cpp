// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "semantic/semantic_search.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <unordered_set>

#ifdef _WIN32
#include <fstream>
#else
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace photo::semantic {

namespace {
float cosine(const std::vector<float>& a, const std::vector<float>& b) {
    double dot = 0.0, na = 0.0, nb = 0.0;
    for (size_t i = 0; i < a.size(); ++i) {
        dot += static_cast<double>(a[i]) * b[i];
        na += static_cast<double>(a[i]) * a[i];
        nb += static_cast<double>(b[i]) * b[i];
    }
    if (na <= 1e-12 || nb <= 1e-12) return 0.0f;
    return static_cast<float>(dot / (std::sqrt(na) * std::sqrt(nb)));
}
}  // namespace

std::vector<SearchHit> cosine_rank(
    const std::vector<float>& query,
    const std::vector<catalog::Catalog::EmbeddingVec>& items,
    const std::vector<int64_t>& candidates, size_t cap) {
    std::vector<SearchHit> hits;
    if (query.empty() || cap == 0) return hits;

    std::unordered_set<int64_t> allow;
    if (!candidates.empty()) {
        allow.reserve(candidates.size() * 2);
        for (int64_t id : candidates) allow.insert(id);
    }

    hits.reserve(items.size());
    for (const auto& it : items) {
        if (it.vec.size() != query.size()) continue;
        if (!allow.empty() && allow.find(it.asset_id) == allow.end()) continue;
        hits.push_back({it.asset_id, cosine(query, it.vec)});
    }

    const size_t k = std::min(cap, hits.size());
    std::partial_sort(hits.begin(), hits.begin() + k, hits.end(),
                      [](const SearchHit& a, const SearchHit& b) {
                          if (a.score != b.score) return a.score > b.score;
                          return a.asset_id < b.asset_id;  // stable tiebreak
                      });
    hits.resize(k);
    return hits;
}

// ── SidecarIndex ─────────────────────────────────────────────────────────────

namespace {

constexpr char kMagic[8] = {'P', 'A', 'B', 'V', 'I', 'D', 'X', '1'};
constexpr size_t kHeaderBytes = 48;

struct Header {
    char     magic[8];
    uint32_t dim;
    uint32_t row_bytes;
    uint64_t count;
    uint64_t model_hash;
    int64_t  stamp_count;
    int64_t  stamp_max_updated_ns;
};
static_assert(sizeof(Header) == kHeaderBytes, "sidecar header layout");

// Row = i64 asset_id + f32 scale + i8[dim], padded up to 8-byte multiples so
// every row starts aligned (loads still go through memcpy for strictness).
size_t row_bytes_for(int dim) {
    const size_t raw = 8 + 4 + static_cast<size_t>(dim);
    return (raw + 7) & ~size_t{7};
}

}  // namespace

uint64_t SidecarIndex::model_hash(const std::string& model_id,
                                  const std::string& model_version, int dim) {
    const std::string key =
        model_id + ":" + model_version + ":" + std::to_string(dim);
    uint64_t h = 1469598103934665603ull;  // FNV-1a 64
    for (unsigned char c : key) {
        h ^= c;
        h *= 1099511628211ull;
    }
    return h;
}

bool SidecarIndex::write(
    const std::string& path,
    const std::vector<catalog::Catalog::EmbeddingVec>& items, int dim,
    uint64_t model_hash, const catalog::Catalog::EmbeddingStamp& stamp) {
    if (dim <= 0) return false;
    const size_t rb = row_bytes_for(dim);

    const std::string tmp = path + ".tmp";
    std::FILE* f = std::fopen(tmp.c_str(), "wb");
    if (!f) return false;

    uint64_t written = 0;
    std::vector<uint8_t> row(rb);
    bool ok = true;

    // Header goes last-known-count first; rewritten after the rows (we only
    // learn the kept count while quantizing). Reserve the slot now.
    Header hdr{};
    std::memcpy(hdr.magic, kMagic, 8);
    hdr.dim = static_cast<uint32_t>(dim);
    hdr.row_bytes = static_cast<uint32_t>(rb);
    hdr.model_hash = model_hash;
    hdr.stamp_count = stamp.count;
    hdr.stamp_max_updated_ns = stamp.max_updated_ns;
    ok = std::fwrite(&hdr, kHeaderBytes, 1, f) == 1;

    for (const auto& it : items) {
        if (!ok) break;
        if (static_cast<int>(it.vec.size()) != dim) continue;  // stale model
        float amax = 0.0f;
        for (float x : it.vec) amax = std::max(amax, std::fabs(x));
        const float scale = amax > 0.0f ? amax / 127.0f : 0.0f;
        const float inv = scale > 0.0f ? 1.0f / scale : 0.0f;

        std::memset(row.data(), 0, rb);
        std::memcpy(row.data(), &it.asset_id, 8);
        std::memcpy(row.data() + 8, &scale, 4);
        int8_t* q = reinterpret_cast<int8_t*>(row.data() + 12);
        for (int i = 0; i < dim; ++i) {
            const float v = it.vec[static_cast<size_t>(i)] * inv;
            q[i] = static_cast<int8_t>(
                std::lround(std::max(-127.0f, std::min(127.0f, v))));
        }
        ok = std::fwrite(row.data(), rb, 1, f) == 1;
        ++written;
    }

    if (ok) {
        hdr.count = written;
        ok = std::fseek(f, 0, SEEK_SET) == 0 &&
             std::fwrite(&hdr, kHeaderBytes, 1, f) == 1;
    }
    ok = (std::fclose(f) == 0) && ok;
    if (!ok) {
        std::remove(tmp.c_str());
        return false;
    }
    std::remove(path.c_str());  // Windows rename won't overwrite
    if (std::rename(tmp.c_str(), path.c_str()) != 0) {
        std::remove(tmp.c_str());
        return false;
    }
    return true;
}

std::shared_ptr<const SidecarIndex> SidecarIndex::open(const std::string& path) {
    auto idx = std::shared_ptr<SidecarIndex>(new SidecarIndex());

#ifdef _WIN32
    std::ifstream f(path, std::ios::binary);
    if (!f) return nullptr;
    idx->heap_.assign(std::istreambuf_iterator<char>(f),
                      std::istreambuf_iterator<char>());
    const uint8_t* base = idx->heap_.data();
    const size_t len = idx->heap_.size();
#else
    const int fd = ::open(path.c_str(), O_RDONLY);
    if (fd < 0) return nullptr;
    struct stat st{};
    if (::fstat(fd, &st) != 0 || st.st_size < 0) {
        ::close(fd);
        return nullptr;
    }
    const size_t len = static_cast<size_t>(st.st_size);
    void* map = len > 0 ? ::mmap(nullptr, len, PROT_READ, MAP_SHARED, fd, 0)
                        : MAP_FAILED;
    ::close(fd);  // mapping keeps its own reference
    if (map == MAP_FAILED) return nullptr;
    idx->map_ = map;
    idx->map_len_ = len;
    const uint8_t* base = static_cast<const uint8_t*>(map);
#endif

    if (len < kHeaderBytes) return nullptr;
    Header hdr;
    std::memcpy(&hdr, base, kHeaderBytes);
    if (std::memcmp(hdr.magic, kMagic, 8) != 0) return nullptr;
    if (hdr.dim == 0 || hdr.dim > 65536) return nullptr;
    if (hdr.row_bytes != row_bytes_for(static_cast<int>(hdr.dim)))
        return nullptr;
    const size_t need =
        kHeaderBytes + static_cast<size_t>(hdr.count) * hdr.row_bytes;
    if (len < need) return nullptr;  // truncated → treat as corrupt

    idx->rows_ = base + kHeaderBytes;
    idx->row_bytes_ = hdr.row_bytes;
    idx->dim_ = static_cast<int>(hdr.dim);
    idx->count_ = static_cast<int64_t>(hdr.count);
    idx->model_hash_ = hdr.model_hash;
    idx->stamp_count_ = hdr.stamp_count;
    idx->stamp_max_updated_ns_ = hdr.stamp_max_updated_ns;
    return idx;
}

std::vector<SearchHit> SidecarIndex::scan(const std::vector<float>& query,
                                          const std::vector<int64_t>& candidates,
                                          size_t cap) const {
    std::vector<SearchHit> hits;
    if (query.size() != static_cast<size_t>(dim_) || cap == 0 || !rows_)
        return hits;

    std::unordered_set<int64_t> allow;
    if (!candidates.empty()) {
        allow.reserve(candidates.size() * 2);
        for (int64_t id : candidates) allow.insert(id);
    }

    hits.reserve(static_cast<size_t>(count_));
    const uint8_t* p = rows_;
    for (int64_t r = 0; r < count_; ++r, p += row_bytes_) {
        int64_t id;
        float scale;
        std::memcpy(&id, p, 8);
        if (!allow.empty() && allow.find(id) == allow.end()) continue;
        std::memcpy(&scale, p + 8, 4);
        const int8_t* q = reinterpret_cast<const int8_t*>(p + 12);
        float acc = 0.0f;
        for (int i = 0; i < dim_; ++i)
            acc += query[static_cast<size_t>(i)] * static_cast<float>(q[i]);
        hits.push_back({id, acc * scale});
    }

    const size_t k = std::min(cap, hits.size());
    std::partial_sort(hits.begin(), hits.begin() + k, hits.end(),
                      [](const SearchHit& a, const SearchHit& b) {
                          if (a.score != b.score) return a.score > b.score;
                          return a.asset_id < b.asset_id;
                      });
    hits.resize(k);
    return hits;
}

SidecarIndex::~SidecarIndex() {
#ifndef _WIN32
    if (map_ && map_len_ > 0) ::munmap(map_, map_len_);
#endif
}

}  // namespace photo::semantic
