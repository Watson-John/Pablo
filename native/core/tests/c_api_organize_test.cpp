// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// c_api_organize_test.cpp — the C ABI surface the Dart FFI drives for §5
// Organize & metadata: photo_asset_set_starred / _set_rating / _set_caption,
// the photo_asset_organize read-back, photo_asset_{add,remove}_tag +
// photo_asset_tags (the NUL-separated grow-and-recall buffer protocol), and
// photo_asset_metadata. Exercises them against a REAL engine handle — the same
// reinterpret_cast the c_api layer uses internally — and pins the status-code
// contracts (OK / NOT_FOUND / INVALID_ARG), null-arg guards, and the fixed
// buffer's truncation behavior.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_SQLITE

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include "catalog/catalog.h"
#include "exif/exif.h"
#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::catalog::AssetRecord;

namespace {
// Decode the NUL-separated UTF-8 buffer photo_asset_tags fills.
std::vector<std::string> decode_nul_list(const char* buf, size_t n) {
    std::vector<std::string> out;
    for (size_t i = 0; i < n;) {
        std::string s(buf + i);  // up to the next NUL
        i += s.size() + 1;
        out.push_back(std::move(s));
    }
    return out;
}
}  // namespace

// A real engine + one seeded asset. The handle is the reinterpret_cast the c_api
// layer performs on its opaque photo_engine_t*, so the C functions operate on
// the same engine/catalog we seed through.
class CApiOrganize : public ::testing::Test {
 protected:
    std::unique_ptr<photo::Engine> eng_;
    photo_engine_t* h_ = nullptr;
    int64_t asset_ = 0;
    std::string dir_;

    void SetUp() override {
        auto d = fs::temp_directory_path() /
                 ("photo_capi_org_" +
                  std::to_string(reinterpret_cast<uintptr_t>(this)));
        fs::remove_all(d);
        fs::create_directories(d);
        dir_ = d.string();
        const std::string db = (d / "pablo.db").string();
        const std::string cache = (d / "cache").string();

        photo_config_t cfg{};
        cfg.catalog_path_utf8 = db.c_str();
        cfg.cache_path_utf8 = cache.c_str();
        eng_ = photo::Engine::create(cfg);
        ASSERT_NE(eng_, nullptr);
        ASSERT_NE(eng_->catalog(), nullptr);
        h_ = reinterpret_cast<photo_engine_t*>(eng_.get());

        AssetRecord r;
        r.path = (d / "a.jpg").string();
        r.filename = "a.jpg";
        r.format = "jpeg";
        asset_ = eng_->catalog()->upsert_asset(r);
        ASSERT_GT(asset_, 0);
    }

    void TearDown() override {
        eng_.reset();  // joins engine threads before we delete the dir
        if (!dir_.empty()) fs::remove_all(dir_);
    }
};

TEST_F(CApiOrganize, StarRatingCaptionRoundTripViaOrganizeGetter) {
    EXPECT_EQ(photo_asset_set_starred(h_, asset_, 1), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_set_rating(h_, asset_, 4), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_set_caption(h_, asset_, "golden hour"), PHOTO_STATUS_OK);

    photo_organize_t org{};
    ASSERT_EQ(photo_asset_organize(h_, asset_, &org), PHOTO_STATUS_OK);
    EXPECT_EQ(org.starred, 1);
    EXPECT_EQ(org.rating, 4);
    EXPECT_STREQ(org.caption, "golden hour");

    EXPECT_EQ(photo_asset_set_starred(h_, asset_, 0), PHOTO_STATUS_OK);
    ASSERT_EQ(photo_asset_organize(h_, asset_, &org), PHOTO_STATUS_OK);
    EXPECT_EQ(org.starred, 0);
}

TEST_F(CApiOrganize, OrganizeUnknownAssetIsNotFound) {
    photo_organize_t org{};
    EXPECT_EQ(photo_asset_organize(h_, 999999, &org), PHOTO_STATUS_NOT_FOUND);
}

TEST_F(CApiOrganize, NullArgumentsRejected) {
    photo_organize_t org{};
    EXPECT_EQ(photo_asset_organize(nullptr, asset_, &org), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_organize(h_, asset_, nullptr), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_set_starred(nullptr, asset_, 1), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_set_rating(nullptr, asset_, 1), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_set_caption(nullptr, asset_, "x"), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_metadata(nullptr, asset_, nullptr), PHOTO_STATUS_INVALID_ARG);
}

