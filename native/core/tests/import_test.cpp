// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// import_test.cpp — exercises photo_import_path / photo_rescan end to end
// through the internal Engine: a real async job walks a temp tree, upserts the
// catalog, and emits IMPORT_COMPLETE. Verifies recursion, the image-extension
// filter, rescan add/prune, and — the whole point of the catalog — that an
// asset_id is STABLE across an engine restart (unlike the old path hash).

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <chrono>
#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <thread>

#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::Engine;

namespace {

fs::path make_tree(const char* tag) {
    auto root = fs::temp_directory_path() / ("photo_import_test_" + std::string(tag));
    fs::remove_all(root);
    fs::create_directories(root);
    return root;
}

void write_file(const fs::path& p, const char* bytes = "x") {
    fs::create_directories(p.parent_path());
    std::ofstream(p, std::ios::binary) << bytes;
}

std::unique_ptr<Engine> make_engine(const fs::path& dir) {
    auto cat = (dir / "pablo.db").string();
    auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return Engine::create(cfg);
}

// Drain the engine's event ring until the given import request completes.
bool wait_for_import(Engine& eng, uint64_t req, int timeout_ms = 8000) {
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[64];
    while (steady_clock::now() < deadline) {
        size_t n = eng.events().pop_n(buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE && buf[i].request_id == req)
                return buf[i].status == PHOTO_STATUS_OK;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return false;
}

// Like wait_for_import but returns the COMPLETE event itself, so callers can
// read the packed incremental-rescan counts (added/updated/skipped/removed).
// status is left -1 on timeout.
photo_event_t wait_for_import_event(Engine& eng, uint64_t req,
                                    int timeout_ms = 8000) {
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[64];
    while (steady_clock::now() < deadline) {
        size_t n = eng.events().pop_n(buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE && buf[i].request_id == req)
                return buf[i];
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    photo_event_t miss{};
    miss.status = -1;
    return miss;
}

bool has_path(const std::vector<photo::catalog::AssetRecord>& v, const fs::path& p) {
    for (const auto& a : v) if (a.path == p.string()) return true;
    return false;
}

}  // namespace

TEST(Import, RecursiveSkipsNonImages) {
    auto dir = make_tree("basic");
    write_file(dir / "a.jpg");
    write_file(dir / "b.PNG");          // case-insensitive extension
    write_file(dir / "note.txt");       // excluded
    write_file(dir / "sub" / "c.jpeg"); // recursion

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const uint64_t req = eng->import_path((dir).string());
    ASSERT_NE(req, 0u);
    ASSERT_TRUE(wait_for_import(*eng, req));

    auto assets = eng->list_assets();
    EXPECT_EQ(assets.size(), 3u);
    EXPECT_TRUE(has_path(assets, dir / "a.jpg"));
    EXPECT_TRUE(has_path(assets, dir / "b.PNG"));
    EXPECT_TRUE(has_path(assets, dir / "sub" / "c.jpeg"));
    EXPECT_FALSE(has_path(assets, dir / "note.txt"));
}

TEST(Import, RescanAddsAndPrunes) {
    auto dir = make_tree("rescan");
    write_file(dir / "keep.jpg");
    write_file(dir / "remove.jpg");

    auto eng = make_engine(dir);
    ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));
    EXPECT_EQ(eng->list_assets().size(), 2u);

    fs::remove(dir / "remove.jpg");
    write_file(dir / "added.png");

    ASSERT_TRUE(wait_for_import(*eng, eng->rescan()));
    auto assets = eng->list_assets();
    EXPECT_EQ(assets.size(), 2u);
    EXPECT_TRUE(has_path(assets, dir / "keep.jpg"));
    EXPECT_TRUE(has_path(assets, dir / "added.png"));
    EXPECT_FALSE(has_path(assets, dir / "remove.jpg"));
}

TEST(Import, IdempotentReimportNoDuplicates) {
    auto dir = make_tree("idem");
    write_file(dir / "a.jpg");

    auto eng = make_engine(dir);
    ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));
    ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));
    EXPECT_EQ(eng->list_assets().size(), 1u);
}

TEST(Import, RescanSkipsUnchanged) {
    auto dir = make_tree("incremental");
    write_file(dir / "a.jpg");
    write_file(dir / "b.jpg");
    write_file(dir / "sub" / "c.png");

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    // First import: all three files are new.
    auto first = wait_for_import_event(*eng, eng->import_path(dir.string()));
    ASSERT_EQ(first.status, PHOTO_STATUS_OK);
    EXPECT_EQ(first.aux64, 3u);          // added
    EXPECT_EQ(first.aux64_b, 0u);        // updated
    EXPECT_EQ(first._reserved[0], 0u);   // skipped

    // Rescan with nothing changed: every file is skipped (no re-extract), and
    // no rows are added/updated/removed.
    auto same = wait_for_import_event(*eng, eng->rescan());
    ASSERT_EQ(same.status, PHOTO_STATUS_OK);
    EXPECT_EQ(same.aux64, 0u);           // added
    EXPECT_EQ(same.aux64_b, 0u);         // updated
    EXPECT_EQ(same._reserved[0], 3u);    // skipped
    EXPECT_EQ(same._reserved[1], 0u);    // removed

    // Modify exactly one file (new bytes change its size; bump mtime too for
    // coarse-granularity filesystems). Rescan must re-read only that one.
    write_file(dir / "a.jpg", "different-bytes");
    fs::last_write_time(
        dir / "a.jpg",
        fs::file_time_type::clock::now() + std::chrono::seconds(2));
    auto changed = wait_for_import_event(*eng, eng->rescan());
    ASSERT_EQ(changed.status, PHOTO_STATUS_OK);
    EXPECT_EQ(changed.aux64, 0u);        // added
    EXPECT_EQ(changed.aux64_b, 1u);      // updated
    EXPECT_EQ(changed._reserved[0], 2u); // skipped
    EXPECT_EQ(changed._reserved[1], 0u); // removed
}

