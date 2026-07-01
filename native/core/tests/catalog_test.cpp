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

// ── Stage 9: embedding / retrieval index (catalog v7) ────────────────────────

TEST(Catalog, EmbeddingUpsertGetRoundTrip) {
    Catalog cat(fresh_db("embed_crud"));  // fresh DB proves the v7 migration ran
    auto a = sample("/lib/a.jpg");
    const int64_t id = cat.upsert_asset(a);

    Catalog::EmbeddingRecord rec;
    rec.asset_id = id;
    rec.model_id = "deterministic-color";
    rec.model_version = "1";
    rec.dim = 4;
    rec.vec = {0.1f, 0.2f, 0.3f, 0.9f};
    rec.dominant_rgb = 0x804020;
    rec.status = Catalog::kEmbedDone;
    cat.upsert_embedding(rec);

    auto got = cat.get_embedding(id);
    ASSERT_TRUE(got.has_value());
    EXPECT_EQ(got->model_id, "deterministic-color");
    EXPECT_EQ(got->model_version, "1");
    EXPECT_EQ(got->dim, 4);
    ASSERT_EQ(got->vec.size(), 4u);
    EXPECT_FLOAT_EQ(got->vec[3], 0.9f);
    EXPECT_EQ(got->dominant_rgb, 0x804020);
    EXPECT_EQ(got->status, Catalog::kEmbedDone);

    auto done = cat.done_embeddings();
    ASSERT_EQ(done.size(), 1u);
    EXPECT_EQ(done[0].asset_id, id);
    ASSERT_EQ(done[0].vec.size(), 4u);

    auto colors = cat.dominant_colors();
    ASSERT_EQ(colors.size(), 1u);
    EXPECT_EQ(colors[0].first, id);
    EXPECT_EQ(colors[0].second, 0x804020);
}

TEST(Catalog, EmbeddingCountsPendingRetry) {
    Catalog cat(fresh_db("embed_counts"));
    auto a = sample("/lib/a.jpg");
    auto b = sample("/lib/b.jpg");
    auto c = sample("/lib/c.jpg");
    const int64_t ida = cat.upsert_asset(a);
    const int64_t idb = cat.upsert_asset(b);
    cat.upsert_asset(c);  // idc

    // Nothing embedded: all 3 are pending (no rows).
    auto k0 = cat.embedding_counts();
    EXPECT_EQ(k0.total, 3);
    EXPECT_EQ(k0.done, 0);
    EXPECT_EQ(k0.pending, 3);
    EXPECT_EQ(cat.pending_embedding_ids("m", "1").size(), 3u);

    // a done; b failed; c still has no row.
    Catalog::EmbeddingRecord ra;
    ra.asset_id = ida; ra.model_id = "m"; ra.model_version = "1";
    ra.dim = 2; ra.vec = {1.0f, 0.0f}; ra.status = Catalog::kEmbedDone;
    cat.upsert_embedding(ra);
    cat.set_embedding_status(idb, Catalog::kEmbedFailed, "boom");

    auto k1 = cat.embedding_counts();
    EXPECT_EQ(k1.done, 1);
    EXPECT_EQ(k1.failed, 1);
    EXPECT_EQ(k1.pending, 1);  // only c (no row); failed is NOT auto-retried
    // pending = just c (a is done+matching model, b is failed).
    EXPECT_EQ(cat.pending_embedding_ids("m", "1").size(), 1u);

    // Explicit retry flips b back to pending.
    cat.retry_failed_embeddings();
    EXPECT_EQ(cat.embedding_counts().failed, 0);
    EXPECT_EQ(cat.pending_embedding_ids("m", "1").size(), 2u);  // b + c
}

TEST(Catalog, EmbeddingModelSwitchRequeues) {
    Catalog cat(fresh_db("embed_switch"));
    auto a = sample("/lib/a.jpg");
    const int64_t id = cat.upsert_asset(a);
    Catalog::EmbeddingRecord ra;
    ra.asset_id = id; ra.model_id = "old"; ra.model_version = "1";
    ra.dim = 2; ra.vec = {1.0f, 0.0f}; ra.status = Catalog::kEmbedDone;
    cat.upsert_embedding(ra);

    EXPECT_TRUE(cat.pending_embedding_ids("old", "1").empty());   // same model
    auto pend = cat.pending_embedding_ids("new", "1");            // switched
    ASSERT_EQ(pend.size(), 1u);
    EXPECT_EQ(pend[0], id);
    EXPECT_EQ(cat.pending_embedding_ids("old", "2").size(), 1u);  // new version
}

TEST(Catalog, EmbeddingPersistsAcrossReopen) {
    const std::string db = fresh_db("embed_persist");
    int64_t id = 0;
    {
        Catalog cat(db);
        auto a = sample("/lib/a.jpg");
        id = cat.upsert_asset(a);
        Catalog::EmbeddingRecord r;
        r.asset_id = id; r.model_id = "m"; r.model_version = "1";
        r.dim = 3; r.vec = {0.5f, 0.5f, 0.7071f};
        r.dominant_rgb = 0x112233; r.status = Catalog::kEmbedDone;
        cat.upsert_embedding(r);
    }
    {
        Catalog cat(db);  // reopen
        auto got = cat.get_embedding(id);
        ASSERT_TRUE(got.has_value());
        ASSERT_EQ(got->vec.size(), 3u);
        EXPECT_EQ(got->dominant_rgb, 0x112233);
        EXPECT_EQ(got->status, Catalog::kEmbedDone);
    }
}

TEST(Catalog, SavedSearchCrud) {
    Catalog cat(fresh_db("saved"));
    const int64_t id1 = cat.create_saved_search("Trees", "{\"text\":\"tree\"}", 100);
    const int64_t id2 = cat.create_saved_search("Red", "{\"color\":\"red\"}", 200);
    EXPECT_GT(id1, 0);
    EXPECT_NE(id1, id2);

    auto all = cat.list_saved_searches();
    ASSERT_EQ(all.size(), 2u);
    EXPECT_EQ(all[0].name, "Red");    // newest first (created desc)
    EXPECT_EQ(all[1].name, "Trees");

    auto got = cat.get_saved_search(id1);
    ASSERT_TRUE(got.has_value());
    EXPECT_EQ(got->query_json, "{\"text\":\"tree\"}");

    cat.delete_saved_search(id1);
    EXPECT_EQ(cat.list_saved_searches().size(), 1u);
    EXPECT_FALSE(cat.get_saved_search(id1).has_value());
}

#endif  // PHOTO_HAVE_SQLITE
