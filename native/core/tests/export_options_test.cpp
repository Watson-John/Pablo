// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// export_options_test.cpp — Stage V1 export options: long-edge resize, jpeg
// quality, and the render-time text watermark, exercised at the Engine level
// (export_path2) and through the extern-C ABI (photo_asset_export2).
//
// Pixel assertions run on PNG outputs (lossless) so a comparison failure means
// the render changed, never that jpeg block artifacts moved. Quality ordering
// uses jpg (that's what [Q=] applies to).

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_VIPS

#include <vips/vips.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "photo_core.h"
#include "runtime/engine.h"
#include "thumb/thumb_service.h"

namespace fs = std::filesystem;
using namespace std::chrono;
using photo::ThumbService;

namespace {

fs::path fresh_dir(const char* tag) {
    auto d = fs::temp_directory_path() / ("photo_export_opts_" + std::string(tag));
    fs::remove_all(d);
    fs::create_directories(d);
    return d;
}

std::unique_ptr<photo::Engine> make_engine(const fs::path& dir) {
    const auto cat = (dir / "p.db").string();
    const auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return photo::Engine::create(cfg);
}

// Await PHOTO_EVT_EXPORT_COMPLETE for `req` on the C++ event ring.
bool wait_export(photo::Engine& eng, uint64_t req, int timeout_ms = 15000) {
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[32];
    while (steady_clock::now() < deadline) {
        const size_t n = eng.events().pop_n(buf, 32);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE &&
                buf[i].request_id == req)
                return buf[i].status == PHOTO_STATUS_OK;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return false;
}

// Mid-grey source so a white watermark is visible everywhere. Owned (copy).
VipsImage* grey_image(int w, int h) {
    std::vector<uint8_t> buf(static_cast<size_t>(w) * h * 3, 110);
    return vips_image_new_from_memory_copy(buf.data(), buf.size(), w, h, 3,
                                           VIPS_FORMAT_UCHAR);
}

std::string write_grey_src(const fs::path& dir, int w, int h,
                           const char* name = "src.png") {
    VipsImage* im = grey_image(w, h);
    const auto p = (dir / name).string();
    if (vips_image_write_to_file(im, p.c_str(), nullptr) != 0) vips_error_clear();
    g_object_unref(im);
    return p;
}

// Decoded, band-normalized pixels of an output file for exact comparisons.
struct Pix {
    int w = 0, h = 0;
    std::vector<uint8_t> rgb;  // 3 bands, row-major
    uint8_t at(int x, int y, int c) const {
        return rgb[(static_cast<size_t>(y) * w + x) * 3 + c];
    }
};

Pix read_pixels(const std::string& path) {
    Pix out;
    VipsImage* im = vips_image_new_from_file(path.c_str(), nullptr);
    if (im == nullptr) { vips_error_clear(); return out; }
    VipsImage* srgb = nullptr;
    if (vips_colourspace(im, &srgb, VIPS_INTERPRETATION_sRGB, nullptr) != 0) {
        vips_error_clear();
        g_object_unref(im);
        return out;
    }
    g_object_unref(im);
    if (vips_image_get_bands(srgb) != 3) {
        VipsImage* flat = nullptr;
        if (vips_extract_band(srgb, &flat, 0, "n", 3, nullptr) != 0) {
            vips_error_clear();
            g_object_unref(srgb);
            return out;
        }
        g_object_unref(srgb);
        srgb = flat;
    }
    out.w = vips_image_get_width(srgb);
    out.h = vips_image_get_height(srgb);
    size_t n = 0;
    auto* mem = static_cast<uint8_t*>(vips_image_write_to_memory(srgb, &n));
    g_object_unref(srgb);
    if (mem == nullptr) return Pix{};
    out.rgb.assign(mem, mem + n);
    g_free(mem);
    return out;
}

// Max per-channel difference between two same-sized decodes over a region.
int region_max_diff(const Pix& a, const Pix& b, int x0, int y0, int w, int h) {
    int worst = 0;
    for (int y = y0; y < y0 + h; ++y)
        for (int x = x0; x < x0 + w; ++x)
            for (int c = 0; c < 3; ++c)
                worst = std::max(worst, std::abs(static_cast<int>(a.at(x, y, c)) -
                                                 static_cast<int>(b.at(x, y, c))));
    return worst;
}

// Centroid of all pixels differing from `base` by more than `thresh`.
// Returns false when nothing differs.
bool diff_centroid(const Pix& a, const Pix& base, int thresh, double* cx,
                   double* cy) {
    double sx = 0, sy = 0;
    long count = 0;
    for (int y = 0; y < a.h; ++y)
        for (int x = 0; x < a.w; ++x)
            for (int c = 0; c < 3; ++c)
                if (std::abs(static_cast<int>(a.at(x, y, c)) -
                             static_cast<int>(base.at(x, y, c))) > thresh) {
                    sx += x; sy += y; ++count;
                    break;
                }
    if (count == 0) return false;
    *cx = sx / count;
    *cy = sy / count;
    return true;
}

ThumbService::ExportOptions wm_opts(const std::string& text, uint32_t argb,
                                    int anchor) {
    ThumbService::ExportOptions o;
    o.wm.text = text;
    o.wm.argb = argb;
    o.wm.anchor = anchor;
    o.wm.size = 0.12f;   // big enough to dominate a small test frame
    o.wm.margin = 0.04f;
    return o;
}

}  // namespace

