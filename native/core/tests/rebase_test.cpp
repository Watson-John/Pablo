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

// ── relocate_assets — per-asset path moves (in-app file moves/renames) ──────

TEST(Relocate, PreservesIdAndOrganizeState) {
    Catalog cat(fresh_db("reloc_keep"));

    const int64_t a = add(cat, "/lib/inbox/a.jpg");
    const int64_t album = cat.create_album("Trip", 1);
    cat.add_to_album(album, a);
    cat.add_tag(a, "beach");
    cat.set_geo_override(a, 12.5, -70.1);
    cat.set_edit(a, "bright=0.2;", 111);
    cat.set_starred(a, true);

    std::vector<uint8_t> ok;
    const int64_t n = cat.relocate_assets(
        {{a, "/lib/sorted/2024/a.jpg"}}, &ok);
    EXPECT_EQ(n, 1);
    ASSERT_EQ(ok.size(), 1u);
    EXPECT_EQ(ok[0], 1);

    auto r = cat.asset_by_id(a);
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(r->path, "/lib/sorted/2024/a.jpg");
    EXPECT_EQ(r->folder, "/lib/sorted/2024");
    EXPECT_EQ(r->filename, "a.jpg");
    EXPECT_TRUE(r->starred);

    // Everything keyed by the id is still attached.
    auto members = cat.album_members(album);
    ASSERT_EQ(members.size(), 1u);
    EXPECT_EQ(members[0], a);
    EXPECT_EQ(cat.tags_for_asset(a).size(), 1u);
    ASSERT_TRUE(cat.geo_override_for(a).has_value());
    ASSERT_TRUE(cat.edit_for(a).has_value());
    // The old path no longer resolves; the new one does, to the same id.
    EXPECT_FALSE(cat.asset_by_path("/lib/inbox/a.jpg").has_value());
    ASSERT_TRUE(cat.asset_by_path("/lib/sorted/2024/a.jpg").has_value());
    EXPECT_EQ(cat.asset_by_path("/lib/sorted/2024/a.jpg")->id, a);
}

TEST(Relocate, SkipsUniqueCollisionAppliesCleanRows) {
    Catalog cat(fresh_db("reloc_clash"));
    const int64_t a = add(cat, "/lib/a.jpg");
    const int64_t b = add(cat, "/lib/b.jpg");
    const int64_t c = add(cat, "/lib/c.jpg");

    // a → b's path collides (skipped); c → fresh path applies. One batch.
    std::vector<uint8_t> ok;
    const int64_t n = cat.relocate_assets(
        {{a, "/lib/b.jpg"}, {c, "/lib/sub/c.jpg"}}, &ok);
    EXPECT_EQ(n, 1);
    ASSERT_EQ(ok.size(), 2u);
    EXPECT_EQ(ok[0], 0);
    EXPECT_EQ(ok[1], 1);

    EXPECT_EQ(cat.asset_by_id(a)->path, "/lib/a.jpg");   // untouched
    EXPECT_EQ(cat.asset_by_id(b)->path, "/lib/b.jpg");   // untouched
    EXPECT_EQ(cat.asset_by_id(c)->path, "/lib/sub/c.jpg");
}

TEST(Relocate, SkipsUnknownIdEmptyAndNoopPath) {
    Catalog cat(fresh_db("reloc_skip"));
    const int64_t a = add(cat, "/lib/a.jpg");

    std::vector<uint8_t> ok;
    const int64_t n = cat.relocate_assets(
        {{9999, "/lib/x.jpg"},      // unknown id
         {a, "/lib/a.jpg"},         // path unchanged
         {a, ""}},                  // empty destination
        &ok);
    EXPECT_EQ(n, 0);
    ASSERT_EQ(ok.size(), 3u);
    EXPECT_EQ(ok[0], 0);
    EXPECT_EQ(ok[1], 0);
    EXPECT_EQ(ok[2], 0);
    EXPECT_EQ(cat.asset_by_id(a)->path, "/lib/a.jpg");

    // Empty batch is a clean no-op.
    EXPECT_EQ(cat.relocate_assets({}, nullptr), 0);
}

TEST(Relocate, UnicodeAndSpacesRoundTrip) {
    Catalog cat(fresh_db("reloc_utf8"));
    const int64_t a = add(cat, "/lib/in/photo.jpg");

    const std::string dest = "/lib/déjà vu/фото 01 (копия).jpg";
    EXPECT_EQ(cat.relocate_assets({{a, dest}}, nullptr), 1);

    auto r = cat.asset_by_id(a);
    ASSERT_TRUE(r.has_value());
    EXPECT_EQ(r->path, dest);
    EXPECT_EQ(r->folder, "/lib/déjà vu");
    EXPECT_EQ(r->filename, "фото 01 (копия).jpg");
    EXPECT_EQ(cat.asset_by_path(dest)->id, a);
}

#endif  // PHOTO_HAVE_SQLITE
