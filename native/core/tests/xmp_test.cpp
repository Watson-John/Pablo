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

// Precision contract: coordinates are serialized with %.6f (trailing zeros
// trimmed), so any value exactly representable at 6 decimal places round-trips
// EXACTLY (EXPECT_DOUBLE_EQ, not just NEAR). Finer values are quantized to the
// nearest 1e-6 — see SubMicroPrecisionQuantizesToNearestMillionth below.
TEST(FaceXmp, WriteRereadRoundTripIsExactAtSixDecimals) {
    const std::vector<FaceRegion> regs = {
        {"Katherine Johnson", 0.123456, 0.654321, 0.015625, 0.098765},
        {"Annie Easley",      0.5,      0.25,     0.1,      0.375},
        {"Mary Jackson",      0.000001, 0.999999, 0.111111, 0.222222},
    };
    const std::string doc = build_face_regions_xmp(6000, 4000, regs);
    ASSERT_FALSE(doc.empty());
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), regs.size());
    for (size_t i = 0; i < regs.size(); ++i) {
        EXPECT_EQ(parsed[i].name, regs[i].name) << "region " << i;
        EXPECT_DOUBLE_EQ(parsed[i].cx, regs[i].cx) << "region " << i;
        EXPECT_DOUBLE_EQ(parsed[i].cy, regs[i].cy) << "region " << i;
        EXPECT_DOUBLE_EQ(parsed[i].w,  regs[i].w)  << "region " << i;
        EXPECT_DOUBLE_EQ(parsed[i].h,  regs[i].h)  << "region " << i;
    }
}

TEST(FaceXmp, SubMicroPrecisionQuantizesToNearestMillionth) {
    const double third = 1.0 / 3.0;
    const std::string doc = build_face_regions_xmp(
        100, 100, {{"thirds", third, 2.0 / 3.0, 0.1, 0.1}});
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), 1u);
    EXPECT_DOUBLE_EQ(parsed[0].cx, 0.333333);  // quantized, not exact
    EXPECT_NEAR(parsed[0].cx, third, 5e-7);    // ...but within half a millionth
    EXPECT_DOUBLE_EQ(parsed[0].cy, 0.666667);  // rounds, does not truncate
}

TEST(FaceXmp, UnicodeAndApostropheNamesSurviveRoundTrip) {
    const std::vector<FaceRegion> regs = {
        {"José Müller-Łukasz", 0.2, 0.2, 0.1, 0.1},
        {"田中 太郎 (お父さん)", 0.6, 0.6, 0.2, 0.2},
        {"O'Brien & Sons", 0.8, 0.3, 0.1, 0.1},
    };
    const std::string doc = build_face_regions_xmp(800, 600, regs);
    // UTF-8 passes through byte-for-byte unescaped...
    EXPECT_NE(doc.find("José Müller-Łukasz"), std::string::npos);
    EXPECT_NE(doc.find("田中 太郎 (お父さん)"), std::string::npos);
    // ...while apostrophe and ampersand are escaped. The document skeleton uses
    // only double quotes, so no raw apostrophe may appear anywhere.
    EXPECT_NE(doc.find("O&apos;Brien &amp; Sons"), std::string::npos);
    EXPECT_EQ(doc.find('\''), std::string::npos);
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), 3u);
    EXPECT_EQ(parsed[0].name, "José Müller-Łukasz");
    EXPECT_EQ(parsed[1].name, "田中 太郎 (お父さん)");
    EXPECT_EQ(parsed[2].name, "O'Brien & Sons");
}

// Regression (bug found + fixed in face_xmp.cpp): a Name whose TEXT contains
// attribute-like tokens must not confuse the attribute scanner. find_attr()
// used to match "stArea:y" inside the escaped Name text and then grab the next
// quoted value anywhere downstream — the real stArea:x — so cy came back as
// cx's value. The scanner now requires `="` (whitespace-tolerant) right after
// the attribute name, which escaped text can never contain.
TEST(FaceXmp, AttributeTokensInsideNamesDoNotCorruptRects) {
    const std::vector<FaceRegion> regs = {
        {"stArea:y trap", 0.111111, 0.222222, 0.333333, 0.444444},
        {"evil stArea:x=\"0.9\" name", 0.555555, 0.666666, 0.077777, 0.088888},
    };
    const std::string doc = build_face_regions_xmp(1000, 1000, regs);
    const auto parsed = parse_face_regions(doc);
    ASSERT_EQ(parsed.size(), 2u);
    EXPECT_EQ(parsed[0].name, "stArea:y trap");
    EXPECT_DOUBLE_EQ(parsed[0].cx, 0.111111);
    EXPECT_DOUBLE_EQ(parsed[0].cy, 0.222222);  // was 0.111111 before the fix
    EXPECT_DOUBLE_EQ(parsed[0].w,  0.333333);
    EXPECT_DOUBLE_EQ(parsed[0].h,  0.444444);
    EXPECT_EQ(parsed[1].name, "evil stArea:x=\"0.9\" name");
    EXPECT_DOUBLE_EQ(parsed[1].cx, 0.555555);
    EXPECT_DOUBLE_EQ(parsed[1].cy, 0.666666);
    EXPECT_DOUBLE_EQ(parsed[1].w,  0.077777);
    EXPECT_DOUBLE_EQ(parsed[1].h,  0.088888);
}

TEST(FaceXmp, ParseOfDocumentsWithoutRegionsYieldsEmpty) {
    EXPECT_TRUE(parse_face_regions("").empty());
    EXPECT_TRUE(parse_face_regions("not xml at all").empty());
    // A well-formed third-party XMP sidecar that HAS rdf:li items (keywords)
    // but no mwg-rs face regions must not fabricate any.
    const std::string keywords_only =
        "<?xpacket begin=\"\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n"
        "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n"
        " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"
        "  <rdf:Description rdf:about=\"\""
        " xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
        "   <dc:subject><rdf:Bag>\n"
        "    <rdf:li>holiday</rdf:li>\n"
        "    <rdf:li>beach</rdf:li>\n"
        "   </rdf:Bag></dc:subject>\n"
        "  </rdf:Description>\n"
        " </rdf:RDF>\n"
        "</x:xmpmeta>\n";
    EXPECT_TRUE(parse_face_regions(keywords_only).empty());
}
