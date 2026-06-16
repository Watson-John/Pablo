// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "thumb/thumb_cache.h"

#include <algorithm>
#include <cstring>
#include <memory>
#include <system_error>
#include <utility>
#include <vector>

#ifdef PHOTO_HAVE_VIPS
#include <mutex>
#include <vips/vips.h>
#endif

namespace photo {

namespace {

// New magic for the rotating-segment format. Any pre-existing PABPACK1/PABIDX01
// files from the prior single-pack format are foreign and ignored — a one-time
// cold start (the cache is regenerable). See docs/DECISIONS.md.
constexpr char     kSegMagic[8] = {'P', 'A', 'B', 'S', 'E', 'G', '0', '2'};
constexpr uint64_t kHeaderSize  = 8;
constexpr uint8_t  kFlagLive    = 0x1;  // bit0: record is live (else a tombstone)
constexpr uint8_t  kFlagJpeg    = 0x2;  // bit1: stored blob is JPEG (else raw BGRA)
[[maybe_unused]] constexpr uint8_t kFlagDead = 0;  // documents the format
constexpr uint8_t  kFmtRaw      = 0;    // Entry.format: raw premultiplied BGRA
constexpr uint8_t  kFmtJpeg     = 1;    // Entry.format: JPEG
constexpr uint64_t kMiB         = 1024ull * 1024ull;

#ifdef PHOTO_HAVE_VIPS
// JPEG quality for cached thumbnails — visually lossless at thumbnail sizes,
// ~10x smaller on disk than raw BGRA so far more thumbs fit the disk budget.
constexpr int kJpegQuality = 85;
#endif

// Hard ceiling on a single blob. Real thumbnails are <= ~16 MiB (the 2048px
// FULL stage); this generous bound rejects absurd inputs, keeps blob length
// within uint32_t, and — together with the <=256 MiB segment cap — guarantees
// every in-segment offset stays well under LONG_MAX, so the std::fseek(long)
// casts are safe on 32-bit / MSVC builds without platform-specific seeks.
constexpr uint64_t kMaxBlobBytes = 64ull * kMiB;

// File handle that closes on scope exit unless released into the segment map —
// prevents leaking an fopen'd segment if a subsequent map insert throws.
using FilePtr = std::unique_ptr<std::FILE, int (*)(std::FILE*)>;

// Promote-at-seal migrates recently-used entries out of the next-to-die segment
// so they outlive pure FIFO. Disable for deterministic FIFO behavior in tests.
constexpr bool     kEnablePromotion = true;

// Per-blob record header, written inline before each blob. Fixed 32 bytes, host
// byte order (a local single-machine cache, same policy as the prior IdxRecord).
struct RecHeader {
    uint64_t key;
    uint32_t len;       // == width*height*4, > 0
    uint32_t width;
    uint32_t height;
    uint8_t  flags;     // kFlagLive / kFlagDead
    uint8_t  pad[3];    // reserved 0
    uint32_t crc;       // reserved 0 (room for a future blob integrity check)
    uint32_t reserved;  // pad to 32 bytes
};
static_assert(sizeof(RecHeader) == 32, "RecHeader must be exactly 32 bytes");

uint64_t fnv1a(const std::string& s) {
    uint64_t h = 0xcbf29ce484222325ULL;
    for (unsigned char c : s) {
        h ^= c;
        h *= 0x100000001b3ULL;
    }
    return h;
}

#ifdef PHOTO_HAVE_VIPS
bool ensure_vips_cache() {
    static std::once_flag once;
    static bool ok = false;
    std::call_once(once, [] { ok = (VIPS_INIT("pablo-cache") == 0); });
    return ok;
}

// Encode a premultiplied-BGRA frame to JPEG bytes. Thumbnails are opaque
// (alpha 255), so dropping alpha is lossless; JPEG itself is visually lossless
// at kJpegQuality but ~10x smaller than raw. Returns empty on failure.
std::vector<uint8_t> encode_jpeg(const FrameBuffer& fb) {
    std::vector<uint8_t> out;
    if (!ensure_vips_cache() || fb.width == 0 || fb.height == 0) return out;
    const size_t px = static_cast<size_t>(fb.width) * fb.height;
    if (fb.bgra.size() < px * 4) return out;
    std::vector<uint8_t> rgb(px * 3);
    const uint8_t* s = fb.bgra.data();
    for (size_t i = 0; i < px; ++i) {
        rgb[i * 3 + 0] = s[i * 4 + 2];  // R
        rgb[i * 3 + 1] = s[i * 4 + 1];  // G
        rgb[i * 3 + 2] = s[i * 4 + 0];  // B
    }
    // new_from_memory does NOT copy; rgb must outlive img (it does — unref below).
    VipsImage* img = vips_image_new_from_memory(
        rgb.data(), rgb.size(),
        static_cast<int>(fb.width), static_cast<int>(fb.height), 3,
        VIPS_FORMAT_UCHAR);
    if (img == nullptr) return out;
    void* buf = nullptr;
    size_t len = 0;
    const int rc = vips_jpegsave_buffer(img, &buf, &len, "Q", kJpegQuality, NULL);
    g_object_unref(img);
    if (rc != 0 || buf == nullptr) {
        if (buf != nullptr) g_free(buf);
        vips_error_clear();
        return out;
    }
    out.assign(static_cast<uint8_t*>(buf), static_cast<uint8_t*>(buf) + len);
    g_free(buf);
    return out;
}

// Decode JPEG bytes back to a premultiplied-BGRA frame. `data` must stay valid
// for the duration of this call.
FramePtr decode_jpeg(const uint8_t* data, size_t len) {
    if (!ensure_vips_cache()) return nullptr;
    VipsImage* img = nullptr;
    if (vips_jpegload_buffer(const_cast<uint8_t*>(data), len, &img, NULL) != 0 ||
        img == nullptr) {
        vips_error_clear();
        return nullptr;
    }
    VipsImage* srgb = nullptr;
    if (vips_colourspace(img, &srgb, VIPS_INTERPRETATION_sRGB, NULL) != 0) {
        g_object_unref(img);
        vips_error_clear();
        return nullptr;
    }
    g_object_unref(img);
    const int w = vips_image_get_width(srgb);
    const int h = vips_image_get_height(srgb);
    const int bands = vips_image_get_bands(srgb);
    size_t n = 0;
    auto* mem = static_cast<uint8_t*>(vips_image_write_to_memory(srgb, &n));
    g_object_unref(srgb);
    if (mem == nullptr || w <= 0 || h <= 0 || bands < 3) {
        if (mem != nullptr) g_free(mem);
        return nullptr;
    }
    auto fb = std::make_shared<FrameBuffer>();
    fb->width = static_cast<uint32_t>(w);
    fb->height = static_cast<uint32_t>(h);
    fb->stride = fb->width * 4;
    fb->bgra.resize(static_cast<size_t>(fb->stride) * fb->height);
    const size_t px = static_cast<size_t>(w) * h;
    uint8_t* d = fb->bgra.data();
    for (size_t i = 0; i < px; ++i) {
        d[i * 4 + 0] = mem[i * bands + 2];  // B
        d[i * 4 + 1] = mem[i * bands + 1];  // G
        d[i * 4 + 2] = mem[i * bands + 0];  // R
        d[i * 4 + 3] = 255;
    }
    g_free(mem);
    return fb;
}
#endif  // PHOTO_HAVE_VIPS

}  // namespace

ThumbCache::ThumbCache(std::filesystem::path dir, uint64_t disk_budget_bytes)
    : dir_(std::move(dir)), budget_(disk_budget_bytes) {
    std::error_code ec;
    std::filesystem::create_directories(dir_, ec);

    // Per-segment soft cap derived from the budget. Default regime: budget/64
    // clamped to [1 MiB, 256 MiB] so a single drop touches a bounded number of
    // index entries. Tiny-budget (test) regime: the 1 MiB floor can exceed the
    // whole budget, leaving a lone segment that never evicts — so when the cap
    // would be at least half the budget, fall back to budget/4 (>= 4 segments).
    uint64_t cap = budget_ / 64;
    if (cap < 1 * kMiB) cap = 1 * kMiB;
    if (cap > 256 * kMiB) cap = 256 * kMiB;
    if (cap * 2 > budget_) cap = budget_ / 4;
    if (cap < sizeof(RecHeader) + 4) cap = sizeof(RecHeader) + 4;
    segment_cap_ = cap;

    std::lock_guard<std::mutex> lk(mu_);
    try {
        discover_segments_locked();
    } catch (...) {
        // Leave ok_ false; the engine runs without persistence.
    }
}

ThumbCache::~ThumbCache() {
    for (auto& [id, sm] : segs_) {
        if (sm.fp) std::fclose(sm.fp);
    }
}

std::filesystem::path ThumbCache::seg_path(uint64_t id) const {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "seg-%012llu.pak",
                  static_cast<unsigned long long>(id));
    return dir_ / buf;
}

