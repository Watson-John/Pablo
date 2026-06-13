// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// thumb_cache.h — persistent on-disk thumbnail cache.
//
// Picasa-style "few big files": a single append-only pack file of
// premultiplied-BGRA blobs plus a compact index file (key -> offset/len/w/h),
// rather than one file per thumbnail. Decoded thumbnails survive across runs,
// so a warm cache serves from disk (a read + memcpy) instead of re-decoding.
//
// Thread-safe: a single mutex serializes all cache I/O. Keyed by a stable hash
// of (asset id, stage, source path + size + mtime) so edits to the source file
// transparently invalidate stale entries.

#pragma once

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <mutex>
#include <string>
#include <unordered_map>

#include "thumb/slot.h"  // FrameBuffer, FramePtr

namespace photo {

class ThumbCache {
public:
    explicit ThumbCache(std::filesystem::path dir);
    ~ThumbCache();

    ThumbCache(const ThumbCache&)            = delete;
    ThumbCache& operator=(const ThumbCache&) = delete;

    // True if the cache opened its backing files successfully. When false,
    // get() always misses and put() is a no-op (the engine still works,
    // just without persistence).
    bool ok() const { return ok_; }

    // Stable 64-bit key for (asset, stage, source-file identity). Incorporates
    // the file's size + mtime so a changed source produces a new key.
    static uint64_t key(uint64_t asset_id, uint32_t stage,
                        const std::string& path);

    // Returns the cached frame for `k`, or nullptr on miss / error.
    FramePtr get(uint64_t k);

    // Appends `frame` under `k`. No-op if the cache isn't ok or `k` is present.
    void put(uint64_t k, const FrameBuffer& frame);

    // Diagnostics.
    size_t entry_count();

private:
    struct Entry {
        uint64_t offset;  // byte offset into the pack file
        uint32_t len;     // blob length (== width*height*4)
        uint32_t width;
        uint32_t height;
    };

    bool load_index_locked();

    std::filesystem::path                dir_;
    std::mutex                           mu_;
    bool                                 ok_{false};
    std::FILE*                           pack_{nullptr};  // "r+b": append + read
    std::FILE*                           idx_{nullptr};   // "a+b": append records
    uint64_t                             pack_size_{0};
    std::unordered_map<uint64_t, Entry>  index_;
};

}  // namespace photo
