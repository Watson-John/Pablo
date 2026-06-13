// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/ingest.h"

#include <array>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <unordered_map>
#include <unordered_set>

#include <xxhash.h>

#include "dedup/cluster.h"   // UnionFind
#include "dedup/decode.h"    // perceptual_hash
#include "dedup/log.h"
#include "dedup/parallel.h"

namespace dedup {
namespace fs = std::filesystem;
namespace {

std::string lower_ext(const fs::path& p) {
    std::string e = p.extension().string();
    if (!e.empty() && e[0] == '.') e.erase(e.begin());
    for (char& c : e) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return e;
}

std::string hex128(XXH128_hash_t h) {
    static const char* d = "0123456789abcdef";
    std::string out(32, '0');
    uint64_t parts[2] = {h.high64, h.low64};
    for (int w = 0; w < 2; ++w) {
        uint64_t v = parts[w];
        for (int i = 0; i < 16; ++i) {
            out[w * 16 + (15 - i)] = d[v & 0xf];
            v >>= 4;
        }
    }
    return out;
}

}  // namespace

std::vector<ImageRecord> enumerate_images(const Config& cfg) {
    std::unordered_set<std::string> exts(cfg.extensions.begin(), cfg.extensions.end());
    std::vector<ImageRecord> out;

    for (const auto& root : cfg.roots) {
        std::error_code ec;
        if (!fs::exists(root, ec)) {
            LOG_WARN("root does not exist, skipping: " << root);
            continue;
        }
        auto it = fs::recursive_directory_iterator(
            root, fs::directory_options::skip_permission_denied, ec);
        const auto end = fs::recursive_directory_iterator{};
        for (; it != end; it.increment(ec)) {
            if (ec) { ec.clear(); continue; }
            const fs::directory_entry& entry = *it;
            std::error_code fec;
            if (!entry.is_regular_file(fec)) continue;
            std::string ext = lower_ext(entry.path());
            if (exts.find(ext) == exts.end()) continue;

            ImageRecord rec;
            rec.path = entry.path().string();
            rec.format = ext;
            rec.size_bytes = static_cast<uint64_t>(entry.file_size(fec));
            auto ftime = entry.last_write_time(fec);
            rec.mtime_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                               ftime.time_since_epoch())
                               .count();
            out.push_back(std::move(rec));
        }
    }
    LOG_INFO("enumerated " << out.size() << " image files across "
                           << cfg.roots.size() << " root(s)");
    return out;
}

std::string content_hash_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return {};
    XXH3_state_t* state = XXH3_createState();
    if (!state) return {};
    XXH3_128bits_reset(state);
    std::array<char, 1 << 16> buf;  // 64 KiB streaming window
    while (f) {
        f.read(buf.data(), static_cast<std::streamsize>(buf.size()));
        std::streamsize got = f.gcount();
        if (got > 0) XXH3_128bits_update(state, buf.data(), static_cast<size_t>(got));
    }
    XXH128_hash_t h = XXH3_128bits_digest(state);
    XXH3_freeState(state);
    return hex128(h);
}

void compute_content_hashes(std::vector<ImageRecord>& records, const Config& cfg) {
    const int threads = resolve_threads(cfg.decode_threads);
    parallel_for(records.size(), threads, [&](size_t i) {
        records[i].content_hash = content_hash_file(records[i].path);
    });
}

ExactGroups exact_duplicate_pass(std::vector<ImageRecord>& records, const Config& cfg) {
    ExactGroups result;
    const size_t n = records.size();
    if (n == 0) return result;

    UnionFind uf(n);

    // --- 1. Byte-identical: union records sharing a content hash. ---
    std::unordered_map<std::string, size_t> first_of_hash;
    first_of_hash.reserve(n * 2);
    std::vector<size_t> representatives;  // one index per distinct hash
    for (size_t i = 0; i < n; ++i) {
        const std::string& h = records[i].content_hash;
        if (h.empty()) { representatives.push_back(i); continue; }  // unhashable -> unique
        auto [it, inserted] = first_of_hash.emplace(h, i);
        if (inserted) {
            representatives.push_back(i);
        } else {
            uf.unite(it->second, i);
            ++result.byte_identical_pairs;
        }
    }

    // --- 2. Trivial re-saves: pHash within Hamming threshold (band-LSH). ---
    // Only representatives (distinct bytes) need a pHash — byte-identical copies
    // already collapsed above. We decode a reduced image per representative.
    if (cfg.phash_hamming >= 0) {
        const int threads = resolve_threads(cfg.decode_threads);
        parallel_for(representatives.size(), threads, [&](size_t r) {
            size_t idx = representatives[r];
            if (auto ph = perceptual_hash(records[idx].path)) {
                records[idx].phash = *ph;
                records[idx].phash_valid = true;
            }
        });

        // Pigeonhole band-LSH: split the 64-bit hash into 8 one-byte bands.
        // Two hashes within Hamming d<=7 must agree on at least one band, so we
        // only ever compare within a shared band bucket (near-linear).
        std::array<std::unordered_map<uint8_t, std::vector<size_t>>, 8> bands;
        for (size_t idx : representatives) {
            if (!records[idx].phash_valid) continue;
            uint64_t h = records[idx].phash;
            for (int b = 0; b < 8; ++b) {
                uint8_t key = static_cast<uint8_t>((h >> (b * 8)) & 0xff);
                bands[b][key].push_back(idx);
            }
        }
        const int max_h = cfg.phash_hamming;
        for (auto& band : bands) {
            for (auto& [key, bucket] : band) {
                for (size_t a = 0; a < bucket.size(); ++a) {
                    for (size_t c = a + 1; c < bucket.size(); ++c) {
                        size_t i = bucket[a], j = bucket[c];
                        if (uf.find(i) == uf.find(j)) continue;
                        if (hamming64(records[i].phash, records[j].phash) <= max_h) {
                            uf.unite(i, j);
                            ++result.phash_pairs;
                        }
                    }
                }
            }
        }
    }

    // --- 3. Collect components of size > 1. ---
    std::unordered_map<size_t, std::vector<size_t>> comps;
    for (size_t i = 0; i < n; ++i) comps[uf.find(i)].push_back(i);
    for (auto& [root, members] : comps) {
        if (members.size() > 1) result.groups.push_back(std::move(members));
    }
    LOG_INFO("exact pass: " << result.groups.size() << " duplicate group(s) ("
                            << result.byte_identical_pairs << " byte-identical, "
                            << result.phash_pairs << " pHash re-save pair(s))");
    return result;
}

}  // namespace dedup
