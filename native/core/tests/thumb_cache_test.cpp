// thumb_cache_test.cpp — disk-budget eviction + crash-safety for ThumbCache.
//
// Covers: budget enforcement, oldest-first eviction, byte-exact survivors,
// reopen correctness, torn-tail recovery, inline-key corruption never returning
// wrong bytes, simulated mid-eviction crash, over-budget no-op, dedup, and the
// hot-survives-FIFO promotion (RAM CLOCK second-chance).
//
// Note: the photo_core gtest suite is a standalone build (vcpkg/gtest); it is
// not run by the app CI, which only compiles thumb_cache.cpp into the plugin.

#include <gtest/gtest.h>

#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <string>

#include "thumb/thumb_cache.h"

namespace fs = std::filesystem;
using photo::FrameBuffer;
using photo::FramePtr;
using photo::ThumbCache;

namespace {

constexpr uint32_t kW = 8, kH = 8;           // 256-byte blob (+32 hdr = 288/rec)
constexpr uint64_t kBudget = 8 * 1024;        // 8 KiB -> forces eviction

uint8_t fill_for(uint64_t k) { return static_cast<uint8_t>(k % 251); }

FrameBuffer mkframe(uint32_t w, uint32_t h, uint8_t fill) {
    FrameBuffer fb;
    fb.width = w;
    fb.height = h;
    fb.stride = w * 4;
    fb.bgra.assign(static_cast<size_t>(w) * h * 4, fill);
    return fb;
}

bool blob_is(const FramePtr& f, uint32_t w, uint32_t h, uint8_t fill) {
    if (!f || f->width != w || f->height != h) return false;
    if (f->bgra.size() != static_cast<size_t>(w) * h * 4) return false;
    for (auto b : f->bgra) {
        if (b != fill) return false;
    }
    return true;
}

uint64_t disk_bytes(const fs::path& dir) {
    uint64_t s = 0;
    std::error_code ec;
    for (auto& e : fs::directory_iterator(dir, ec)) {
        const auto n = e.path().filename().string();
        if (n.rfind("seg-", 0) == 0 && n.size() > 4 &&
            n.substr(n.size() - 4) == ".pak") {
            s += static_cast<uint64_t>(fs::file_size(e.path(), ec));
        }
    }
    return s;
}

fs::path fresh_dir(const char* tag) {
    auto d = fs::temp_directory_path() / (std::string("pablo_evict_") + tag);
    std::error_code ec;
    fs::remove_all(d, ec);
    fs::create_directories(d, ec);
    return d;
}

}  // namespace

TEST(ThumbCacheEvict, BudgetHeldAndOldestEvicted) {
    auto dir = fresh_dir("budget");
    size_t max_segs = 0;
    {
        ThumbCache c(dir, kBudget);
        ASSERT_TRUE(c.ok());
        for (uint64_t k = 0; k < 200; ++k) {
            c.put(k, mkframe(kW, kH, fill_for(k)));
            max_segs = std::max(max_segs, c.segment_count());
            EXPECT_LE(c.total_bytes(), kBudget);
        }
        EXPECT_GE(max_segs, 2u);                 // eviction actually exercised
        EXPECT_LE(disk_bytes(dir), kBudget);
        EXPECT_EQ(c.get(0), nullptr);            // oldest cold key evicted
        for (uint64_t k = 195; k < 200; ++k) {
            EXPECT_TRUE(blob_is(c.get(k), kW, kH, fill_for(k)));
        }
    }
    {  // reopen
        ThumbCache c(dir, kBudget);
        ASSERT_TRUE(c.ok());
        EXPECT_LE(disk_bytes(dir), kBudget);
        EXPECT_EQ(c.get(0), nullptr);
        for (uint64_t k = 195; k < 200; ++k) {
            EXPECT_TRUE(blob_is(c.get(k), kW, kH, fill_for(k)));
        }
    }
}

TEST(ThumbCacheEvict, SingleBlobOverBudgetIsNoOp) {
    auto dir = fresh_dir("toobig");
    ThumbCache c(dir, 100);                       // < one 288-byte record
    c.put(42, mkframe(kW, kH, fill_for(42)));
    EXPECT_EQ(c.get(42), nullptr);
    EXPECT_EQ(c.entry_count(), 0u);
}

TEST(ThumbCacheEvict, DuplicatePutKeepsFirst) {
    auto dir = fresh_dir("dup");
    ThumbCache c(dir, kBudget);
    c.put(7, mkframe(kW, kH, 11));
    c.put(7, mkframe(kW, kH, 99));                // ignored
    EXPECT_TRUE(blob_is(c.get(7), kW, kH, 11));
}

