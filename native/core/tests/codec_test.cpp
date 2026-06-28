// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// codec_test.cpp — decode_bgr basics. The standalone build has no libvips, so
// this exercises the cv::imread fallback; the libvips path (HEIC/RAW/JXL/TIFF)
// is verified against real fixtures.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_FACES

#include <filesystem>
#include <fstream>
#include <string>

#include <opencv2/imgcodecs.hpp>

#include "codec/codec.h"

namespace fs = std::filesystem;

namespace {
fs::path fresh(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_codec_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return dir;
}
}  // namespace

TEST(Codec, DecodesToFullResBgr) {
    const auto p = (fresh("png") / "x.png").string();
    // 30x20 solid blue, written as BGR.
    cv::Mat src(20, 30, CV_8UC3, cv::Scalar(255, 0, 0));
    ASSERT_TRUE(cv::imwrite(p, src));

    cv::Mat got = photo::codec::decode_bgr(p);
    ASSERT_FALSE(got.empty());
    EXPECT_EQ(got.rows, 20);
    EXPECT_EQ(got.cols, 30);
    EXPECT_EQ(got.type(), CV_8UC3);
    const auto px = got.at<cv::Vec3b>(0, 0);
    EXPECT_GT(px[0], 200);  // B high
    EXPECT_LT(px[2], 60);   // R low
}

TEST(Codec, EmptyOnUnreadable) {
    const auto p = (fresh("bad") / "x.png").string();
    std::ofstream(p, std::ios::binary) << "not an image";
    EXPECT_TRUE(photo::codec::decode_bgr(p).empty());

    EXPECT_TRUE(photo::codec::decode_bgr("/no/such/file.jpg").empty());
}

#endif  // PHOTO_HAVE_FACES