// ── Resize ───────────────────────────────────────────────────────────────────

TEST(ExportOptions, ResizeBoundsLongEdgeAndPreservesAspect) {
    auto dir = fresh_dir("resize");
    const std::string src = write_grey_src(dir, 400, 200);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    ThumbService::ExportOptions o;
    o.max_dim = 100;
    const auto out = (dir / "out.png").string();
    const uint64_t req = eng->export_path2(src, out, "", o);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));

    const Pix p = read_pixels(out);
    EXPECT_EQ(p.w, 100);
    EXPECT_EQ(p.h, 50);
}

TEST(ExportOptions, ResizeNeverUpscales) {
    auto dir = fresh_dir("noupscale");
    const std::string src = write_grey_src(dir, 120, 80);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    ThumbService::ExportOptions o;
    o.max_dim = 4000;
    const auto out = (dir / "out.png").string();
    const uint64_t req = eng->export_path2(src, out, "", o);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));

    const Pix p = read_pixels(out);
    EXPECT_EQ(p.w, 120);
    EXPECT_EQ(p.h, 80);
}

TEST(ExportOptions, ResizeAppliesAfterGeometry) {
    // A 0.5-wide crop of a 400x200 source is 200x200; max_dim bounds THAT.
    auto dir = fresh_dir("resize_geo");
    const std::string src = write_grey_src(dir, 400, 200);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    ThumbService::ExportOptions o;
    o.max_dim = 64;
    const auto out = (dir / "out.png").string();
    const uint64_t req = eng->export_path2(src, out, "crop=0,0,0.5,1;", o);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));

    const Pix p = read_pixels(out);
    EXPECT_EQ(p.w, 64);
    EXPECT_EQ(p.h, 64);
}

// ── Quality ──────────────────────────────────────────────────────────────────

TEST(ExportOptions, JpegQualityOrdersFileSize) {
    auto dir = fresh_dir("quality");
    // Noise compresses badly, so quality separates file sizes decisively.
    std::vector<uint8_t> buf(240 * 160 * 3);
    uint32_t s = 0x12345678u;
    for (auto& v : buf) { s = s * 1664525u + 1013904223u; v = s >> 24; }
    VipsImage* im = vips_image_new_from_memory_copy(buf.data(), buf.size(), 240,
                                                    160, 3, VIPS_FORMAT_UCHAR);
    const std::string src = (dir / "src.png").string();
    ASSERT_EQ(vips_image_write_to_file(im, src.c_str(), nullptr), 0);
    g_object_unref(im);

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    ThumbService::ExportOptions lo, hi;
    lo.quality = 30;
    hi.quality = 90;
    const auto out_lo = (dir / "q30.jpg").string();
    const auto out_hi = (dir / "q90.jpg").string();
    // wait_export drains the shared ring, so serialize submit->wait pairs —
    // waiting on two in-flight requests would discard the other's event.
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, out_lo, "", lo)));
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, out_hi, "", hi)));

    EXPECT_LT(fs::file_size(out_lo), fs::file_size(out_hi));
}

