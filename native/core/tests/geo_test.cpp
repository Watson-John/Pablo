// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// geo_test.cpp — manual geotag overrides: precedence over EXIF GPS, survival of
// a metadata refresh, and the geotagged() union that drives the map.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <map>
#include <string>
#include <utility>

#include "catalog/catalog.h"
#include "exif/exif.h"
#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;
using photo::exif::AssetMetadata;

namespace {
std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_geo_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}
}  // namespace

TEST(ManualGeo, SetClearAndRead) {
    Catalog cat(fresh_db("setclear"));
    EXPECT_FALSE(cat.geo_override_for(5).has_value());

    cat.set_geo_override(5, 48.8566, 2.3522);  // Paris
    auto o = cat.geo_override_for(5);
    ASSERT_TRUE(o.has_value());
    EXPECT_NEAR(o->lat, 48.8566, 1e-9);
    EXPECT_NEAR(o->lon, 2.3522, 1e-9);

    // Re-set is an upsert (no duplicate, new value).
    cat.set_geo_override(5, 40.0, -3.0);
    EXPECT_NEAR(cat.geo_override_for(5)->lat, 40.0, 1e-9);

    cat.clear_geo_override(5);
    EXPECT_FALSE(cat.geo_override_for(5).has_value());
}

TEST(ManualGeo, OverrideBeatsExifInGeotagged) {
    Catalog cat(fresh_db("beats"));

    // Asset 1 has EXIF GPS only.
    AssetMetadata m;
    m.has_gps = true;
    m.gps_lat = 10.0;
    m.gps_lon = 20.0;
    cat.upsert_metadata(1, m);

    // Asset 2 has EXIF GPS *and* a manual override — the override wins.
    cat.upsert_metadata(2, m);
    cat.set_geo_override(2, 51.5, -0.12);

    // Asset 3 has no EXIF GPS, only a manual override.
    cat.set_geo_override(3, -33.87, 151.21);

    auto geo = cat.geotagged();
    ASSERT_EQ(geo.size(), 3u);
    // Collect into a map for order-independent assertions.
    std::map<int64_t, std::pair<double, double>> by_id;
    for (const auto& g : geo) by_id[g.asset_id] = {g.lat, g.lon};

    ASSERT_EQ(by_id.count(1), 1u);
    EXPECT_NEAR(by_id[1].first, 10.0, 1e-9);      // EXIF
    ASSERT_EQ(by_id.count(2), 1u);
    EXPECT_NEAR(by_id[2].first, 51.5, 1e-9);      // override, not 10.0
    EXPECT_NEAR(by_id[2].second, -0.12, 1e-9);
    ASSERT_EQ(by_id.count(3), 1u);
    EXPECT_NEAR(by_id[3].first, -33.87, 1e-9);    // override-only

    // geo_for_asset resolves the same precedence.
    EXPECT_NEAR(cat.geo_for_asset(2)->lat, 51.5, 1e-9);
    EXPECT_NEAR(cat.geo_for_asset(1)->lat, 10.0, 1e-9);
    EXPECT_FALSE(cat.geo_for_asset(999).has_value());
}

TEST(ManualGeo, OverrideSurvivesMetadataRefresh) {
    Catalog cat(fresh_db("survives"));
    cat.set_geo_override(8, 35.68, 139.69);  // Tokyo, set by hand

    // A rescan refreshes asset_metadata from the file (no GPS on this one).
    AssetMetadata m;  // has_gps == false
    m.camera = "NoGPS Cam";
    cat.upsert_metadata(8, m);

    // The manual point still drives the map.
    auto geo = cat.geotagged();
    ASSERT_EQ(geo.size(), 1u);
    EXPECT_EQ(geo[0].asset_id, 8);
    EXPECT_NEAR(geo[0].lat, 35.68, 1e-9);
}

TEST(ManualGeo, RejectsOutOfRangeViaCApi) {
    auto dir = fs::temp_directory_path() / "photo_geo_capi";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const auto db = (dir / "pablo.db").string();
    const auto cache = (dir / "cache").string();

    photo_config_t cfg{};
    cfg.catalog_path_utf8 = db.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    auto eng = photo::Engine::create(cfg);
    ASSERT_NE(eng, nullptr);
    auto* h = reinterpret_cast<photo_engine_t*>(eng.get());

    EXPECT_EQ(photo_asset_set_geo(h, 1, 95.0, 0.0), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_set_geo(h, 1, 0.0, 200.0), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_set_geo(h, 1, 45.0, 45.0), PHOTO_STATUS_OK);
    ASSERT_EQ(eng->list_geotagged().size(), 1u);
    EXPECT_EQ(photo_asset_clear_geo(h, 1), PHOTO_STATUS_OK);
    EXPECT_TRUE(eng->list_geotagged().empty());
}

#endif  // PHOTO_HAVE_SQLITE
