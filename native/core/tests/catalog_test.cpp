// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// catalog_test.cpp — white-box tests for the durable asset catalog. Linked
// against photo_core_objects (PHOTO_HAVE_SQLITE propagates from there); when
// SQLite is unavailable the file compiles to no tests.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {

// A fresh, empty DB path under the temp dir (WAL siblings removed too).
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_catalog_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

AssetRecord sample(const std::string& path, int64_t size = 100, int64_t mtime = 5) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    r.size = size;
    r.mtime_ns = mtime;
    r.width = 640;
    r.height = 480;
    r.format = "jpeg";
    r.import_time = 1000;
    return r;
}

}  // namespace

TEST(Catalog, UpsertAndReadBack) {
    Catalog cat(fresh_db("readback"));
    ASSERT_TRUE(cat.ok());

    auto rec = sample("/lib/a.jpg");
    const int64_t id = cat.upsert_asset(rec);
    EXPECT_GT(id, 0);
    EXPECT_EQ(rec.id, id);
    EXPECT_EQ(cat.count(), 1);
    EXPECT_EQ(cat.path_by_id(id), "/lib/a.jpg");

    auto by_id = cat.asset_by_id(id);
    ASSERT_TRUE(by_id.has_value());
    EXPECT_EQ(by_id->filename, "a.jpg");
    EXPECT_EQ(by_id->width, 640);
    EXPECT_EQ(by_id->format, "jpeg");

    auto by_path = cat.asset_by_path("/lib/a.jpg");
    ASSERT_TRUE(by_path.has_value());
    EXPECT_EQ(by_path->id, id);

    EXPECT_FALSE(cat.asset_by_id(999).has_value());
    EXPECT_EQ(cat.path_by_id(999), "");
}

TEST(Catalog, PersistsAcrossReopen) {
    const std::string db = fresh_db("persist");
    int64_t id = 0;
    {
        Catalog cat(db);
        auto rec = sample("/lib/keep.png", /*size=*/42, /*mtime=*/7);
        id = cat.upsert_asset(rec);
        EXPECT_EQ(cat.count(), 1);
    }
    {
        Catalog cat(db);  // reopen the same file
        EXPECT_EQ(cat.count(), 1);
        auto rec = cat.asset_by_id(id);
        ASSERT_TRUE(rec.has_value());
        EXPECT_EQ(rec->path, "/lib/keep.png");
        EXPECT_EQ(rec->size, 42);
        EXPECT_EQ(rec->mtime_ns, 7);
    }
}

TEST(Catalog, UpsertPreservesUserFieldsRefreshesFileFields) {
    Catalog cat(fresh_db("upsert"));
    auto rec = sample("/lib/p.jpg", /*size=*/100, /*mtime=*/1);
    const int64_t id = cat.upsert_asset(rec);

    cat.set_starred(id, true);
    cat.set_rating(id, 4);
    cat.set_caption(id, "sunset");

    // Re-import the same path with new file stats.
    auto again = sample("/lib/p.jpg", /*size=*/200, /*mtime=*/9);
    const int64_t id2 = cat.upsert_asset(again);
    EXPECT_EQ(id2, id);            // same row, not a duplicate
    EXPECT_EQ(cat.count(), 1);

    auto got = cat.asset_by_id(id);
    ASSERT_TRUE(got.has_value());
    EXPECT_EQ(got->size, 200);     // file field refreshed
    EXPECT_EQ(got->mtime_ns, 9);
    EXPECT_TRUE(got->starred);     // user fields preserved
    EXPECT_EQ(got->rating, 4);
    EXPECT_EQ(got->caption, "sunset");
}

TEST(Catalog, ListOrdersByPathAndHidesHidden) {
    Catalog cat(fresh_db("list"));
    auto c = sample("/lib/c.jpg");
    auto a = sample("/lib/a.jpg");
    auto b = sample("/lib/b.jpg");
    cat.upsert_asset(c);
    cat.upsert_asset(a);
    cat.upsert_asset(b);

    auto all = cat.list_assets();
    ASSERT_EQ(all.size(), 3u);
    EXPECT_EQ(all[0].path, "/lib/a.jpg");
    EXPECT_EQ(all[1].path, "/lib/b.jpg");
    EXPECT_EQ(all[2].path, "/lib/c.jpg");

    cat.set_hidden(b.id, true);
    EXPECT_EQ(cat.list_assets(/*include_hidden=*/false).size(), 2u);
    EXPECT_EQ(cat.list_assets(/*include_hidden=*/true).size(), 3u);
}

TEST(Catalog, RemoveAsset) {
    Catalog cat(fresh_db("remove"));
    auto rec = sample("/lib/gone.jpg");
    const int64_t id = cat.upsert_asset(rec);
    EXPECT_EQ(cat.count(), 1);

    cat.remove_asset(id);
    EXPECT_EQ(cat.count(), 0);
    EXPECT_FALSE(cat.asset_by_id(id).has_value());
}

#endif  // PHOTO_HAVE_SQLITE