TEST(ThumbCacheEvict, TornTailDroppedOnReopen) {
    auto dir = fresh_dir("torn");
    const uint64_t big = 1024 * 1024;            // no eviction
    {
        ThumbCache c(dir, big);
        for (uint64_t k = 0; k < 5; ++k) c.put(k, mkframe(kW, kH, fill_for(k)));
    }
    {  // append a partial (12-byte) header to the active segment
        auto p = dir / "seg-000000000000.pak";
        std::FILE* f = std::fopen(p.string().c_str(), "ab");
        ASSERT_NE(f, nullptr);
        unsigned char junk[12];
        for (auto& b : junk) b = 0xAB;
        std::fwrite(junk, 1, sizeof(junk), f);
        std::fclose(f);
    }
    {
        ThumbCache c(dir, big);
        ASSERT_TRUE(c.ok());
        for (uint64_t k = 0; k < 5; ++k) {
            EXPECT_TRUE(blob_is(c.get(k), kW, kH, fill_for(k)));
        }
        c.put(999, mkframe(kW, kH, fill_for(999)));   // append still works
        EXPECT_TRUE(blob_is(c.get(999), kW, kH, fill_for(999)));
    }
}

TEST(ThumbCacheEvict, CorruptedKeyNeverReturnsWrongBytes) {
    auto dir = fresh_dir("corrupt");
    const uint64_t big = 1024 * 1024;
    {
        ThumbCache c(dir, big);
        for (uint64_t k = 10; k < 13; ++k) c.put(k, mkframe(kW, kH, fill_for(k)));
    }
    {  // overwrite the first record's inline key (at offset 8)
        auto p = dir / "seg-000000000000.pak";
        std::FILE* f = std::fopen(p.string().c_str(), "r+b");
        ASSERT_NE(f, nullptr);
        std::fseek(f, 8, SEEK_SET);
        uint64_t bogus = 0xDEADBEEFCAFEull;
        std::fwrite(&bogus, sizeof(bogus), 1, f);
        std::fclose(f);
    }
    {
        ThumbCache c(dir, big);
        ASSERT_TRUE(c.ok());
        EXPECT_EQ(c.get(10), nullptr);            // original key now misses
        auto bf = c.get(0xDEADBEEFCAFEull);       // bogus key -> only its own bytes
        if (bf) EXPECT_TRUE(blob_is(bf, kW, kH, fill_for(10)));
        EXPECT_TRUE(blob_is(c.get(11), kW, kH, fill_for(11)));
        EXPECT_TRUE(blob_is(c.get(12), kW, kH, fill_for(12)));
    }
}

TEST(ThumbCacheEvict, SurvivesMidEvictionCrash) {
    auto dir = fresh_dir("crash");
    {
        ThumbCache c(dir, kBudget);
        for (uint64_t k = 0; k < 200; ++k) c.put(k, mkframe(kW, kH, fill_for(k)));
    }
    {  // out-of-band remove the lowest-id surviving segment (crash mid-drop)
        std::error_code ec;
        uint64_t lowest = UINT64_MAX;
        fs::path lp;
        for (auto& e : fs::directory_iterator(dir, ec)) {
            const auto n = e.path().filename().string();
            if (n.rfind("seg-", 0) == 0 && n.substr(n.size() - 4) == ".pak") {
                uint64_t id = std::stoull(n.substr(4, n.size() - 8));
                if (id < lowest) {
                    lowest = id;
                    lp = e.path();
                }
            }
        }
        if (!lp.empty()) fs::remove(lp, ec);
    }
    {
        ThumbCache c(dir, kBudget);
        ASSERT_TRUE(c.ok());
        EXPECT_LE(disk_bytes(dir), kBudget);
        for (uint64_t k = 190; k < 200; ++k) {
            auto f = c.get(k);
            if (f) EXPECT_TRUE(blob_is(f, kW, kH, fill_for(k)));  // never garbage
        }
    }
}

TEST(ThumbCacheEvict, OverflowingDimensionsRejected) {
    auto dir = fresh_dir("overflow");
    ThumbCache c(dir, 1024 * 1024);
    FrameBuffer fb;
    fb.width = 100000;       // width*height*4 = 4e10, wraps uint32_t
    fb.height = 100000;
    fb.stride = 0;
    fb.bgra.assign(64, 0xCD);  // deliberately tiny backing buffer
    c.put(5, fb);
    EXPECT_EQ(c.get(5), nullptr);
    EXPECT_EQ(c.entry_count(), 0u);
}

TEST(ThumbCacheEvict, HotKeySurvivesColdEvicted) {
    auto dir = fresh_dir("lru");
    ThumbCache c(dir, kBudget);
    c.put(0, mkframe(kW, kH, fill_for(0)));       // hot anchor
    c.put(1, mkframe(kW, kH, fill_for(1)));       // cold anchor
    for (uint64_t k = 100; k < 300; ++k) {
        (void)c.get(0);                            // keep key 0 recently-used
        c.put(k, mkframe(kW, kH, fill_for(k)));
    }
    EXPECT_TRUE(blob_is(c.get(0), kW, kH, fill_for(0)));  // promoted, survived
    EXPECT_EQ(c.get(1), nullptr);                          // cold, evicted
}
