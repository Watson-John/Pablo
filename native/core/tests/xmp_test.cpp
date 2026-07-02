// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// xmp_test.cpp — the MWG face-region XMP writer/parser (pure; always built).

#include <gtest/gtest.h>

#include <cmath>

#include "xmp/face_xmp.h"

using photo::xmp::FaceRegion;
using photo::xmp::build_face_regions_xmp;
using photo::xmp::parse_face_regions;

TEST(FaceXmp, BuildContainsSchemaAndDimensions) {
    std::vector<FaceRegion> regs = {{"Ada Lovelace", 0.5, 0.4, 0.2, 0.25}};
    const std::string doc = build_face_regions_xmp(4000, 3000, regs);
    ASSERT_FALSE(doc.empty());
    EXPECT_NE(doc.find("metadataworkinggroup.com/schemas/regions"), std::string::npos);
    EXPECT_NE(doc.find("stDim:w=\"4000\""), std::string::npos);
    EXPECT_NE(doc.find("stDim:h=\"3000\""), std::string::npos);
    EXPECT_NE(doc.find("<mwg-rs:Type>Face</mwg-rs:Type>"), std::string::npos);
    EXPECT_NE(doc.find("Ada Lovelace"), std::string::npos);
}

TEST(FaceXmp, RoundTripsMultipleRegions) {
    std::vector<FaceRegion> regs = {
        {"Grace Hopper", 0.25, 0.30, 0.10, 0.12},
        {"Alan Turing", 0.70, 0.55, 0.15, 0.18},
    };
    const std::string doc = build_face_regions_xmp(2000, 1500, regs);
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), 2u);
    EXPECT_EQ(parsed[0].name, "Grace Hopper");
    EXPECT_NEAR(parsed[0].cx, 0.25, 1e-4);
    EXPECT_NEAR(parsed[0].cy, 0.30, 1e-4);
    EXPECT_NEAR(parsed[0].w, 0.10, 1e-4);
    EXPECT_NEAR(parsed[0].h, 0.12, 1e-4);
    EXPECT_EQ(parsed[1].name, "Alan Turing");
    EXPECT_NEAR(parsed[1].cx, 0.70, 1e-4);
}

TEST(FaceXmp, EscapesXmlSpecialCharsInName) {
    std::vector<FaceRegion> regs = {{"Tom & \"Jerry\" <b>", 0.5, 0.5, 0.1, 0.1}};
    const std::string doc = build_face_regions_xmp(100, 100, regs);
    // Raw specials must not appear unescaped inside the Name element region.
    EXPECT_NE(doc.find("&amp;"), std::string::npos);
    EXPECT_NE(doc.find("&quot;"), std::string::npos);
    EXPECT_NE(doc.find("&lt;b&gt;"), std::string::npos);
    // And they must decode back to the original.
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), 1u);
    EXPECT_EQ(parsed[0].name, "Tom & \"Jerry\" <b>");
}

TEST(FaceXmp, RejectsBadDimensions) {
    EXPECT_TRUE(build_face_regions_xmp(0, 100, {{"x", .5, .5, .1, .1}}).empty());
    EXPECT_TRUE(build_face_regions_xmp(100, -1, {{"x", .5, .5, .1, .1}}).empty());
}

TEST(FaceXmp, EmptyRegionListStillValidDoc) {
    const std::string doc = build_face_regions_xmp(640, 480, {});
    ASSERT_FALSE(doc.empty());
    EXPECT_TRUE(parse_face_regions(doc).empty());
}