std::FILE* ThumbCache::create_segment_file_locked(uint64_t id) {
    std::FILE* f = std::fopen(seg_path(id).string().c_str(), "w+b");
    if (f == nullptr) return nullptr;
    if (std::fwrite(kSegMagic, 1, kHeaderSize, f) != kHeaderSize) {
        std::fclose(f);
        return nullptr;
    }
    std::fflush(f);
    return f;
}

void ThumbCache::discover_segments_locked() {
    std::error_code ec;

    // Gather existing seg-*.pak files, sorted by ascending id.
    std::vector<std::pair<uint64_t, std::filesystem::path>> found;
    for (std::filesystem::directory_iterator it(dir_, ec), end;
         !ec && it != end; it.increment(ec)) {
        const auto& p = it->path();
        std::error_code fec;
        if (!std::filesystem::is_regular_file(p, fec)) continue;
        const std::string name = p.filename().string();
        if (name.size() > 8 && name.compare(0, 4, "seg-") == 0 &&
            name.compare(name.size() - 4, 4, ".pak") == 0) {
            const std::string mid = name.substr(4, name.size() - 8);
            try {
                found.emplace_back(std::stoull(mid), p);
            } catch (...) {
                // Not a parseable id — ignore.
            }
        }
    }
    std::sort(found.begin(), found.end(),
              [](const auto& a, const auto& b) { return a.first < b.first; });

    // Open + scan each in ascending order. Ascending-id, ascending-offset scan
    // makes the NEWEST live copy of a key win (last-write-wins), resolving
    // promotion / crash duplicates deterministically.
    for (const auto& [id, p] : found) {
        std::FILE* f = std::fopen(p.string().c_str(), "r+b");
        if (f == nullptr) continue;
        char hdr[8] = {0};
        if (std::fread(hdr, 1, 8, f) != 8 ||
            std::memcmp(hdr, kSegMagic, 8) != 0) {
            std::fclose(f);  // foreign/corrupt header — leave the file, skip it
            continue;
        }
        std::error_code sec;
        uint64_t on_disk =
            static_cast<uint64_t>(std::filesystem::file_size(p, sec));
        if (sec) on_disk = 0;

        FilePtr holder(f, &std::fclose);
        auto res = segs_.emplace(id, SegMeta{holder.get(), kHeaderSize, {}});
        holder.release();  // map owns the handle now
        SegMeta& sm = res.first->second;
        sm.size = scan_segment_locked(id, f, on_disk, sm.keys);
        total_bytes_ += sm.size;
    }

    if (segs_.empty()) {
        std::FILE* f = create_segment_file_locked(0);
        if (f == nullptr) return;  // ok_ stays false
        FilePtr holder(f, &std::fclose);
        segs_.emplace(0, SegMeta{holder.get(), kHeaderSize, {}});
        holder.release();
        total_bytes_ += kHeaderSize;
    }

    active_seg_id_ = segs_.rbegin()->first;

    // Truncate any torn tail of the active segment so the next append is
    // contiguous (a crash mid-append leaves trailing bytes past the last valid
    // record; appending after them would orphan everything written next).
    auto ait = segs_.find(active_seg_id_);
    std::error_code rec;
    uint64_t fsz =
        static_cast<uint64_t>(std::filesystem::file_size(seg_path(active_seg_id_), rec));
    if (!rec && fsz > ait->second.size) {
        std::filesystem::resize_file(seg_path(active_seg_id_), ait->second.size, rec);
    }

    ok_ = true;
}

