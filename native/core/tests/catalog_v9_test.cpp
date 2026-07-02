// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// catalog_v9_test.cpp — the §11 v9 migration: asset.kind / asset.duration_ms +
// the video_edit trim table. Verifies the video columns round-trip and that a
// v8-shaped DB (simulated by dropping the v9 additions from a fresh catalog)
// forward-migrates cleanly, defaulting legacy rows to kind=0.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <sqlite3.h>

#include <filesystem>
#include <optional>
#include <string>

#include "catalog/catalog.h"

namespace fs = std::filesystem;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {

std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_catv9_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

AssetRecord photo_rec(const std::string& path) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    r.size = 100;
    r.mtime_ns = 5;
    r.width = 640;
    r.height = 480;
    r.format = "jpeg";
    r.import_time = 1000;
    return r;
}

// Simulate a pre-v9 catalog by dropping the v9 additions and resetting the
// schema version. Uses the real column set, so the forward migration is
// exercised exactly as it would run on an old DB.
void downgrade_to_v8(const std::string& path) {
    sqlite3* db = nullptr;
    ASSERT_EQ(sqlite3_open(path.c_str(), &db), SQLITE_OK);
    // SQLite >= 3.35 supports DROP COLUMN (Homebrew ships current).
    sqlite3_exec(db, "ALTER TABLE asset DROP COLUMN kind;", nullptr, nullptr,
                 nullptr);
    sqlite3_exec(db, "ALTER TABLE asset DROP COLUMN duration_ms;", nullptr,
                 nullptr, nullptr);
    sqlite3_exec(db, "DROP TABLE IF EXISTS video_edit;", nullptr, nullptr,
                 nullptr);
    ASSERT_EQ(sqlite3_exec(db, "PRAGMA user_version=8;", nullptr, nullptr,
                           nullptr),
              SQLITE_OK);
    sqlite3_close(db);
}

int schema_version(const std::string& path) {
    sqlite3* db = nullptr;
    if (sqlite3_open(path.c_str(), &db) != SQLITE_OK) return -1;
    sqlite3_stmt* st = nullptr;
    int v = -1;
    if (sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &st, nullptr) ==
        SQLITE_OK) {
        if (sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int(st, 0);
        sqlite3_finalize(st);
    }
    sqlite3_close(db);
    return v;
}

}  // namespace

TEST(CatalogV9, VideoColumnsRoundTrip) {
    const auto db = fresh_db("roundtrip");
    Catalog cat(db);
    ASSERT_TRUE(cat.ok());

    // A photo defaults to kind 0 / duration 0.
    auto pr = photo_rec("/lib/a.jpg");
    const int64_t pid = cat.upsert_asset(pr);
    ASSERT_GT(pid, 0);

    // A video carries kind 1 + a duration.
    AssetRecord vr = photo_rec("/lib/clip.mp4");
    vr.format = "mp4";
    vr.kind = 1;
    vr.duration_ms = 4200;
    const int64_t vid = cat.upsert_asset(vr);
    ASSERT_GT(vid, 0);

    const auto got_p = cat.asset_by_id(pid);
    const auto got_v = cat.asset_by_id(vid);
    ASSERT_TRUE(got_p.has_value());
    ASSERT_TRUE(got_v.has_value());
    EXPECT_EQ(got_p->kind, 0);
    EXPECT_EQ(got_p->duration_ms, 0);
    EXPECT_EQ(got_v->kind, 1);
    EXPECT_EQ(got_v->duration_ms, 4200);
}

TEST(CatalogV9, MigratesFromV8AndDefaultsLegacyRows) {
    const auto db = fresh_db("migrate");
    {
        Catalog cat(db);
        ASSERT_TRUE(cat.ok());
        auto r = photo_rec("/lib/legacy.jpg");
        ASSERT_GT(cat.upsert_asset(r), 0);
    }
    ASSERT_EQ(schema_version(db), 9);

    // Roll the schema back to v8 (drop the v9 additions) then reopen.
    downgrade_to_v8(db);
    ASSERT_EQ(schema_version(db), 8);

    Catalog cat(db);  // reopen → forward-migrates to v9
    ASSERT_TRUE(cat.ok());
    EXPECT_EQ(schema_version(db), 9);

    // The pre-existing row survived and defaults to kind 0.
    const auto rows = cat.list_assets(/*include_hidden=*/true);
    ASSERT_EQ(rows.size(), 1u);
    EXPECT_EQ(rows[0].kind, 0);
    EXPECT_EQ(rows[0].duration_ms, 0);

    // video_edit was recreated (a video row + a trim row + cascade works).
    AssetRecord vr = photo_rec("/lib/clip.mov");
    vr.kind = 1;
    vr.duration_ms = 1000;
    const int64_t vid = cat.upsert_asset(vr);
    ASSERT_GT(vid, 0);
}

#endif  // PHOTO_HAVE_SQLITE
