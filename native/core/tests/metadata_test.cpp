// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// metadata_test.cpp — the asset_metadata storage round-trip and the libexif
// extractor's robustness on non-EXIF input. (Real-EXIF extraction is verified
// against actual photos; crafting a known-EXIF fixture in C++ is a follow-up.)

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <fstream>
#include <string>

#include "catalog/catalog.h"
#include "exif/exif.h"
#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;
using photo::exif::AssetMetadata;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_meta_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(Metadata, CatalogRoundTripAndGeotagged) {
    Catalog cat(fresh_db("rt"));

    AssetMetadata m;
    m.camera = "TestCam X1";
    m.lens = "50mm f/1.8";
    m.aperture = "f/2.8";
    m.shutter = "1/250 sec";
    m.focal = "50.0 mm";
    m.iso = 400;
    m.datetime_unix = 1700000000;
    m.orientation = 6;
    m.width = 4000;
    m.height = 3000;
    m.has_gps = true;
    m.gps_lat = 37.7749;
    m.gps_lon = -122.4194;
    cat.upsert_metadata(42, m);

    auto got = cat.get_metadata(42);
    ASSERT_TRUE(got.has_value());
    EXPECT_EQ(got->camera, "TestCam X1");
    EXPECT_EQ(got->aperture, "f/2.8");
    EXPECT_EQ(got->iso, 400);
    EXPECT_EQ(got->orientation, 6);
    EXPECT_EQ(got->datetime_unix, 1700000000);
    ASSERT_TRUE(got->has_gps);
    EXPECT_NEAR(got->gps_lat, 37.7749, 1e-6);
    EXPECT_NEAR(got->gps_lon, -122.4194, 1e-6);

    auto geo = cat.geotagged();
    ASSERT_EQ(geo.size(), 1u);
    EXPECT_EQ(geo[0].asset_id, 42);
    EXPECT_NEAR(geo[0].lat, 37.7749, 1e-6);
    EXPECT_NEAR(geo[0].lon, -122.4194, 1e-6);

    // Upsert again — same row refreshed, no duplicate.
    m.iso = 800;
    cat.upsert_metadata(42, m);
    EXPECT_EQ(cat.get_metadata(42)->iso, 800);
    EXPECT_EQ(cat.geotagged().size(), 1u);
}

TEST(Metadata, GetMissingIsNullopt) {
    Catalog cat(fresh_db("missing"));
    EXPECT_FALSE(cat.get_metadata(999).has_value());
    EXPECT_TRUE(cat.geotagged().empty());
}

TEST(Metadata, ExtractNonExifReturnsEmpty) {
    auto dir = fs::temp_directory_path() / "photo_meta_extract";
    fs::remove_all(dir);
    fs::create_directories(dir);
    auto p = (dir / "x.jpg").string();
    std::ofstream(p, std::ios::binary) << "not a real jpeg";

    auto m = photo::exif::extract(p);
    EXPECT_TRUE(m.camera.empty());
    EXPECT_FALSE(m.has_gps);
    EXPECT_EQ(m.iso, 0);
}

// Engine → catalog → list_geotagged, the path the map's C ABI uses.
TEST(Metadata, EngineListGeotagged) {
    auto dir = fs::temp_directory_path() / "photo_meta_engine_geo";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const auto db = (dir / "pablo.db").string();
    const auto cache = (dir / "cache").string();

    photo_config_t cfg{};
    cfg.catalog_path_utf8 = db.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    auto eng = photo::Engine::create(cfg);
    ASSERT_NE(eng, nullptr);
    ASSERT_NE(eng->catalog(), nullptr);

    AssetMetadata m;
    m.has_gps = true;
    m.gps_lat = 51.5074;
    m.gps_lon = -0.1278;
    eng->catalog()->upsert_metadata(7, m);

    auto geo = eng->list_geotagged();
    ASSERT_EQ(geo.size(), 1u);
    EXPECT_EQ(geo[0].asset_id, 7);
    EXPECT_NEAR(geo[0].lat, 51.5074, 1e-9);
    EXPECT_NEAR(geo[0].lon, -0.1278, 1e-9);
}

#endif  // PHOTO_HAVE_SQLITE