TEST(Import, AssetIdStableAcrossRestart) {
    auto dir = make_tree("stable");
    write_file(dir / "keep.jpg");

    uint64_t first_id = 0;
    {
        auto eng = make_engine(dir);
        ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));
        auto assets = eng->list_assets();
        ASSERT_EQ(assets.size(), 1u);
        first_id = static_cast<uint64_t>(assets[0].id);
        EXPECT_GT(first_id, 0u);
    }
    {
        // Reopen the same catalog; no re-import. The asset_id must be identical.
        auto eng = make_engine(dir);
        auto assets = eng->list_assets();
        ASSERT_EQ(assets.size(), 1u);
        EXPECT_EQ(static_cast<uint64_t>(assets[0].id), first_id);
    }
}

// §11: a mixed photo+video folder imports both; the video row is flagged
// kind=1. Duration is filled when the build linked FFmpeg (else stays 0 but the
// row still imports — video is never dropped for lack of a decoder).
TEST(Import, VideoIsImportedAndFlagged) {
    auto dir = make_tree("video");
    write_file(dir / "photo.jpg");
    fs::copy_file(fs::path(PHOTO_TEST_DATA_DIR) / "tiny.mp4",
                  dir / "clip.mp4", fs::copy_options::overwrite_existing);

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);
    const uint64_t req = eng->import_path(dir.string());
    ASSERT_NE(req, 0u);
    ASSERT_TRUE(wait_for_import(*eng, req));

    auto assets = eng->list_assets();
    ASSERT_EQ(assets.size(), 2u);
    const photo::catalog::AssetRecord* vid = nullptr;
    const photo::catalog::AssetRecord* pho = nullptr;
    for (const auto& a : assets) {
        if (a.path == (dir / "clip.mp4").string()) vid = &a;
        if (a.path == (dir / "photo.jpg").string()) pho = &a;
    }
    ASSERT_NE(vid, nullptr);
    ASSERT_NE(pho, nullptr);
    EXPECT_EQ(vid->kind, 1);
    EXPECT_EQ(pho->kind, 0);
#ifdef PHOTO_HAVE_FFMPEG
    EXPECT_EQ(vid->width, 64);
    EXPECT_EQ(vid->height, 48);
    EXPECT_NEAR(vid->duration_ms, 2000, 200);
#endif

    // Rescan is idempotent (unchanged files skipped, nothing re-added).
    const auto ev = wait_for_import_event(*eng, eng->rescan());
    EXPECT_EQ(ev.aux64, 0u);         // added
    EXPECT_EQ(ev.aux64_b, 0u);       // updated
    EXPECT_EQ(eng->list_assets().size(), 2u);
}

TEST(Import, RescanAfterRelocateIsChurnFree) {
    // The acceptance test for in-app file moves: move a file on disk, tell the
    // catalog via relocate_assets, and a rescan must see NOTHING to do — same
    // id, no add/remove churn, user state (star) intact. Without relocate this
    // sequence orphans every id-keyed row (the pre-relocate status quo).
    auto dir = make_tree("reloc_churn");
    write_file(dir / "a" / "one.jpg");
    write_file(dir / "a" / "two.jpg");

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);
    ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));

    auto assets = eng->list_assets();
    ASSERT_EQ(assets.size(), 2u);
    int64_t moved_id = 0;
    for (const auto& a : assets)
        if (a.path == (dir / "a" / "one.jpg").string()) moved_id = a.id;
    ASSERT_NE(moved_id, 0);
    eng->set_starred(moved_id, true);

    // Move on disk first (what the app's move service does), then relocate.
    const auto dest = dir / "b" / "one.jpg";
    fs::create_directories(dest.parent_path());
    fs::rename(dir / "a" / "one.jpg", dest);
    EXPECT_EQ(eng->relocate_assets({{moved_id, dest.string()}}, nullptr), 1);

    auto ev = wait_for_import_event(*eng, eng->rescan());
    ASSERT_EQ(ev.status, PHOTO_STATUS_OK);
    EXPECT_EQ(ev.aux64, 0u);            // added
    EXPECT_EQ(ev.aux64_b, 0u);          // updated
    EXPECT_EQ(ev._reserved[0], 2u);     // both files skipped (unchanged)
    EXPECT_EQ(ev._reserved[1], 0u);     // removed

    auto after = eng->list_assets();
    ASSERT_EQ(after.size(), 2u);
    bool found = false;
    for (const auto& a : after) {
        if (a.id != moved_id) continue;
        found = true;
        EXPECT_EQ(a.path, dest.string());
        EXPECT_TRUE(a.starred);
    }
    EXPECT_TRUE(found);
}

#endif  // PHOTO_HAVE_SQLITE
