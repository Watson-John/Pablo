// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// album_test.cpp — album CRUD, membership, and persistence.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_album_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(Album, CrudMembershipAndCover) {
    Catalog cat(fresh_db("crud"));

    const int64_t a = cat.create_album("Trip", 100);
    const int64_t b = cat.create_album("Family", 200);
    EXPECT_GT(a, 0);
    EXPECT_NE(a, b);

    auto albums = cat.list_albums();
    ASSERT_EQ(albums.size(), 2u);
    EXPECT_EQ(albums[0].name, "Trip");  // ordered by created
    EXPECT_EQ(albums[0].count, 0);
    EXPECT_EQ(albums[0].cover_asset_id, -1);

    // Append + idempotent re-add; members come back in insertion order.
    cat.add_to_album(a, 10);
    cat.add_to_album(a, 11);
    cat.add_to_album(a, 10);
    auto mem = cat.album_members(a);
    ASSERT_EQ(mem.size(), 2u);
    EXPECT_EQ(mem[0], 10);
    EXPECT_EQ(mem[1], 11);
    EXPECT_EQ(cat.list_albums()[0].count, 2);

    cat.set_album_cover(a, 11);
    EXPECT_EQ(cat.list_albums()[0].cover_asset_id, 11);

    cat.remove_from_album(a, 10);
    mem = cat.album_members(a);
    ASSERT_EQ(mem.size(), 1u);
    EXPECT_EQ(mem[0], 11);

    cat.rename_album(b, "Kin");
    EXPECT_EQ(cat.list_albums()[1].name, "Kin");

    // Delete drops the album and its members.
    cat.delete_album(a);
    albums = cat.list_albums();
    ASSERT_EQ(albums.size(), 1u);
    EXPECT_EQ(albums[0].id, b);
    EXPECT_TRUE(cat.album_members(a).empty());
}

TEST(Album, PersistsAcrossReopen) {
    const std::string db = fresh_db("persist");
    int64_t a = 0;
    {
        Catalog cat(db);
        a = cat.create_album("X", 5);
        cat.add_to_album(a, 1);
        cat.add_to_album(a, 2);
    }
    {
        Catalog cat(db);
        auto albums = cat.list_albums();
        ASSERT_EQ(albums.size(), 1u);
        EXPECT_EQ(albums[0].id, a);
        EXPECT_EQ(albums[0].count, 2);
        EXPECT_EQ(cat.album_members(a).size(), 2u);
    }
}

#endif  // PHOTO_HAVE_SQLITE