// ── Watermark ────────────────────────────────────────────────────────────────

TEST(ExportOptions, WatermarkDrawsAtBottomRightOnly) {
    auto dir = fresh_dir("wm_br");
    const std::string src = write_grey_src(dir, 320, 200);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto base_out = (dir / "base.png").string();
    const auto wm_out = (dir / "wm.png").string();
    ThumbService::ExportOptions plain;
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, base_out, "", plain)));
    ASSERT_TRUE(wait_export(
        *eng,
        eng->export_path2(src, wm_out, "",
                          wm_opts("PABLO", 0xFFFFFFFFu,
                                  PHOTO_EXPORT_ANCHOR_BR))));

    const Pix base = read_pixels(base_out);
    const Pix wm = read_pixels(wm_out);
    ASSERT_EQ(base.w, wm.w);
    ASSERT_EQ(base.h, wm.h);
    // Bottom-right quadrant contains the text...
    EXPECT_GT(region_max_diff(wm, base, wm.w / 2, wm.h / 2, wm.w / 2, wm.h / 2),
              60);
    // ...and the top-left quadrant is untouched.
    EXPECT_EQ(region_max_diff(wm, base, 0, 0, wm.w / 2, wm.h / 2), 0);
}

TEST(ExportOptions, WatermarkAnchorsLandInTheirQuadrant) {
    auto dir = fresh_dir("wm_anchor");
    const std::string src = write_grey_src(dir, 320, 200);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto base_out = (dir / "base.png").string();
    ThumbService::ExportOptions plain;
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, base_out, "", plain)));
    const Pix base = read_pixels(base_out);

    struct Case { int anchor; bool right, bottom, centre; };
    const Case cases[] = {
        {PHOTO_EXPORT_ANCHOR_BR, true, true, false},
        {PHOTO_EXPORT_ANCHOR_BL, false, true, false},
        {PHOTO_EXPORT_ANCHOR_TR, true, false, false},
        {PHOTO_EXPORT_ANCHOR_TL, false, false, false},
        {PHOTO_EXPORT_ANCHOR_CENTER, false, false, true},
    };
    for (const Case& c : cases) {
        const auto out =
            (dir / ("wm_" + std::to_string(c.anchor) + ".png")).string();
        ASSERT_TRUE(wait_export(
            *eng, eng->export_path2(src, out, "",
                                    wm_opts("W", 0xFFFF2020u, c.anchor))));
        const Pix p = read_pixels(out);
        double cx = 0, cy = 0;
        ASSERT_TRUE(diff_centroid(p, base, 30, &cx, &cy))
            << "anchor " << c.anchor << " drew nothing";
        if (c.centre) {
            EXPECT_NEAR(cx, p.w / 2.0, p.w * 0.15) << "anchor " << c.anchor;
            EXPECT_NEAR(cy, p.h / 2.0, p.h * 0.15) << "anchor " << c.anchor;
        } else {
            EXPECT_EQ(cx > p.w / 2.0, c.right) << "anchor " << c.anchor;
            EXPECT_EQ(cy > p.h / 2.0, c.bottom) << "anchor " << c.anchor;
        }
    }
}

