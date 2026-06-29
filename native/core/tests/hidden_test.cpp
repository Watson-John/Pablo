// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// hidden_test.cpp — per-asset hide, folder-level hide (persisted rule + sweep),
// separator-boundary safety, and that import re-applies a hidden folder.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>

#include "catalog/catalog.h"
#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::Engine;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {

std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_hidden_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

int64_t add_asset(Catalog& cat, const std::string& path) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    return cat.upsert_asset(r);
}

fs::path make_tree(const char* tag) {
    auto root = fs::temp_directory_path() / ("photo_hidden_eng_" + std::string(tag));
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

}  // namespace

TEST(Hidden, PerAssetRoundTripAndExclusion) {
    const std::string db = fresh_db("asset");
    int64_t id = 0;
    {
        Catalog cat(db);
        id = add_asset(cat, "/lib/a.jpg");
        add_asset(cat, "/lib/b.jpg");
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 2u);

        cat.set_hidden(id, true);
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 1u);
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/true).size(), 2u);
    }
    {
        // Hidden state is durable across reopen.
        Catalog cat(db);
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 1u);
        cat.set_hidden(id, false);
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 2u);
    }
}

TEST(Hidden, FolderRuleListAndBoundary) {
    Catalog cat(fresh_db("folder"));
    cat.add_hidden_folder("/a/photos");
    cat.add_hidden_folder("/a/photos");  // idempotent

    auto dirs = cat.hidden_folders();
    ASSERT_EQ(dirs.size(), 1u);
    EXPECT_EQ(dirs[0], "/a/photos");

    EXPECT_TRUE(cat.is_path_hidden("/a/photos"));            // the folder itself
    EXPECT_TRUE(cat.is_path_hidden("/a/photos/x.jpg"));      // a child
    EXPECT_TRUE(cat.is_path_hidden("/a/photos/sub/y.jpg"));  // a descendant
    EXPECT_FALSE(cat.is_path_hidden("/a/photoshop/z.jpg"));  // boundary: not a child
    EXPECT_FALSE(cat.is_path_hidden("/a/other.jpg"));

    cat.remove_hidden_folder("/a/photos");
    EXPECT_TRUE(cat.hidden_folders().empty());
    EXPECT_FALSE(cat.is_path_hidden("/a/photos/x.jpg"));
}

TEST(Hidden, FolderSweepHidesAndUnhides) {
    Catalog cat(fresh_db("sweep"));
    add_asset(cat, "/a/photos/x.jpg");
    add_asset(cat, "/a/photos/sub/y.jpg");
    add_asset(cat, "/a/photoshop/z.jpg");  // boundary — must stay visible
    add_asset(cat, "/a/other.jpg");

    cat.set_assets_hidden_under("/a/photos", true);
    EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 2u);  // shop + other
    EXPECT_EQ(cat.list_assets(/*include_hidden=*/true).size(), 4u);

    cat.set_assets_hidden_under("/a/photos", false);
    EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 4u);
}

TEST(Hidden, ImportReappliesHiddenFolder) {
    auto dir = make_tree("reapply");
    write_file(dir / "vis.jpg");
    write_file(dir / "secret" / "s1.jpg");
    write_file(dir / "secret" / "s2.jpg");

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);
    ASSERT_TRUE(wait_for_import(*eng, eng->import_path(dir.string())));
    EXPECT_EQ(eng->list_assets().size(), 3u);

    // Hide the secret folder: existing assets are swept hidden immediately.
    const std::string secret = (dir / "secret").string();
    eng->set_folder_hidden(secret, true);
    EXPECT_EQ(eng->list_assets().size(), 1u);  // only vis.jpg visible

    // A new file dropped into the hidden folder stays hidden after rescan
    // (upsert preserves the hidden field, and the rule re-forces new rows).
    write_file(dir / "secret" / "s3.jpg");
    ASSERT_TRUE(wait_for_import(*eng, eng->rescan()));
    EXPECT_EQ(eng->list_assets().size(), 1u);

    // The rule persists; the folder appears in the hidden list.
    auto dirs = eng->hidden_folders();
    ASSERT_EQ(dirs.size(), 1u);
    EXPECT_EQ(dirs[0], secret);

    // Un-hiding the folder reveals everything beneath it.
    eng->set_folder_hidden(secret, false);
    EXPECT_EQ(eng->list_assets().size(), 4u);
    EXPECT_TRUE(eng->hidden_folders().empty());
}

#endif  // PHOTO_HAVE_SQLITE
