// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// organize_test.cpp — tag CRUD + search. (Star/rating/caption round-trips are
// covered by catalog_test.UpsertPreservesUserFields...)

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_organize_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(Tags, AddRemoveListSearch) {
    Catalog cat(fresh_db("tags"));

    cat.add_tag(1, "beach");
    cat.add_tag(1, "summer");
    cat.add_tag(1, "beach");  // idempotent membership; tag table dedups by name
    cat.add_tag(2, "beach");

    auto t1 = cat.tags_for_asset(1);
    ASSERT_EQ(t1.size(), 2u);
    EXPECT_EQ(t1[0], "beach");  // sorted
    EXPECT_EQ(t1[1], "summer");

    auto beach = cat.assets_with_tag("beach");
    ASSERT_EQ(beach.size(), 2u);  // assets 1 and 2

    cat.remove_tag(1, "beach");
    t1 = cat.tags_for_asset(1);
    ASSERT_EQ(t1.size(), 1u);
    EXPECT_EQ(t1[0], "summer");
    EXPECT_EQ(cat.assets_with_tag("beach").size(), 1u);  // only asset 2 now

    EXPECT_TRUE(cat.tags_for_asset(99).empty());
    EXPECT_TRUE(cat.assets_with_tag("nope").empty());
}

TEST(Tags, PersistAcrossReopen) {
    const std::string db = fresh_db("persist");
    {
        Catalog cat(db);
        cat.add_tag(7, "x");
        cat.add_tag(7, "y");
    }
    {
        Catalog cat(db);
        auto t = cat.tags_for_asset(7);
        ASSERT_EQ(t.size(), 2u);
        EXPECT_EQ(t[0], "x");
        EXPECT_EQ(t[1], "y");
    }
}

#endif  // PHOTO_HAVE_SQLITE
