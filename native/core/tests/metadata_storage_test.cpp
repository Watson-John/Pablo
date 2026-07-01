// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// metadata_storage_test.cpp — the asset_metadata catalog round-trip, covering
// the fields metadata_test.cpp does not assert (lens / focal / shutter / width
// / height), signed S/W GPS coordinates, the has_gps gate on geotagged(),
// full-row overwrite on re-upsert, and UTF-8 string fields. (Real libexif
// extraction is in exif_extract_test.cpp.)

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>
#include <string>

#include "catalog/catalog.h"
#include "exif/exif.h"

namespace fs = std::filesystem;
using photo::catalog::Catalog;
using photo::exif::AssetMetadata;

namespace {
std::string fresh_db(const char* tag) {
    auto dir =
        fs::temp_directory_path() / ("photo_metadata_storage_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

AssetMetadata rich() {
    AssetMetadata m;
    m.camera = "Canon EOS R5";
    m.lens = "RF 24-70mm F2.8";
    m.aperture = "f/4.0";
    m.shutter = "1/125 sec";
    m.focal = "35.0 mm";
    m.iso = 200;
    m.datetime_unix = 1626352245;
    m.orientation = 8;
    m.width = 8192;
    m.height = 5464;
    return m;
}
}  // namespace

TEST(MetadataStorage, EveryFieldRoundTrips) {
    Catalog cat(fresh_db("all"));
    cat.upsert_metadata(5, rich());

    auto g = cat.get_metadata(5);
    ASSERT_TRUE(g.has_value());
    EXPECT_EQ(g->camera, "Canon EOS R5");
    EXPECT_EQ(g->lens, "RF 24-70mm F2.8");
    EXPECT_EQ(g->aperture, "f/4.0");
    EXPECT_EQ(g->shutter, "1/125 sec");
    EXPECT_EQ(g->focal, "35.0 mm");
    EXPECT_EQ(g->iso, 200);
    EXPECT_EQ(g->datetime_unix, 1626352245);
    EXPECT_EQ(g->orientation, 8);
    EXPECT_EQ(g->width, 8192);
    EXPECT_EQ(g->height, 5464);
    EXPECT_FALSE(g->has_gps);
}

TEST(MetadataStorage, SouthAndWestCoordinatesPersistWithSign) {
    Catalog cat(fresh_db("sw"));
    AssetMetadata sydney;  // southern latitude
    sydney.has_gps = true;
    sydney.gps_lat = -33.8688;
    sydney.gps_lon = 151.2093;
    cat.upsert_metadata(1, sydney);

    AssetMetadata nyc;  // western longitude
    nyc.has_gps = true;
    nyc.gps_lat = 40.7128;
    nyc.gps_lon = -74.0060;
    cat.upsert_metadata(2, nyc);

    EXPECT_NEAR(cat.get_metadata(1)->gps_lat, -33.8688, 1e-9);
    EXPECT_NEAR(cat.get_metadata(1)->gps_lon, 151.2093, 1e-9);
    EXPECT_NEAR(cat.get_metadata(2)->gps_lat, 40.7128, 1e-9);
    EXPECT_NEAR(cat.get_metadata(2)->gps_lon, -74.0060, 1e-9);
    EXPECT_EQ(cat.geotagged().size(), 2u);
}

TEST(MetadataStorage, HasGpsFalseIsExcludedFromGeotagged) {
    Catalog cat(fresh_db("nogeo"));
    AssetMetadata m;  // has_gps defaults false even though coords are set
    m.gps_lat = 10.0;
    m.gps_lon = 20.0;
    cat.upsert_metadata(1, m);
    EXPECT_TRUE(cat.get_metadata(1).has_value());  // the row exists…
    EXPECT_TRUE(cat.geotagged().empty());          // …but is not geotagged
}

TEST(MetadataStorage, ReUpsertOverwritesEveryFieldNotInserts) {
    Catalog cat(fresh_db("overwrite"));
    cat.upsert_metadata(1, rich());  // no GPS

    AssetMetadata m2;  // mostly-empty, now WITH gps
    m2.camera = "Nikon Z9";
    m2.iso = 6400;
    m2.has_gps = true;
    m2.gps_lat = 1.0;
    m2.gps_lon = 2.0;
    cat.upsert_metadata(1, m2);  // same asset_id (PK) → replace in place

    auto g = cat.get_metadata(1);
    ASSERT_TRUE(g.has_value());
    EXPECT_EQ(g->camera, "Nikon Z9");
    EXPECT_EQ(g->iso, 6400);
    EXPECT_EQ(g->lens, "");  // cleared by the second upsert's empty lens
    EXPECT_EQ(g->orientation, 1);  // m2's default
    EXPECT_TRUE(g->has_gps);
    EXPECT_EQ(cat.geotagged().size(), 1u);  // overwrite, not a second row
}

TEST(MetadataStorage, Utf8CameraAndLensRoundTrip) {
    Catalog cat(fresh_db("utf8"));
    AssetMetadata m;
    m.camera = "Nikon 日本 Z";
    m.lens = "Nikkor 50mm — naïve";
    cat.upsert_metadata(3, m);
    auto g = cat.get_metadata(3);
    ASSERT_TRUE(g.has_value());
    EXPECT_EQ(g->camera, "Nikon 日本 Z");
    EXPECT_EQ(g->lens, "Nikkor 50mm — naïve");
}

TEST(MetadataStorage, GetMissingIsNullopt) {
    Catalog cat(fresh_db("missing"));
    EXPECT_FALSE(cat.get_metadata(404).has_value());
}

#endif  // PHOTO_HAVE_SQLITE