uint64_t ThumbCache::scan_segment_locked(uint64_t seg_id, std::FILE* fp,
                                         uint64_t on_disk_size,
                                         std::vector<uint64_t>& keys) {
    uint64_t off = kHeaderSize;
    if (std::fseek(fp, static_cast<long>(off), SEEK_SET) != 0) return kHeaderSize;

    for (;;) {
        RecHeader h;
        if (std::fread(&h, sizeof(h), 1, fp) != 1) break;  // torn/EOF header
        // Validate the record. On any inconsistency STOP scanning this segment:
        // in a self-describing log the next record's position depends on this
        // record's len, so a torn record makes everything after it unreadable.
        // Raw size from the dims (u64 so a garbage width*height can't wrap).
        // For raw blobs len must equal it exactly; for JPEG it must be smaller.
        const uint64_t rawSize =
            static_cast<uint64_t>(h.width) * h.height * 4ull;
        const bool isJpeg = (h.flags & kFlagJpeg) != 0;
        if (h.len == 0 || rawSize == 0 || rawSize > kMaxBlobBytes) break;
        if (isJpeg ? (h.len > rawSize) : (h.len != rawSize)) break;
        const uint64_t blob_off = off + sizeof(RecHeader);
        if (blob_off + h.len > on_disk_size) break;  // torn/partial blob

        if ((h.flags & kFlagLive) != 0) {
            index_[h.key] = Entry{seg_id, blob_off, h.len, h.width, h.height,
                                  isJpeg ? kFmtJpeg : kFmtRaw, 0};
            keys.push_back(h.key);
        } else {  // tombstone — treat as absent
            index_.erase(h.key);
        }

        off = blob_off + h.len;
        if (std::fseek(fp, static_cast<long>(off), SEEK_SET) != 0) break;
    }
    return off;  // end of the last fully-valid record (== authoritative size)
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
    it->second.clock = 1;  // RAM-only recency mark (no disk write on read path)
    const Entry e = it->second;

    auto sit = segs_.find(e.seg_id);
    if (sit == segs_.end()) return nullptr;  // index/segment desync — miss

    std::vector<uint8_t> blob(e.len);
    if (std::fseek(sit->second.fp, static_cast<long>(e.blob_offset), SEEK_SET) != 0) {
        return nullptr;
    }
    if (std::fread(blob.data(), 1, e.len, sit->second.fp) != e.len) {
        return nullptr;
    }

    if (e.format == kFmtJpeg) {
#ifdef PHOTO_HAVE_VIPS
        return decode_jpeg(blob.data(), e.len);  // null on decode failure -> miss
#else
        return nullptr;  // JPEG blob but no decoder in this build
#endif
    }

    // Raw premultiplied BGRA — the bytes are the frame.
    auto fb = std::make_shared<FrameBuffer>();
    fb->width  = e.width;
    fb->height = e.height;
    fb->stride = e.width * 4;
    fb->bgra = std::move(blob);
    return fb;
}