TEST(ExportOptions, WatermarkZeroAlphaIsInvisible) {
    auto dir = fresh_dir("wm_alpha0");
    const std::string src = write_grey_src(dir, 200, 140);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto base_out = (dir / "base.png").string();
    const auto wm_out = (dir / "wm.png").string();
    ThumbService::ExportOptions plain;
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, base_out, "", plain)));
    ASSERT_TRUE(wait_export(
        *eng,
        eng->export_path2(src, wm_out, "",
                          wm_opts("PABLO", 0x00FFFFFFu,
                                  PHOTO_EXPORT_ANCHOR_BR))));

    const Pix base = read_pixels(base_out);
    const Pix wm = read_pixels(wm_out);
    ASSERT_EQ(base.w, wm.w);
    ASSERT_EQ(base.h, wm.h);
    EXPECT_EQ(region_max_diff(wm, base, 0, 0, wm.w, wm.h), 0);
}

TEST(ExportOptions, DefaultOptionsMatchLegacyExport) {
    auto dir = fresh_dir("legacy_parity");
    const std::string src = write_grey_src(dir, 160, 120);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto legacy_out = (dir / "legacy.png").string();
    const auto opt_out = (dir / "opts.png").string();
    ThumbService::ExportOptions defaults;
    ASSERT_TRUE(wait_export(*eng, eng->export_path(src, legacy_out, "", 92)));
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, opt_out, "", defaults)));

    const Pix a = read_pixels(legacy_out);
    const Pix b = read_pixels(opt_out);
    ASSERT_EQ(a.w, b.w);
    ASSERT_EQ(a.h, b.h);
    EXPECT_EQ(region_max_diff(a, b, 0, 0, a.w, a.h), 0);
}

TEST(ExportOptions, ExifOrientationExportsUpright) {
    auto dir = fresh_dir("exif_orient");
    // 120x80 with EXIF orientation 6 (rotate 90 CW to display): decoders that
    // honour it (vips_thumbnail autorotates) show 80x120.
    VipsImage* im = grey_image(120, 80);
    VipsImage* tagged = nullptr;
    ASSERT_EQ(vips_copy(im, &tagged, nullptr), 0);
    g_object_unref(im);
    vips_image_set_int(tagged, VIPS_META_ORIENTATION, 6);
    const std::string src = (dir / "src.jpg").string();
    ASSERT_EQ(vips_image_write_to_file(tagged, src.c_str(), nullptr), 0);
    g_object_unref(tagged);

    // Precondition: the tag survived the round-trip (else the test is vacuous).
    VipsImage* reread = vips_image_new_from_file(src.c_str(), nullptr);
    ASSERT_NE(reread, nullptr);
    int orient = 0;
    if (vips_image_get_typeof(reread, VIPS_META_ORIENTATION))
        vips_image_get_int(reread, VIPS_META_ORIENTATION, &orient);
    g_object_unref(reread);
    if (orient != 6)
        GTEST_SKIP() << "jpegsave did not persist the orientation tag here";

    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);
    ThumbService::ExportOptions o;
    const auto out = (dir / "out.png").string();
    ASSERT_TRUE(wait_export(*eng, eng->export_path2(src, out, "", o)));

    const Pix p = read_pixels(out);
    EXPECT_EQ(p.w, 80);
    EXPECT_EQ(p.h, 120);
}

// ── The extern-C ABI ─────────────────────────────────────────────────────────

namespace {

photo_engine_t* make_engine_c(const fs::path& dir, std::string& cat_hold,
                              std::string& cache_hold) {
    cat_hold = (dir / "p.db").string();
    cache_hold = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat_hold.c_str();
    cfg.cache_path_utf8 = cache_hold.c_str();
    return photo_engine_create(&cfg);
}

// Await the export event through the C ABI; returns its status (INT32_MIN on
// timeout so status assertions fail loudly).
int32_t wait_export_status_c(photo_engine_t* eng, uint64_t req,
                             int timeout_ms = 15000) {
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[32];
    while (steady_clock::now() < deadline) {
        const size_t n = photo_poll_events(eng, buf, 32);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE &&
                buf[i].request_id == req)
                return buf[i].status;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return INT32_MIN;
}

}  // namespace

