// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// thumb_cache.h — persistent on-disk thumbnail cache with disk-budget eviction.
//
// Picasa-style "few big files", now as ROTATING SEGMENTS: the cache is a set of
// bounded, self-describing segment files (seg-<id>.pak). Each segment is an
// append-only log of [RecHeader][blob] pairs — the per-blob metadata (key, len,
// w, h) lives INLINE next to its bytes, so every segment validates standalone
// and the in-RAM index is rebuilt by scanning segments at open. There is NO
// separate index file (its absence is what removes the dangling-pointer /
// half-renamed-pair hazard a single pack+idx pair would have under eviction).
//
// Eviction enforces a disk budget by deleting the OLDEST whole segment file:
// O(1) physical reclaim, a whole-file atomic crash unit, and no compaction pass
// (so the lock is never held for a multi-GB rewrite). LRU is approximated by a
// RAM-only CLOCK bit set on get() plus promote-at-seal (hot entries from the
// next-to-die segment are re-appended forward when a segment is sealed).
//
// Crash-safety: a crash at any point re-opens to either the prior cache or a
// colder (smaller) one — never corruption, and never wrong bytes for a key,
// because offsets are absolute within a self-describing segment and the key is
// validated from the same bytes the index is rebuilt from.
//
// Thread-safe: a single mutex serializes all cache I/O. Keyed by a stable hash
// of (asset id, stage, source path + size + mtime) so edits to the source file
// transparently invalidate stale entries.

#pragma once

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <map>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "thumb/slot.h"  // FrameBuffer, FramePtr

namespace photo {

class ThumbCache {
public:
    // `disk_budget_bytes` is the high-water mark on the sum of segment file
    // sizes. When exceeded after a put, the oldest segment(s) are dropped.
    ThumbCache(std::filesystem::path dir, uint64_t disk_budget_bytes);
    ~ThumbCache();

    ThumbCache(const ThumbCache&)            = delete;
    ThumbCache& operator=(const ThumbCache&) = delete;

    // True if the cache opened/created its segment directory successfully. When
    // false, get() always misses and put() is a no-op (engine still works).
    bool ok() const { return ok_; }

    // Stable 64-bit key for (asset, stage, source-file identity). Incorporates
    // the file's size + mtime so a changed source produces a new key.
    static uint64_t key(uint64_t asset_id, uint32_t stage,
                        const std::string& path);

    // Returns the cached frame for `k`, or nullptr on miss / error.
    FramePtr get(uint64_t k);

    // Appends `frame` under `k`. No-op if the cache isn't ok, `k` is present, or
    // the blob alone would exceed the disk budget. May trigger eviction.
    void put(uint64_t k, const FrameBuffer& frame);

    // Diagnostics.
    size_t entry_count();
    size_t segment_count();
    uint64_t total_bytes();

private:
    struct Entry {
        uint64_t seg_id;       // which segment holds the live copy
        uint64_t blob_offset;  // byte offset of the stored blob (past RecHeader)
        uint32_t len;          // STORED blob length (raw = w*h*4; JPEG = file size)
        uint32_t width;
        uint32_t height;
        uint8_t  format;       // 0 = raw premultiplied BGRA, 1 = JPEG
        uint8_t  clock;        // RAM-only LRU/CLOCK recency bit (1 = recent)
    };

    struct SegMeta {
        std::FILE*            fp;    // open r+b handle
        uint64_t              size;  // authoritative end-of-data (== file size)
        std::vector<uint64_t> keys;  // keys ever written here (drop scans this)
    };

    // All *_locked helpers require mu_ held.
    void     discover_segments_locked();
    uint64_t scan_segment_locked(uint64_t seg_id, std::FILE* fp,
                                 uint64_t on_disk_size,
                                 std::vector<uint64_t>& keys);
    std::FILE* create_segment_file_locked(uint64_t id);
    // Low-level: write [RecHeader][data] verbatim. Used by put() (after any
    // encode) and by promotion (verbatim copy, preserving format).
    bool     append_raw_locked(uint64_t seg_id, uint64_t k,
                               const uint8_t* data, uint32_t len,
                               uint32_t width, uint32_t height, uint8_t format);
    void     roll_active_segment_locked();
    void     promote_from_locked(uint64_t victim_seg_id);
    void     enforce_budget_locked();
    void     drop_oldest_segment_locked(
                 std::map<uint64_t, SegMeta>::iterator it);
    std::filesystem::path seg_path(uint64_t id) const;

    std::filesystem::path                dir_;
    std::mutex                           mu_;
    bool                                 ok_{false};
    uint64_t                             budget_{0};
    uint64_t                             total_bytes_{0};  // sum of seg sizes
    uint64_t                             segment_cap_{0};  // per-segment soft cap
    uint64_t                             active_seg_id_{0};
    std::map<uint64_t, SegMeta>          segs_;   // ordered: begin()=oldest
    std::unordered_map<uint64_t, Entry>  index_;
};

}  // namespace photo