bool ThumbCache::append_raw_locked(uint64_t seg_id, uint64_t k,
                                   const uint8_t* data, uint32_t len,
                                   uint32_t width, uint32_t height,
                                   uint8_t format) {
    auto sit = segs_.find(seg_id);
    if (sit == segs_.end()) return false;
    SegMeta& sm = sit->second;

    const uint64_t off = sm.size;
    if (std::fseek(sm.fp, static_cast<long>(off), SEEK_SET) != 0) return false;

    RecHeader h{};
    h.key    = k;
    h.len    = len;
    h.width  = width;
    h.height = height;
    h.flags  = static_cast<uint8_t>(
        kFlagLive | (format == kFmtJpeg ? kFlagJpeg : 0));
    if (std::fwrite(&h, sizeof(h), 1, sm.fp) != 1) return false;
    std::fflush(sm.fp);  // header durable before the blob — clean torn boundary
    if (len > 0 && std::fwrite(data, 1, len, sm.fp) != len) return false;
    std::fflush(sm.fp);

    const uint64_t needed = sizeof(RecHeader) + len;
    sm.size += needed;
    sm.keys.push_back(k);
    total_bytes_ += needed;
    index_[k] = Entry{seg_id, off + sizeof(RecHeader), len,
                      width, height, format, 0};
    return true;
}

void ThumbCache::roll_active_segment_locked() {
    const uint64_t new_id = active_seg_id_ + 1;
    std::FILE* f = create_segment_file_locked(new_id);
    if (f == nullptr) return;  // can't roll; keep using current (may exceed cap)
    FilePtr holder(f, &std::fclose);
    segs_.emplace(new_id, SegMeta{holder.get(), kHeaderSize, {}});
    holder.release();
    total_bytes_ += kHeaderSize;
    active_seg_id_ = new_id;
}

void ThumbCache::promote_from_locked(uint64_t victim_seg_id) {
    auto vit = segs_.find(victim_seg_id);
    if (vit == segs_.end()) return;

    // Bound write amplification (and active-segment growth): re-append at most
    // a quarter-segment of hot blobs per drop. The active segment may briefly
    // exceed segment_cap_ by this much; the next put() rolls it. We deliberately
    // do NOT skip a hot entry when the active is near-full: that would leave its
    // index pointing at the victim and silently evict it on the drop below.
    const uint64_t budget_bytes = segment_cap_ / 4;
    uint64_t used = 0;

    // Snapshot the victim's keys; append_record_locked mutates index_ and the
    // active segment's keys, never this victim's, so iterating is safe.
    const std::vector<uint64_t> keys = vit->second.keys;
    for (uint64_t k : keys) {
        if (used >= budget_bytes) break;
        auto e = index_.find(k);
        if (e == index_.end()) continue;
        if (e->second.seg_id != victim_seg_id) continue;  // already moved
        if (e->second.clock == 0) continue;               // cold — let it die

        const Entry src = e->second;
        // Copy the STORED bytes verbatim (a JPEG stays JPEG — no re-encode).
        std::vector<uint8_t> blob(src.len);
        if (std::fseek(vit->second.fp, static_cast<long>(src.blob_offset),
                       SEEK_SET) != 0) {
            continue;
        }
        if (std::fread(blob.data(), 1, src.len, vit->second.fp) != src.len) {
            continue;
        }
        if (append_raw_locked(active_seg_id_, k, blob.data(), src.len,
                              src.width, src.height, src.format)) {
            used += sizeof(RecHeader) + src.len;
        }
    }
}

