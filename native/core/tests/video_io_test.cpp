// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// video_io_test.cpp — the §11 FFmpeg video module. is_video_path() is pure and
// always tested; probe()/poster_frame() are exercised against a tiny committed
// fixture only when the build linked FFmpeg (PHOTO_HAVE_FFMPEG). Regenerate the
// fixture with:
//   ffmpeg -y -f lavfi -i testsrc=size=64x48:rate=10:duration=2 \
//     -c:v libx264 -pix_fmt yuv420p -g 5 native/core/tests/data/tiny.mp4

#include <gtest/gtest.h>

#include <filesystem>
#include <numeric>
#include <string>

#include "video/video_io.h"

namespace {
std::string fixture(const char* name) {
    return std::string(PHOTO_TEST_DATA_DIR) + "/" + name;
}
}  // namespace

TEST(VideoIsPath, RecognizesVideoExtensionsCaseInsensitively) {
    using photo::video::is_video_path;
    EXPECT_TRUE(is_video_path("/a/b.mp4"));
    EXPECT_TRUE(is_video_path("/a/b.MOV"));
    EXPECT_TRUE(is_video_path("clip.mkv"));
    EXPECT_TRUE(is_video_path("clip.webm"));
    EXPECT_FALSE(is_video_path("/a/b.jpg"));
    EXPECT_FALSE(is_video_path("/a/b.png"));
    EXPECT_FALSE(is_video_path("/a/mp4"));      // no dot
    EXPECT_FALSE(is_video_path("/a.mp4/b.jpg")); // dot before the last slash
}

#ifdef PHOTO_HAVE_FFMPEG

TEST(VideoProbe, ReadsDimsAndDuration) {
    const auto r = photo::video::probe(fixture("tiny.mp4"));
    ASSERT_TRUE(r.ok);
    EXPECT_EQ(r.width, 64);
    EXPECT_EQ(r.height, 48);
    EXPECT_NEAR(r.duration_ms, 2000, 150);
    EXPECT_EQ(r.codec, "h264");
}

TEST(VideoProbe, GarbageFileIsNotOk) {
    const auto r = photo::video::probe(fixture("does_not_exist.mp4"));
    EXPECT_FALSE(r.ok);
}

TEST(VideoPoster, DecodesBoundedPremultipliedFrame) {
    auto f = photo::video::poster_frame(fixture("tiny.mp4"), 32);
    ASSERT_NE(f, nullptr);
    EXPECT_GT(f->width, 0u);
    EXPECT_GT(f->height, 0u);
    // Bounded to 32 on the long edge (source 64x48 → 32x24).
    EXPECT_LE(f->width, 32u);
    EXPECT_LE(f->height, 32u);
    EXPECT_EQ(f->width, 32u);  // long edge hits the cap
    EXPECT_EQ(f->stride, f->width * 4);
    EXPECT_EQ(f->bgra.size(), static_cast<size_t>(f->stride) * f->height);
    // Opaque poster: every alpha byte is 255.
    for (size_t i = 3; i < f->bgra.size(); i += 4)
        ASSERT_EQ(f->bgra[i], 255);
    // testsrc is a colourful pattern, so the frame isn't a flat color.
    const uint64_t sum =
        std::accumulate(f->bgra.begin(), f->bgra.end(), uint64_t{0});
    EXPECT_GT(sum, 0u);
}

TEST(VideoPoster, IsDeterministicAcrossCalls) {
    auto a = photo::video::poster_frame(fixture("tiny.mp4"), 48);
    auto b = photo::video::poster_frame(fixture("tiny.mp4"), 48);
    ASSERT_NE(a, nullptr);
    ASSERT_NE(b, nullptr);
    EXPECT_EQ(a->width, b->width);
    EXPECT_EQ(a->height, b->height);
    EXPECT_EQ(a->bgra, b->bgra);  // same seek target → identical pixels
}

TEST(VideoPoster, GarbageFileReturnsNull) {
    EXPECT_EQ(photo::video::poster_frame(fixture("nope.mp4"), 32), nullptr);
}

TEST(VideoRemuxTrim, ProducesShorterClipSameCodec) {
    const std::string src = fixture("tiny.mp4");
    const auto probe0 = photo::video::probe(src);
    ASSERT_TRUE(probe0.ok);  // ~2000 ms source

    const std::string dst =
        (std::filesystem::temp_directory_path() / "pablo_trim_out.mp4").string();
    std::filesystem::remove(dst);
    // Keep [500, 1500) ≈ 1 s. Start snaps to a keyframe (GOP=5 @ 10fps = 0.5s),
    // so the exact duration can wobble by up to one GOP.
    ASSERT_TRUE(photo::video::remux_trim(src, dst, 500, 1500));
    ASSERT_TRUE(std::filesystem::exists(dst));

    const auto probe1 = photo::video::probe(dst);
    ASSERT_TRUE(probe1.ok);
    EXPECT_EQ(probe1.codec, probe0.codec);          // stream copy — no transcode
    EXPECT_LT(probe1.duration_ms, probe0.duration_ms);  // genuinely shorter
    EXPECT_NEAR(probe1.duration_ms, 1000, 600);     // ~1s ± a GOP
    // Stream copy shouldn't inflate the file.
    EXPECT_LE(std::filesystem::file_size(dst),
              std::filesystem::file_size(src) + 4096);
    std::filesystem::remove(dst);
}

TEST(VideoRemuxTrim, RejectsBadRange) {
    const std::string src = fixture("tiny.mp4");
    const std::string dst =
        (std::filesystem::temp_directory_path() / "pablo_trim_bad.mp4").string();
    EXPECT_FALSE(photo::video::remux_trim(src, dst, 1500, 500));  // end<start
    EXPECT_FALSE(photo::video::remux_trim("/nope.mp4", dst, 0, 100));
}

#else

TEST(VideoProbe, StubsWithoutFfmpeg) {
    EXPECT_FALSE(photo::video::probe(fixture("tiny.mp4")).ok);
    EXPECT_EQ(photo::video::poster_frame(fixture("tiny.mp4"), 32), nullptr);
}

#endif  // PHOTO_HAVE_FFMPEG
