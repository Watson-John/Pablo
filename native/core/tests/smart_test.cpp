// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// smart_test.cpp — smart-collection catalog queries: Recently Added (by
// import_time, limited, hidden-excluded) and Starred (hidden-excluded).

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_smart_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

int64_t add(Catalog& cat, const std::string& path, int64_t import_time) {
    AssetRecord r;
    r.path = path;
    r.folder = "/x";
    r.filename = path;
    r.import_time = import_time;
    return cat.upsert_asset(r);  // starred/hidden default 0; set explicitly
}
}  // namespace

TEST(Smart, RecentOrdersByImportTimeWithLimitAndHiddenExcluded) {
    Catalog cat(fresh_db("recent"));
    const int64_t a = add(cat, "/x/a.jpg", 100);
    const int64_t b = add(cat, "/x/b.jpg", 300);
    const int64_t c = add(cat, "/x/c.jpg", 200);

    auto two = cat.recent_assets(2);
    ASSERT_EQ(two.size(), 2u);
    EXPECT_EQ(two[0], b);  // import_time 300 (newest)
    EXPECT_EQ(two[1], c);  // 200

    auto all = cat.recent_assets(10);  // limit > count → all, newest first
    ASSERT_EQ(all.size(), 3u);
    EXPECT_EQ(all[0], b);
    EXPECT_EQ(all[2], a);

    cat.set_hidden(b, true);  // hidden assets drop out of Recently Added
    auto r2 = cat.recent_assets(10);
    ASSERT_EQ(r2.size(), 2u);
    EXPECT_EQ(r2[0], c);
    EXPECT_EQ(r2[1], a);
}

TEST(Smart, StarredExcludesHidden) {
    Catalog cat(fresh_db("starred"));
    const int64_t a = add(cat, "/x/a.jpg", 1);
    const int64_t b = add(cat, "/x/b.jpg", 2);
    const int64_t c = add(cat, "/x/c.jpg", 3);

    EXPECT_TRUE(cat.starred_assets().empty());

    cat.set_starred(a, true);
    cat.set_starred(b, true);
    EXPECT_EQ(cat.starred_assets().size(), 2u);

    cat.set_hidden(b, true);  // hidden starred photo is excluded
    auto s = cat.starred_assets();
    ASSERT_EQ(s.size(), 1u);
    EXPECT_EQ(s[0], a);

    cat.set_starred(c, true);
    EXPECT_EQ(cat.starred_assets().size(), 2u);  // a + c
}

#endif  // PHOTO_HAVE_SQLITE
