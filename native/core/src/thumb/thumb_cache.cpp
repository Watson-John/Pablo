// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "thumb/thumb_cache.h"

#include <cstring>
#include <system_error>

namespace photo {

namespace {

constexpr char     kPackMagic[8] = {'P', 'A', 'B', 'P', 'A', 'C', 'K', '1'};
constexpr char     kIdxMagic[8]  = {'P', 'A', 'B', 'I', 'D', 'X', '0', '1'};
constexpr uint64_t kHeaderSize   = 8;

// One on-disk index record (host byte order — a local, single-machine cache).
struct IdxRecord {
    uint64_t key;
    uint64_t offset;
    uint32_t len;
    uint32_t width;
    uint32_t height;
};

uint64_t fnv1a(const std::string& s) {
    uint64_t h = 0xcbf29ce484222325ULL;
    for (unsigned char c : s) {
        h ^= c;
        h *= 0x100000001b3ULL;
    }
    return h;
}

// Open `path` for read+write, creating it with `magic` if absent or if its
// header doesn't match (format reset). Returns an open FILE* or nullptr.
std::FILE* open_with_magic(const std::filesystem::path& path,
                           const char magic[8]) {
    std::FILE* f = std::fopen(path.string().c_str(), "r+b");
    if (f != nullptr) {
        char hdr[8] = {0};
        if (std::fread(hdr, 1, 8, f) == 8 && std::memcmp(hdr, magic, 8) == 0) {
            return f;  // valid existing file
        }
        std::fclose(f);  // bad/short header — recreate
    }
    f = std::fopen(path.string().c_str(), "w+b");
    if (f == nullptr) return nullptr;
    std::fwrite(magic, 1, 8, f);
    std::fflush(f);
    return f;
}

}  // namespace

ThumbCache::ThumbCache(std::filesystem::path dir) : dir_(std::move(dir)) {
    std::error_code ec;
    std::filesystem::create_directories(dir_, ec);

    pack_ = open_with_magic(dir_ / "thumbs.pack", kPackMagic);
    idx_  = open_with_magic(dir_ / "thumbs.idx", kIdxMagic);
    if (pack_ == nullptr || idx_ == nullptr) {
        if (pack_) { std::fclose(pack_); pack_ = nullptr; }
        if (idx_)  { std::fclose(idx_);  idx_ = nullptr; }
        return;
    }

    std::fseek(pack_, 0, SEEK_END);
    pack_size_ = static_cast<uint64_t>(std::ftell(pack_));
    if (pack_size_ < kHeaderSize) pack_size_ = kHeaderSize;

    std::lock_guard<std::mutex> lk(mu_);
    ok_ = load_index_locked();
}

ThumbCache::~ThumbCache() {
    if (pack_) std::fclose(pack_);
    if (idx_)  std::fclose(idx_);
}

bool ThumbCache::load_index_locked() {
    if (std::fseek(idx_, static_cast<long>(kHeaderSize), SEEK_SET) != 0) return false;
    IdxRecord rec;
    while (std::fread(&rec, sizeof(rec), 1, idx_) == 1) {
        // Drop entries whose blob would fall outside the current pack (a
        // partial/torn append): keeps a crash-truncated cache consistent.
        if (rec.offset + rec.len <= pack_size_ &&
            rec.len == rec.width * rec.height * 4u && rec.len > 0) {
            index_[rec.key] = Entry{rec.offset, rec.len, rec.width, rec.height};
        }
    }
    return true;
}

uint64_t ThumbCache::key(uint64_t asset_id, uint32_t stage,
                         const std::string& path) {
    std::string buf;
    buf.reserve(path.size() + 48);
    buf.append(reinterpret_cast<const char*>(&asset_id), sizeof(asset_id));
    buf.append(reinterpret_cast<const char*>(&stage), sizeof(stage));
    buf.append(path);

    std::error_code ec;
    auto sz = std::filesystem::file_size(path, ec);
    if (!ec) buf.append(reinterpret_cast<const char*>(&sz), sizeof(sz));
    auto mt = std::filesystem::last_write_time(path, ec);
    if (!ec) {
        auto t = mt.time_since_epoch().count();
        buf.append(reinterpret_cast<const char*>(&t), sizeof(t));
    }
    return fnv1a(buf);
}

FramePtr ThumbCache::get(uint64_t k) {
    std::lock_guard<std::mutex> lk(mu_);
    if (!ok_) return nullptr;
    auto it = index_.find(k);
    if (it == index_.end()) return nullptr;
    const Entry& e = it->second;

    auto fb = std::make_shared<FrameBuffer>();
    fb->width  = e.width;
    fb->height = e.height;
    fb->stride = e.width * 4;
    fb->bgra.resize(e.len);
    if (std::fseek(pack_, static_cast<long>(e.offset), SEEK_SET) != 0) return nullptr;
    if (std::fread(fb->bgra.data(), 1, e.len, pack_) != e.len) return nullptr;
    return fb;
}

void ThumbCache::put(uint64_t k, const FrameBuffer& frame) {
    const uint32_t len = frame.width * frame.height * 4u;
    if (len == 0 || frame.bgra.size() < len) return;

    std::lock_guard<std::mutex> lk(mu_);
    if (!ok_ || index_.count(k)) return;

    if (std::fseek(pack_, 0, SEEK_END) != 0) return;
    const uint64_t offset = static_cast<uint64_t>(std::ftell(pack_));
    if (std::fwrite(frame.bgra.data(), 1, len, pack_) != len) return;
    std::fflush(pack_);
    pack_size_ = offset + len;

    IdxRecord rec{k, offset, len, frame.width, frame.height};
    std::fseek(idx_, 0, SEEK_END);
    if (std::fwrite(&rec, sizeof(rec), 1, idx_) == 1) {
        std::fflush(idx_);
        index_[k] = Entry{offset, len, frame.width, frame.height};
    }
}

size_t ThumbCache::entry_count() {
    std::lock_guard<std::mutex> lk(mu_);
    return index_.size();
}

}  // namespace photo