TEST_F(CApiOrganize, CaptionTruncatedSafelyToBuffer) {
    const std::string big(1000, 'x');  // longer than photo_organize_t::caption[512]
    EXPECT_EQ(photo_asset_set_caption(h_, asset_, big.c_str()), PHOTO_STATUS_OK);

    photo_organize_t org{};
    ASSERT_EQ(photo_asset_organize(h_, asset_, &org), PHOTO_STATUS_OK);
    // snprintf into caption[512] writes at most 511 bytes + a guaranteed NUL.
    EXPECT_EQ(std::strlen(org.caption), 511u);
    EXPECT_EQ(org.caption[511], '\0');
    // (The full caption is still intact in the catalog — only the ABI view is
    // bounded — so the asset row's own caption is unbounded; not asserted here.)
}

TEST_F(CApiOrganize, AddTagRejectsEmptyAndNull) {
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, ""), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, nullptr), PHOTO_STATUS_INVALID_ARG);
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, "ok"), PHOTO_STATUS_OK);
}

TEST_F(CApiOrganize, TagsNulSeparatedTwoPassAndCapTruncation) {
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, "alpha"), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, "beta"), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, "gamma"), PHOTO_STATUS_OK);

    // tags_for_asset is sorted → "alpha\0beta\0gamma\0" = 6 + 5 + 6 = 17 bytes.
    const size_t need = photo_asset_tags(h_, asset_, nullptr, 0);
    EXPECT_EQ(need, 17u);

    std::vector<char> buf(need, '\1');
    const size_t got = photo_asset_tags(h_, asset_, buf.data(), buf.size());
    EXPECT_EQ(got, need);
    EXPECT_EQ(decode_nul_list(buf.data(), need),
              (std::vector<std::string>{"alpha", "beta", "gamma"}));

    // A cap too small for the second tag must stop on a tag boundary — never
    // split a tag — while still reporting the full size needed.
    std::vector<char> small(8, '\1');  // "alpha\0" (6) fits; "beta\0" would not
    const size_t total = photo_asset_tags(h_, asset_, small.data(), small.size());
    EXPECT_EQ(total, 17u);
    EXPECT_STREQ(small.data(), "alpha");
}

TEST_F(CApiOrganize, RemoveTagAndEmptyListReportsZero) {
    EXPECT_EQ(photo_asset_add_tag(h_, asset_, "solo"), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_remove_tag(h_, asset_, "solo"), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_tags(h_, asset_, nullptr, 0), 0u);
    // Removing a tag the asset never had is still OK (idempotent).
    EXPECT_EQ(photo_asset_remove_tag(h_, asset_, "never"), PHOTO_STATUS_OK);
}

TEST_F(CApiOrganize, MetadataOkNotFoundAndInvalid) {
    photo_metadata_t md{};
    // The asset exists but has no metadata row yet.
    EXPECT_EQ(photo_asset_metadata(h_, asset_, &md), PHOTO_STATUS_NOT_FOUND);

    photo::exif::AssetMetadata m;
    m.camera = "Leica M11";
    m.lens = "APO-Summicron 35mm";
    m.aperture = "f/1.4";
    m.shutter = "1/60 sec";
    m.focal = "35.0 mm";
    m.iso = 64;
    m.datetime_unix = 1626352245;
    m.orientation = 3;
    m.width = 9528;
    m.height = 6328;
    m.has_gps = true;
    m.gps_lat = 48.8566;
    m.gps_lon = 2.3522;
    eng_->catalog()->upsert_metadata(asset_, m);

    ASSERT_EQ(photo_asset_metadata(h_, asset_, &md), PHOTO_STATUS_OK);
    EXPECT_EQ(md.asset_id, static_cast<uint64_t>(asset_));
    EXPECT_STREQ(md.camera, "Leica M11");
    EXPECT_STREQ(md.lens, "APO-Summicron 35mm");
    EXPECT_STREQ(md.aperture, "f/1.4");
    EXPECT_STREQ(md.shutter, "1/60 sec");
    EXPECT_STREQ(md.focal, "35.0 mm");
    EXPECT_EQ(md.iso, 64);
    EXPECT_EQ(md.datetime_unix, 1626352245);
    EXPECT_EQ(md.orientation, 3);
    EXPECT_EQ(md.width, 9528);
    EXPECT_EQ(md.height, 6328);
    EXPECT_EQ(md.has_gps, 1);
    EXPECT_NEAR(md.gps_lat, 48.8566, 1e-9);
    EXPECT_NEAR(md.gps_lon, 2.3522, 1e-9);

    EXPECT_EQ(photo_asset_metadata(h_, asset_, nullptr), PHOTO_STATUS_INVALID_ARG);
}

#endif  // PHOTO_HAVE_SQLITE
