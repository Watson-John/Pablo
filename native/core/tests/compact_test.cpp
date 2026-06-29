// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// compact_test.cpp — catalog maintenance: stats reporting, and that compact()
// reclaims freelist pages left by deletes while preserving the surviving data.

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
    auto dir = fs::temp_directory_path() / ("photo_compact_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(Compact, ReclaimsFreelistAndPreservesData) {
    const std::string db = fresh_db("reclaim");
    {
        Catalog cat(db);

        // Bulk the DB across several pages: each asset carries a large caption.
        const std::string big(512, 'z');
        std::vector<int64_t> ids;
        for (int i = 0; i < 500; ++i) {
            AssetRecord r;
            r.path = "/x/" + std::to_string(i) + ".jpg";
            r.folder = "/x";
            r.filename = std::to_string(i);
            const int64_t id = cat.upsert_asset(r);
            cat.set_caption(id, big);  // caption isn't written on insert
            ids.push_back(id);
        }

        // Delete all but the last 10 → their pages go onto the freelist.
        for (size_t i = 0; i + 10 < ids.size(); ++i) cat.remove_asset(ids[i]);
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/true).size(), 10u);

        const auto mid = cat.stats();
        EXPECT_GT(mid.page_size, 0);
        EXPECT_GT(mid.freelist_count, 0);  // deletes freed pages

        cat.compact();
        const auto after = cat.stats();
        EXPECT_EQ(after.freelist_count, 0);           // VACUUM reclaimed them
        EXPECT_LE(after.page_count, mid.page_count);  // file did not grow
        EXPECT_EQ(cat.list_assets(/*include_hidden=*/true).size(), 10u);
    }
    // Surviving data is durable across a reopen of the compacted DB.
    {
        Catalog reopened(db);
        EXPECT_EQ(reopened.list_assets(/*include_hidden=*/true).size(), 10u);
    }
}

TEST(Compact, SafeOnEmptyDatabase) {
    Catalog cat(fresh_db("empty"));
    cat.compact();  // must not throw on a fresh schema-only DB
    const auto s = cat.stats();
    EXPECT_GT(s.page_size, 0);
    EXPECT_GE(s.page_count, 1);
    EXPECT_EQ(s.freelist_count, 0);
}

#endif  // PHOTO_HAVE_SQLITE
