// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// exif_extract_test.cpp — the real libexif extractor (native/core/src/exif/
// exif.cpp), the §5 "EXIF/IPTC read … integ (vs exiftool)" cell.
//
// Two halves:
//   1. Robustness — extract() must never throw and must return an empty struct
//      for non-EXIF, missing, truncated, or directory inputs. These run in every
//      build (with libexif the path is real; without it extract() self-stubs to
//      {} and the expectations still hold).
//   2. Ground-truth cross-check (PHOTO_HAVE_EXIF only) — against
//      native/core/tests/fixtures/exif_full.jpg, whose tags were *baked by
//      exiftool* (see make_exif_fixture.py). The committed exif_full.golden.json
//      records those baked values; the expected constants below are kept in
//      lockstep with it (SPEC-05 §3.1) — they are not parsed at runtime so the
//      test stays dependency-free. Asserting our reader recovers exiftool's
//      values is the interop check. Also pins the DECISIONS-D1 invariant:
//      extraction is read-only — it never writes the file.

#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>

#include "exif/exif.h"

namespace fs = std::filesystem;

#ifndef PHOTO_TEST_FIXTURES_DIR
#define PHOTO_TEST_FIXTURES_DIR "."
#endif

namespace {
std::string fixture(const char* name) {
    return (fs::path(PHOTO_TEST_FIXTURES_DIR) / name).string();
}
std::string read_all(const std::string& p) {
    std::ifstream f(p, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(f), {});
}
fs::path scratch(const char* tag) {
    auto d = fs::temp_directory_path() / ("photo_exif_extract_" + std::string(tag));
    fs::remove_all(d);
    fs::create_directories(d);
    return d;
}
}  // namespace

// ── Robustness (build-config independent) ───────────────────────────────────

TEST(Exif, NonExifFileReturnsEmpty) {
    const auto p = (scratch("nonexif") / "x.jpg").string();
    std::ofstream(p, std::ios::binary) << "not a real jpeg, no EXIF here";
    auto m = photo::exif::extract(p);
    EXPECT_TRUE(m.camera.empty());
    EXPECT_FALSE(m.has_gps);
    EXPECT_EQ(m.iso, 0);
    EXPECT_EQ(m.orientation, 1);  // documented default
    EXPECT_EQ(m.datetime_unix, 0);
}

TEST(Exif, MissingFileReturnsEmpty) {
    auto m = photo::exif::extract("/no/such/file/at/all.jpg");
    EXPECT_TRUE(m.camera.empty());
    EXPECT_FALSE(m.has_gps);
}

TEST(Exif, DirectoryPathReturnsEmpty) {
    auto m = photo::exif::extract(fs::temp_directory_path().string());
    EXPECT_TRUE(m.camera.empty());
    EXPECT_FALSE(m.has_gps);
}

TEST(Exif, TruncatedExifHeaderDoesNotCrash) {
    const auto p = (scratch("trunc") / "t.jpg").string();
    // JPEG SOI + an APP1/"Exif" marker that promises more bytes than follow.
    const unsigned char bytes[] = {0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x20,
                                   'E',  'x',  'i',  'f',  0x00, 0x00};
    {
        std::ofstream f(p, std::ios::binary);
        f.write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
    }
    auto m = photo::exif::extract(p);  // must return, not crash/throw
    EXPECT_FALSE(m.has_gps);
}

// ── Ground-truth cross-check vs exiftool (libexif builds only) ───────────────

#ifdef PHOTO_HAVE_EXIF

class ExifFixture : public ::testing::Test {
 protected:
    const std::string path = fixture("exif_full.jpg");
    void SetUp() override {
        if (!fs::exists(path))
            GTEST_SKIP() << "fixture missing: " << path
                         << " — regenerate with native/core/tests/fixtures/"
                            "make_exif_fixture.py";
    }
};

TEST_F(ExifFixture, AllFieldsMatchBakedGroundTruth) {
    auto m = photo::exif::extract(path);
    EXPECT_EQ(m.camera, "TestMake PabloCam 100");  // trim(Make + " " + Model)
    EXPECT_EQ(m.lens, "TestLens 50mm F1.8");
    // The unit-bearing strings (aperture / shutter / focal) are libexif-
    // formatted: the exact rendering drifts across libexif versions ("1/250 sec"
    // vs "1/250 sec.", decimal/locale, etc.). Assert the stable numeric core so
    // the cross-check survives a libexif bump rather than pinning the cosmetics.
    EXPECT_NE(m.aperture.find("2.8"), std::string::npos) << "aperture=" << m.aperture;
    EXPECT_NE(m.shutter.find("1/250"), std::string::npos) << "shutter=" << m.shutter;
    EXPECT_NE(m.focal.find("50"), std::string::npos) << "focal=" << m.focal;
    EXPECT_EQ(m.iso, 400);
    EXPECT_EQ(m.orientation, 6);  // "Rotate 90 CW"
    EXPECT_EQ(m.width, 4000);     // PixelXDimension
    EXPECT_EQ(m.height, 3000);    // PixelYDimension
}

TEST_F(ExifFixture, DateTimeOriginalParsedAsUtcSeconds) {
    // exif.cpp's parse_datetime treats "2021:07:15 12:30:45" as naive UTC.
    EXPECT_EQ(photo::exif::extract(path).datetime_unix, 1626352245);
}

TEST_F(ExifFixture, GpsDecodedWithHemisphereSign) {
    auto m = photo::exif::extract(path);
    ASSERT_TRUE(m.has_gps);
    EXPECT_NEAR(m.gps_lat, 37.7749, 1e-4);    // N → positive
    EXPECT_NEAR(m.gps_lon, -122.4194, 1e-4);  // W → negative
}

// DECISIONS D1: user-authored metadata is catalog-only and originals are never
// written. Extraction in particular must be read-only.
TEST_F(ExifFixture, ExtractionDoesNotModifyTheFile) {
    // Operate on a scratch copy so a regression that wrote back would mutate a
    // throwaway file, never the committed fixture (which would silently perturb
    // the other ExifFixture cases).
    const auto copy = (scratch("readonly") / "copy.jpg").string();
    fs::copy_file(path, copy);
    const std::string before = read_all(copy);
    const auto mtime_before = fs::last_write_time(copy);
    (void)photo::exif::extract(copy);
    EXPECT_EQ(read_all(copy), before);                       // byte-identical
    EXPECT_TRUE(fs::last_write_time(copy) == mtime_before);  // mtime untouched
}

#endif  // PHOTO_HAVE_EXIF
