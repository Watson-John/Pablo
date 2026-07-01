// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// organize_state_test.cpp — exhaustive coverage of the user-authored organize
// fields the catalog persists: star / numeric rating / caption (§5 Organize &
// metadata). catalog_test.cpp proves these survive a re-import; this file pins
// the per-field contracts that file does not: toggling + per-asset isolation,
// no-op on unknown ids, the (deliberately) un-clamped rating range at the
// storage layer, caption robustness against UTF-8 and SQL metacharacters, and
// the starred smart-set's ordering / hidden-exclusion.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>
#include <vector>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {

std::string fresh_db(const char* tag) {
    auto dir =
        fs::temp_directory_path() / ("photo_organize_state_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

int64_t seed(Catalog& cat, const std::string& path) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    r.format = "jpeg";
    return cat.upsert_asset(r);
}

}  // namespace

TEST(OrganizeState, StarToggleAndPerAssetIsolation) {
    Catalog cat(fresh_db("star"));
    const int64_t a = seed(cat, "/lib/a.jpg");
    const int64_t b = seed(cat, "/lib/b.jpg");

    EXPECT_FALSE(cat.asset_by_id(a)->starred);  // default off

    cat.set_starred(a, true);
    EXPECT_TRUE(cat.asset_by_id(a)->starred);
    EXPECT_FALSE(cat.asset_by_id(b)->starred);  // b untouched

    cat.set_starred(a, true);  // idempotent re-set
    EXPECT_TRUE(cat.asset_by_id(a)->starred);

    cat.set_starred(a, false);
    EXPECT_FALSE(cat.asset_by_id(a)->starred);
}

TEST(OrganizeState, SettersOnUnknownIdAreNoOps) {
    Catalog cat(fresh_db("unknown"));
    // No row #999 exists; setters must not create one, nor throw.
    cat.set_starred(999, true);
    cat.set_rating(999, 5);
    cat.set_caption(999, "ghost");
    cat.set_hidden(999, true);
    EXPECT_EQ(cat.count(), 0);
    EXPECT_FALSE(cat.asset_by_id(999).has_value());
}

TEST(OrganizeState, RatingStoredVerbatimIncludingOutOfRange) {
    Catalog cat(fresh_db("rating"));
    const int64_t id = seed(cat, "/lib/r.jpg");

    for (int32_t v : {0, 1, 5}) {
        cat.set_rating(id, v);
        EXPECT_EQ(cat.asset_by_id(id)->rating, v);
    }
    // The catalog layer intentionally does NOT clamp — it stores what it is
    // given. The 0..5 contract is enforced above this layer (UI / C ABI). Pin
    // the current behavior so an accidental clamp added here would be caught.
    cat.set_rating(id, -1);
    EXPECT_EQ(cat.asset_by_id(id)->rating, -1);
    cat.set_rating(id, 99);
    EXPECT_EQ(cat.asset_by_id(id)->rating, 99);
}

TEST(OrganizeState, CaptionOverwriteClearAndUtf8) {
    Catalog cat(fresh_db("caption"));
    const int64_t id = seed(cat, "/lib/c.jpg");

    EXPECT_EQ(cat.asset_by_id(id)->caption, "");  // default empty

    cat.set_caption(id, "sunset over the bay");
    EXPECT_EQ(cat.asset_by_id(id)->caption, "sunset over the bay");

    cat.set_caption(id, "Café — 北京 — 😀");  // multibyte UTF-8 round-trips
    EXPECT_EQ(cat.asset_by_id(id)->caption, "Café — 北京 — 😀");

    cat.set_caption(id, "");  // clearing back to empty
    EXPECT_EQ(cat.asset_by_id(id)->caption, "");
}

TEST(OrganizeState, CaptionWithSqlMetacharactersIsBoundSafely) {
    Catalog cat(fresh_db("inject"));
    const int64_t id = seed(cat, "/lib/q.jpg");
    // If captions were concatenated into SQL instead of bound as a parameter,
    // this string would corrupt the statement / drop a table. Binding makes it
    // an inert literal.
    const std::string nasty = "O'Brien \"x\"; DROP TABLE asset;-- \n\t end";
    cat.set_caption(id, nasty);
    EXPECT_EQ(cat.asset_by_id(id)->caption, nasty);
    EXPECT_EQ(cat.count(), 1);  // asset table is still there
}

TEST(OrganizeState, FieldsAreIndependentAndPersistAcrossReopen) {
    const std::string db = fresh_db("persist");
    int64_t id = 0;
    {
        Catalog cat(db);
        id = seed(cat, "/lib/p.jpg");
        cat.set_starred(id, true);
        cat.set_rating(id, 3);
        cat.set_caption(id, "kept");
        cat.set_hidden(id, true);
    }
    {
        Catalog cat(db);  // reopen the same file
        auto r = cat.asset_by_id(id);
        ASSERT_TRUE(r.has_value());
        EXPECT_TRUE(r->starred);
        EXPECT_EQ(r->rating, 3);
        EXPECT_EQ(r->caption, "kept");
        EXPECT_TRUE(r->hidden);
    }
}

TEST(OrganizeState, StarredSmartSetExcludesHiddenOrdersByPathReflectsUnstar) {
    Catalog cat(fresh_db("starred_set"));
    const int64_t c = seed(cat, "/lib/c.jpg");
    const int64_t a = seed(cat, "/lib/a.jpg");
    const int64_t b = seed(cat, "/lib/b.jpg");
    cat.set_starred(a, true);
    cat.set_starred(b, true);
    cat.set_starred(c, true);

    // Seed order was (c, a, b) so the id order (c=1, a=2, b=3) differs from the
    // path order (a, b, c) — this assertion fails if starred_assets sorts by id.
    EXPECT_EQ(cat.starred_assets(), (std::vector<int64_t>{a, b, c}));  // by path
    EXPECT_NE(cat.starred_assets(), (std::vector<int64_t>{c, a, b}));  // != id order

    cat.set_hidden(b, true);  // a hidden starred asset drops out of the set
    EXPECT_EQ(cat.starred_assets(), (std::vector<int64_t>{a, c}));

    cat.set_starred(a, false);  // unstar removes from the set
    EXPECT_EQ(cat.starred_assets(), (std::vector<int64_t>{c}));
}

#endif  // PHOTO_HAVE_SQLITE
