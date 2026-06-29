// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// rebase_test.cpp — relocating the photo library: rebase_paths rewrites every
// stored path under a prefix, preserves asset ids (so albums/tags/hidden
// survive), respects separator boundaries, and is transactional.

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
    auto dir = fs::temp_directory_path() / ("photo_rebase_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

int64_t add(Catalog& cat, const std::string& path) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    return cat.upsert_asset(r);
}
}  // namespace

TEST(Rebase, RewritesPathsPreservesIdsAndBoundaries) {
    Catalog cat(fresh_db("rewrite"));

    const int64_t a = add(cat, "/old/lib/a.jpg");
    const int64_t b = add(cat, "/old/lib/sub/b.jpg");
    const int64_t outside = add(cat, "/older/c.jpg");  // boundary — untouched

    // Attach organize state that must survive the move (keyed by asset id).
    const int64_t album = cat.create_album("Trip", 1);
    cat.add_to_album(album, a);
    cat.add_tag(b, "beach");
    cat.add_hidden_folder("/old/lib/sub");
    cat.set_assets_hidden_under("/old/lib/sub", true);
    cat.add_import_root("/old/lib");

    const int64_t n = cat.rebase_paths("/old/lib", "/new/spot");
    EXPECT_EQ(n, 2);  // a + b rewritten; outside untouched

    // Paths rewritten, ids identical.
    auto ra = cat.asset_by_id(a);
    auto rb = cat.asset_by_id(b);
    ASSERT_TRUE(ra.has_value());
    ASSERT_TRUE(rb.has_value());
    EXPECT_EQ(ra->path, "/new/spot/a.jpg");
    EXPECT_EQ(ra->folder, "/new/spot");
    EXPECT_EQ(rb->path, "/new/spot/sub/b.jpg");
    EXPECT_EQ(rb->folder, "/new/spot/sub");

    // Boundary: /older/c.jpg was NOT caught by the /old/lib prefix.
    auto rc = cat.asset_by_id(outside);
    ASSERT_TRUE(rc.has_value());
    EXPECT_EQ(rc->path, "/older/c.jpg");

    // Album membership + tag + import root + hidden folder followed the ids.
    auto members = cat.album_members(album);
    ASSERT_EQ(members.size(), 1u);
    EXPECT_EQ(members[0], a);
    EXPECT_EQ(cat.tags_for_asset(b).size(), 1u);

    auto roots = cat.import_roots();
    ASSERT_EQ(roots.size(), 1u);
    EXPECT_EQ(roots[0], "/new/spot");

    auto hidden = cat.hidden_folders();
    ASSERT_EQ(hidden.size(), 1u);
    EXPECT_EQ(hidden[0], "/new/spot/sub");
    // b sat under the hidden folder and is still hidden after the rebase.
    ASSERT_TRUE(cat.asset_by_id(b)->hidden);
}

TEST(Rebase, NoOpWhenPrefixesEqualOrEmpty) {
    Catalog cat(fresh_db("noop"));
    add(cat, "/lib/a.jpg");
    EXPECT_EQ(cat.rebase_paths("/lib", "/lib"), 0);
    EXPECT_EQ(cat.rebase_paths("", "/new"), 0);
    EXPECT_EQ(cat.asset_by_path("/lib/a.jpg").has_value(), true);
}

#endif  // PHOTO_HAVE_SQLITE
