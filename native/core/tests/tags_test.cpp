// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// tags_test.cpp — keyword/tag edge cases beyond organize_test.cpp's happy-path
// add/remove/list/search (§5 Organize & metadata). Covers case sensitivity,
// idempotent / no-op mutations, sharing one tag across many assets, the orphan
// tag-row lifecycle (a `tag` row outlives its last membership and is reused),
// and Unicode / SQL-metacharacter safety.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>
#include <vector>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_tags_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(Tags, NamesAreCaseSensitive) {
    Catalog cat(fresh_db("case"));
    cat.add_tag(1, "Beach");
    cat.add_tag(1, "beach");
    auto t = cat.tags_for_asset(1);
    ASSERT_EQ(t.size(), 2u);   // distinct tag rows
    EXPECT_EQ(t[0], "Beach");  // sorted; uppercase sorts before lowercase (ASCII)
    EXPECT_EQ(t[1], "beach");
    EXPECT_EQ(cat.assets_with_tag("Beach").size(), 1u);
    EXPECT_TRUE(cat.assets_with_tag("BEACH").empty());  // exact-match only
}

TEST(Tags, AddIsIdempotentPerMembership) {
    Catalog cat(fresh_db("idem"));
    cat.add_tag(1, "sky");
    cat.add_tag(1, "sky");  // PRIMARY KEY(asset_id, tag_id) ignores the re-add
    cat.add_tag(1, "sky");
    auto t = cat.tags_for_asset(1);
    ASSERT_EQ(t.size(), 1u);
    EXPECT_EQ(t[0], "sky");
}

TEST(Tags, RemoveNonMemberIsNoOp) {
    Catalog cat(fresh_db("rm_noop"));
    cat.add_tag(1, "x");
    cat.remove_tag(1, "never-added");  // membership absent
    cat.remove_tag(2, "x");            // asset 2 never had x
    cat.remove_tag(1, "x");            // present → removed
    cat.remove_tag(1, "x");            // already gone → still a no-op
    EXPECT_TRUE(cat.tags_for_asset(1).empty());
}

TEST(Tags, SharedAcrossManyAssets) {
    Catalog cat(fresh_db("shared"));
    for (int64_t id : {1, 2, 3, 4}) cat.add_tag(id, "trip");
    EXPECT_EQ(cat.assets_with_tag("trip").size(), 4u);
    cat.remove_tag(2, "trip");
    EXPECT_EQ(cat.assets_with_tag("trip").size(), 3u);
    // Only asset 2's membership is gone; 1/3/4 each still carry exactly "trip"
    // (this catches a remove that dropped the wrong membership).
    EXPECT_EQ(cat.tags_for_asset(1), (std::vector<std::string>{"trip"}));
    EXPECT_TRUE(cat.tags_for_asset(2).empty());
    EXPECT_EQ(cat.tags_for_asset(3), (std::vector<std::string>{"trip"}));
    EXPECT_EQ(cat.tags_for_asset(4), (std::vector<std::string>{"trip"}));
}

TEST(Tags, OrphanTagRowSurvivesAndIsReused) {
    Catalog cat(fresh_db("orphan"));
    cat.add_tag(1, "solo");
    cat.remove_tag(1, "solo");  // last membership gone
    EXPECT_TRUE(cat.assets_with_tag("solo").empty());
    // The `tag` row persists (names dedup through it). Re-adding to a different
    // asset reuses that row rather than tripping the UNIQUE(name) constraint.
    cat.add_tag(2, "solo");
    EXPECT_EQ(cat.assets_with_tag("solo"), (std::vector<int64_t>{2}));
}

TEST(Tags, ManyTagsForOneAssetAreSorted) {
    Catalog cat(fresh_db("sorted"));
    for (const char* name : {"delta", "alpha", "charlie", "bravo"})
        cat.add_tag(9, name);
    EXPECT_EQ(cat.tags_for_asset(9),
              (std::vector<std::string>{"alpha", "bravo", "charlie", "delta"}));
}

TEST(Tags, Utf8AndMetacharNamesRoundTrip) {
    Catalog cat(fresh_db("utf8"));
    const std::string a = "naïve-tag";
    const std::string b = "drop'; DELETE FROM tag;--";  // bound, not concatenated
    cat.add_tag(7, a);
    cat.add_tag(7, b);
    ASSERT_EQ(cat.tags_for_asset(7).size(), 2u);
    EXPECT_EQ(cat.assets_with_tag(a), (std::vector<int64_t>{7}));
    EXPECT_EQ(cat.assets_with_tag(b), (std::vector<int64_t>{7}));
    // The injection literal did not execute — the tag table still holds 2 names.
    EXPECT_EQ(cat.tags_for_asset(7).size(), 2u);
}

TEST(Tags, UnknownAssetOrTagYieldsEmpty) {
    Catalog cat(fresh_db("empty"));
    EXPECT_TRUE(cat.tags_for_asset(123).empty());
    EXPECT_TRUE(cat.assets_with_tag("ghost").empty());
}

TEST(Tags, PersistAcrossReopenWithSharing) {
    const std::string db = fresh_db("persist");
    {
        Catalog cat(db);
        cat.add_tag(1, "keep");
        cat.add_tag(2, "keep");
        cat.add_tag(1, "unique");
    }
    {
        Catalog cat(db);
        EXPECT_EQ(cat.assets_with_tag("keep").size(), 2u);
        EXPECT_EQ(cat.tags_for_asset(1),
                  (std::vector<std::string>{"keep", "unique"}));
    }
}

#endif  // PHOTO_HAVE_SQLITE