void ThumbCache::enforce_budget_locked() {
    while (total_bytes_ > budget_ && segs_.size() > 1) {
        auto oldest = segs_.begin();
        if (oldest->first == active_seg_id_) break;  // never drop the active one
        drop_oldest_segment_locked(oldest);
    }
}

void ThumbCache::drop_oldest_segment_locked(
        std::map<uint64_t, SegMeta>::iterator it) {
    const uint64_t seg_id = it->first;
    // Second-chance: migrate this segment's recently-used (hot) entries into the
    // active segment BEFORE dropping it, so hot data outlives FIFO. Cold entries
    // die with the segment. Promotion copies < the segment's bytes, so the net
    // effect of this drop still reduces total_bytes_.
    if (kEnablePromotion && seg_id != active_seg_id_) promote_from_locked(seg_id);
    for (uint64_t k : it->second.keys) {
        auto e = index_.find(k);
        // Erase only if the LIVE copy is still in THIS segment; a promoted/
        // re-put copy living in a younger segment must survive.
        if (e != index_.end() && e->second.seg_id == seg_id) index_.erase(e);
    }
    total_bytes_ -= it->second.size;
    if (it->second.fp) std::fclose(it->second.fp);
    std::error_code ec;
    std::filesystem::remove(seg_path(seg_id), ec);
    segs_.erase(it);
}

void ThumbCache::put(uint64_t k, const FrameBuffer& frame) {
    // Raw size in u64 so width*height*4 can't overflow uint32_t and wrap to a
    // small value. Bounds the dims (and thus in-segment offsets) regardless of
    // the smaller stored (encoded) size.
    const uint64_t rawLen =
        static_cast<uint64_t>(frame.width) * frame.height * 4ull;
    if (rawLen == 0 || rawLen > kMaxBlobBytes || frame.bgra.size() < rawLen) {
        return;
    }

    std::lock_guard<std::mutex> lk(mu_);
    if (!ok_ || index_.count(k)) return;

    // Prefer a JPEG-encoded blob (≈10x smaller) when libvips is available so
    // far more thumbnails fit the disk budget; fall back to raw BGRA otherwise.
    const uint8_t* data = frame.bgra.data();
    uint32_t storeLen = static_cast<uint32_t>(rawLen);
    uint8_t format = kFmtRaw;
#ifdef PHOTO_HAVE_VIPS
    std::vector<uint8_t> jpeg = encode_jpeg(frame);
    if (!jpeg.empty() && jpeg.size() < rawLen) {
        data = jpeg.data();  // valid until this function returns (append copies)
        storeLen = static_cast<uint32_t>(jpeg.size());
        format = kFmtJpeg;
    }
#endif

    const uint64_t needed = sizeof(RecHeader) + storeLen;
    if (needed > budget_) return;  // a single blob can't fit the budget — no-op

    // Roll to a new segment if this record won't fit the active one (but always
    // accept into a fresh/empty segment so an over-cap-but-under-budget blob
    // still lands somewhere).
    auto ait = segs_.find(active_seg_id_);
    if (ait != segs_.end() && ait->second.size > kHeaderSize &&
        ait->second.size + needed > segment_cap_) {
        roll_active_segment_locked();
    }

    append_raw_locked(active_seg_id_, k, data, storeLen,
                      frame.width, frame.height, format);
    enforce_budget_locked();
}

size_t ThumbCache::entry_count() {
    std::lock_guard<std::mutex> lk(mu_);
    return index_.size();
}

size_t ThumbCache::segment_count() {
    std::lock_guard<std::mutex> lk(mu_);
    return segs_.size();
}

uint64_t ThumbCache::total_bytes() {
    std::lock_guard<std::mutex> lk(mu_);
    return total_bytes_;
}

}  // namespace photo