TEST(ExportCApi, NullOptsMatchesLegacyExport) {
    auto dir = fresh_dir("capi_null");
    const std::string src = write_grey_src(dir, 150, 100);
    std::string ch, cah;
    photo_engine_t* eng = make_engine_c(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    const auto legacy_out = (dir / "legacy.png").string();
    const auto null_out = (dir / "null_opts.png").string();
    const uint64_t r1 =
        photo_asset_export(eng, src.c_str(), legacy_out.c_str(), "", 92);
    ASSERT_GT(r1, 0u);
    EXPECT_EQ(wait_export_status_c(eng, r1), PHOTO_STATUS_OK);
    const uint64_t r2 = photo_asset_export2(eng, src.c_str(), null_out.c_str(),
                                            "", nullptr);
    ASSERT_GT(r2, 0u);
    EXPECT_NE(r1, r2);  // shared id counter, distinct requests
    EXPECT_EQ(wait_export_status_c(eng, r2), PHOTO_STATUS_OK);

    const Pix a = read_pixels(legacy_out);
    const Pix b = read_pixels(null_out);
    ASSERT_EQ(a.w, b.w);
    ASSERT_EQ(a.h, b.h);
    EXPECT_EQ(region_max_diff(a, b, 0, 0, a.w, a.h), 0);
    photo_engine_destroy(eng);
}

TEST(ExportCApi, OptionsResizeAndWatermarkThroughAbi) {
    auto dir = fresh_dir("capi_opts");
    const std::string src = write_grey_src(dir, 400, 200);
    std::string ch, cah;
    photo_engine_t* eng = make_engine_c(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    const auto base_out = (dir / "base.png").string();
    photo_export_options_t base{};
    base.max_dim = 128;
    const uint64_t r1 = photo_asset_export2(eng, src.c_str(), base_out.c_str(),
                                            "", &base);
    ASSERT_GT(r1, 0u);
    EXPECT_EQ(wait_export_status_c(eng, r1), PHOTO_STATUS_OK);
    const Pix pb = read_pixels(base_out);
    EXPECT_EQ(pb.w, 128);
    EXPECT_EQ(pb.h, 64);

    const auto wm_out = (dir / "wm.png").string();
    photo_export_options_t opts{};
    opts.max_dim = 128;
    opts.wm_argb = 0xFFFFFFFFu;
    opts.wm_size = 0.2f;
    opts.wm_anchor = PHOTO_EXPORT_ANCHOR_BR;
    std::snprintf(opts.wm_text, sizeof(opts.wm_text), "%s", "PABLO");
    const uint64_t r2 =
        photo_asset_export2(eng, src.c_str(), wm_out.c_str(), "", &opts);
    ASSERT_GT(r2, 0u);
    EXPECT_EQ(wait_export_status_c(eng, r2), PHOTO_STATUS_OK);

    const Pix pw = read_pixels(wm_out);
    ASSERT_EQ(pw.w, pb.w);
    ASSERT_EQ(pw.h, pb.h);
    // Watermark is sized against the 128px OUTPUT (0.2 * 64 ≈ 13px tall text),
    // present bottom-right, absent top-left.
    EXPECT_GT(region_max_diff(pw, pb, pw.w / 2, pw.h / 2, pw.w / 2, pw.h / 2),
              60);
    EXPECT_EQ(region_max_diff(pw, pb, 0, 0, pw.w / 2, pw.h / 2), 0);
    photo_engine_destroy(eng);
}

TEST(ExportCApi, BadSourceEmitsIoErrorEvent) {
    auto dir = fresh_dir("capi_bad");
    std::string ch, cah;
    photo_engine_t* eng = make_engine_c(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    const auto out = (dir / "out.jpg").string();
    photo_export_options_t opts{};
    const uint64_t req = photo_asset_export2(
        eng, (dir / "does_not_exist.jpg").string().c_str(), out.c_str(), "",
        &opts);
    ASSERT_GT(req, 0u);  // accepted; failure is reported via the event
    EXPECT_EQ(wait_export_status_c(eng, req), PHOTO_STATUS_IO_ERROR);
    EXPECT_FALSE(fs::exists(out));
    photo_engine_destroy(eng);
}

#endif  // PHOTO_HAVE_VIPS
