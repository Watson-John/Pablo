// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// edit_test.cpp — the non-destructive edit stack (Stage 7).
//   * EditSpec parse/serialize round-trip + is_identity        (always)
//   * apply_pixels: identity is a no-op; tone/filter change pixels  (always)
//   * ThumbCache::key content_rev behaviour                     (always)
//   * Catalog asset_edit: set/get/clear, atomic rev bump, FK cascade (SQLite)
//   * Engine: set_edits/content_rev/get_edits/revert end to end      (SQLite)

#include <gtest/gtest.h>

#include "edit/edit_spec.h"
#include "edit/render.h"
#include "thumb/slot.h"
#include "thumb/thumb_cache.h"

using photo::FrameBuffer;
using photo::ThumbCache;
using photo::edit::EditSpec;
using photo::edit::parse_edit_spec;
using photo::edit::serialize_edit_spec;

namespace {

FrameBuffer solid(int w, int h, uint8_t b, uint8_t g, uint8_t r, uint8_t a = 255) {
    FrameBuffer fb;
    fb.width = static_cast<uint32_t>(w);
    fb.height = static_cast<uint32_t>(h);
    fb.stride = static_cast<uint32_t>(w * 4);
    fb.bgra.resize(static_cast<size_t>(w) * h * 4);
    for (size_t i = 0; i < fb.bgra.size(); i += 4) {
        fb.bgra[i + 0] = b;
        fb.bgra[i + 1] = g;
        fb.bgra[i + 2] = r;
        fb.bgra[i + 3] = a;
    }
    return fb;
}

// A solid frame with PREMULTIPLIED BGRA for a given STRAIGHT colour + alpha —
// the real texture-path invariant the render's un/re-premultiply logic assumes.
FrameBuffer premul(int w, int h, uint8_t R, uint8_t G, uint8_t B, uint8_t A) {
    FrameBuffer fb;
    fb.width = static_cast<uint32_t>(w);
    fb.height = static_cast<uint32_t>(h);
    fb.stride = static_cast<uint32_t>(w * 4);
    fb.bgra.resize(static_cast<size_t>(w) * h * 4);
    const uint8_t pb = static_cast<uint8_t>((B * A + 127) / 255);
    const uint8_t pg = static_cast<uint8_t>((G * A + 127) / 255);
    const uint8_t pr = static_cast<uint8_t>((R * A + 127) / 255);
    for (size_t i = 0; i < fb.bgra.size(); i += 4) {
        fb.bgra[i + 0] = pb;
        fb.bgra[i + 1] = pg;
        fb.bgra[i + 2] = pr;
        fb.bgra[i + 3] = A;
    }
    return fb;
}

}  // namespace

TEST(EditSpec, RoundTrip) {
    EditSpec e;
    e.exposure = 20;
    e.contrast = -10.5;
    e.saturation = 35;
    e.vignette = -40;
    e.filter = "vivid";
    e.rot90 = 1;
    e.flipH = true;
    e.cropL = 0.1; e.cropT = 0.1; e.cropW = 0.8; e.cropH = 0.8;

    const std::string s = serialize_edit_spec(e);
    const EditSpec r = parse_edit_spec(s);
    EXPECT_NEAR(r.exposure, 20, 1e-3);
    EXPECT_NEAR(r.contrast, -10.5, 1e-3);
    EXPECT_NEAR(r.saturation, 35, 1e-3);
    EXPECT_NEAR(r.vignette, -40, 1e-3);
    EXPECT_EQ(r.filter, "vivid");
    EXPECT_EQ(r.rot90, 1);
    EXPECT_TRUE(r.flipH);
    EXPECT_FALSE(r.flipV);
    EXPECT_NEAR(r.cropW, 0.8, 1e-3);
}

TEST(EditSpec, IdentityAndSerializeEmpty) {
    EditSpec id;
    EXPECT_TRUE(id.is_identity());
    EXPECT_TRUE(serialize_edit_spec(id).empty());

    EditSpec filterNone;
    filterNone.filter = "none";
    EXPECT_TRUE(filterNone.is_identity());

    EditSpec e;
    e.exposure = 1;
    EXPECT_FALSE(e.is_identity());

    EditSpec g;
    g.rot90 = 2;
    EXPECT_FALSE(g.is_identity());
    EXPECT_TRUE(g.has_geometry());
}

TEST(EditSpec, ParseIgnoresUnknownAndMalformed) {
    const EditSpec e = parse_edit_spec("exposure=15;bogus=42;filter=warm;junk");
    EXPECT_NEAR(e.exposure, 15, 1e-3);
    EXPECT_EQ(e.filter, "warm");
}

TEST(EditSpec, RejectsNonFiniteAndTrailingGarbage) {
    // strtod parses "inf"/"nan" — they must fall back to the default, not poison
    // the render math. Trailing garbage after a number is rejected too.
    const EditSpec e = parse_edit_spec(
        "exposure=inf;contrast=nan;shadows=-infinity;whites=12abc;blacks=5");
    EXPECT_EQ(e.exposure, 0);
    EXPECT_EQ(e.contrast, 0);
    EXPECT_EQ(e.shadows, 0);
    EXPECT_EQ(e.whites, 0);
    EXPECT_NEAR(e.blacks, 5, 1e-3);  // the one well-formed value survives
    EXPECT_TRUE(e.is_identity() == false);
}

// The GOLDEN cross-language parity string. The EXACT same literal is asserted in
// pablo/test/edit_spec_test.dart ('cross-language golden parity'). Because the
// live "preview == saved" invariant depends on the native and Dart encoders
// emitting byte-identical output, any drift in key order, key names, or float
// formatting on EITHER side breaks one of the two assertions. A spec touching
// one field per category, with values chosen to format unambiguously.
static constexpr const char* kGolden =
    "rot=1;fliph=1;straighten=7.5;crop=0.1,0.2,0.7,0.6;exposure=20;"
    "contrast=-10.5;temp=15;vignette=-30;autofix=1;curves=0,0|0.5,0.25|1,1;"
    "text=0.25,0.8,0.1,FF8800,Hi;redeye=0.4,0.55,0.03;heal=0.6,0.1,0.05;"
    "filter=vivid;";

TEST(EditSpec, CrossLanguageGoldenParity) {
    EditSpec e;
    e.rot90 = 1;
    e.flipH = true;
    e.straighten = 7.5;
    e.cropL = 0.1; e.cropT = 0.2; e.cropW = 0.7; e.cropH = 0.6;
    e.exposure = 20;
    e.contrast = -10.5;
    e.temperature = 15;
    e.vignette = -30;
    e.autoFix = true;
    e.curve = {{0.f, 0.f}, {0.5f, 0.25f}, {1.f, 1.f}};
    photo::edit::TextItem t;
    t.x = 0.25f; t.y = 0.8f; t.size = 0.1f; t.color = 0xFF8800; t.text = "Hi";
    e.texts.push_back(t);
    e.redeye.push_back({0.4f, 0.55f, 0.03f});
    e.heal.push_back({0.6f, 0.1f, 0.05f});
    e.filter = "vivid";

    // Native encoder must emit exactly the golden literal…
    EXPECT_EQ(serialize_edit_spec(e), kGolden);
    // …and parsing the golden then re-serializing must be idempotent.
    EXPECT_EQ(serialize_edit_spec(parse_edit_spec(kGolden)), kGolden);
}

TEST(EditSpec, FloatFormatTiesMatchDart) {
    // %.4f (native) and toStringAsFixed(4) (Dart) must round ties identically.
    // The same literal is pinned in the Dart 'float-format ties' test.
    EditSpec e;
    e.straighten = 0.12345;  // → 0.1235
    e.exposure = 0.33335;    // → 0.3333
    EXPECT_EQ(serialize_edit_spec(e), "straighten=0.1235;exposure=0.3333;");
}

TEST(EditRender, IdentityIsNoOp) {
    FrameBuffer fb = solid(4, 4, 100, 120, 140);
    const std::vector<uint8_t> before = fb.bgra;
    photo::edit::apply_pixels(fb, EditSpec{});  // identity
    EXPECT_EQ(fb.bgra, before);
}

TEST(EditRender, ExposureBrightens) {
    FrameBuffer fb = solid(4, 4, 100, 100, 100);
    EditSpec e;
    e.exposure = 100;  // +1 stop → ~2x
    photo::edit::apply_pixels(fb, e);
    EXPECT_GT(fb.bgra[2], 100);  // R brightened
    EXPECT_GT(fb.bgra[1], 100);  // G brightened
}

TEST(EditRender, BlackAndWhiteFilterGreys) {
    FrameBuffer fb = solid(4, 4, /*b=*/40, /*g=*/160, /*r=*/220);
    EditSpec e;
    e.filter = "bw";
    photo::edit::apply_pixels(fb, e);
    // B == G == R after the luminance matrix.
    EXPECT_EQ(fb.bgra[0], fb.bgra[1]);
    EXPECT_EQ(fb.bgra[1], fb.bgra[2]);
}

TEST(EditSpec, RetouchRoundTripAndFlags) {
    EditSpec e;
    e.redeye.push_back({0.4f, 0.55f, 0.03f});
    e.heal.push_back({0.2f, 0.8f, 0.05f});
    e.heal.push_back({0.6f, 0.1f, 0.02f});

    // Retouch-only: no tone pass, but not identity.
    EXPECT_FALSE(e.has_tone_ops());
    EXPECT_TRUE(e.has_pixel_ops());
    EXPECT_FALSE(e.is_identity());

    const EditSpec r = parse_edit_spec(serialize_edit_spec(e));
    ASSERT_EQ(r.redeye.size(), 1u);
    ASSERT_EQ(r.heal.size(), 2u);
    EXPECT_NEAR(r.redeye[0].x, 0.4f, 1e-3);
    EXPECT_NEAR(r.redeye[0].y, 0.55f, 1e-3);
    EXPECT_NEAR(r.redeye[0].r, 0.03f, 1e-3);
    EXPECT_NEAR(r.heal[1].x, 0.6f, 1e-3);
    EXPECT_NEAR(r.heal[1].r, 0.02f, 1e-3);
    // Serialization is stable (idempotent round-trip).
    EXPECT_EQ(serialize_edit_spec(r), serialize_edit_spec(e));
}

TEST(EditRender, RedeyeNeutralizesInsideCircleOnly) {
    // Fully red frame; a red-eye circle at the centre should desaturate the pupil
    // pixels but leave the corners untouched.
    FrameBuffer fb = solid(20, 20, /*b=*/10, /*g=*/10, /*r=*/220);
    EditSpec e;
    e.redeye.push_back({0.5f, 0.5f, 0.25f});  // ~5px radius (short edge 20)
    photo::edit::apply_redeye(fb, e);

    auto at = [&](int x, int y, int ch) {
        return fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4 + ch];
    };
    // Centre pixel: red neutralized (R dropped far below the original 220).
    EXPECT_LT(at(10, 10, 2), 60);
    // Corner pixel (outside the circle): still red.
    EXPECT_EQ(at(0, 0, 2), 220);
}

TEST(EditRender, RedeyeSparesSurroundingSkin) {
    // A skin field with a small red pupil at the centre; a brush that covers the
    // pupil AND a wide skin margin must recolor ONLY the pupil blob and leave the
    // skin untouched. This is the fix for the old fixed-threshold over-fire, where
    // warm/dark skin inside the brush was greyed along with the pupil.
    FrameBuffer fb = solid(40, 40, /*b=*/150, /*g=*/170, /*r=*/220);  // skin tone
    const int cx = 20, cy = 20;
    for (int y = 0; y < 40; ++y)
        for (int x = 0; x < 40; ++x) {
            const int dx = x - cx, dy = y - cy;
            if (dx * dx + dy * dy <= 16) {  // ~4px flash pupil
                uint8_t* p = &fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4];
                p[0] = 30; p[1] = 30; p[2] = 200;  // bright red
            }
        }
    EditSpec e;
    e.redeye.push_back({0.5f, 0.5f, 0.30f});  // 12px brush: pupil + skin margin
    photo::edit::apply_redeye(fb, e);
    auto R = [&](int x, int y) {
        return fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4 + 2];
    };
    EXPECT_LT(R(cx, cy), 120);      // pupil corrected
    EXPECT_GT(R(cx + 8, cy), 200);  // skin 8px out (inside brush, off pupil) spared
    EXPECT_GT(R(cx, cy + 8), 200);  // skin below the pupil spared too
}

TEST(EditRender, RedeyeNoRedIsNoOp) {
    // A brush dabbed on plain skin (no pupil) must change nothing.
    FrameBuffer fb = solid(30, 30, /*b=*/150, /*g=*/170, /*r=*/220);
    const std::vector<uint8_t> before = fb.bgra;
    EditSpec e;
    e.redeye.push_back({0.5f, 0.5f, 0.25f});
    photo::edit::apply_redeye(fb, e);
    EXPECT_EQ(fb.bgra, before);
}

TEST(EditRender, MapRegionThroughGeometryPureMath) {
    using photo::edit::map_region_through_geometry;
    photo::edit::Region in;
    in.x = 0.25f; in.y = 0.5f; in.r = 0.1f;  // 100x60: px=(25,30), pr=6
    photo::edit::Region out;

    // rot90=1 (90° CW): (25,30) → (60−30, 25) = (30,25) in a 60x100 frame.
    { EditSpec s; s.rot90 = 1;
      ASSERT_TRUE(map_region_through_geometry(in, 100, 60, s, &out));
      EXPECT_NEAR(out.x, 30.0 / 60, 1e-4);
      EXPECT_NEAR(out.y, 25.0 / 100, 1e-4);
      EXPECT_NEAR(out.r, 6.0 / 60, 1e-4); }  // short edge still 60

    // Crop left half off: (25,30) → (0,30) in 50x60 → u=0; radius rescales.
    { EditSpec s; s.cropL = 0.25; s.cropT = 0; s.cropW = 0.5; s.cropH = 1;
      ASSERT_TRUE(map_region_through_geometry(in, 100, 60, s, &out));
      EXPECT_NEAR(out.x, 0.0, 1e-4);
      EXPECT_NEAR(out.y, 0.5, 1e-4);
      EXPECT_NEAR(out.r, 6.0 / 50, 1e-4); }

    // A crop that excludes the point entirely → dropped, not misplaced.
    { EditSpec s; s.cropL = 0.5; s.cropT = 0.5; s.cropW = 0.5; s.cropH = 0.5;
      EXPECT_FALSE(map_region_through_geometry(in, 100, 60, s, &out)); }

    // Identity spec is a passthrough.
    { EditSpec s;
      ASSERT_TRUE(map_region_through_geometry(in, 100, 60, s, &out));
      EXPECT_NEAR(out.x, in.x, 1e-5);
      EXPECT_NEAR(out.y, in.y, 1e-5);
      EXPECT_NEAR(out.r, in.r, 1e-5); }
}

TEST(EditRender, AutoRedeyeFindsRedPupilsSkipsNonRed) {
    // Skin BGR image with red pupils painted at two eye landmarks; the auto-detect
    // must emit a Region at each red eye and NONE at a plain-skin eye pair.
    const int W = 100, H = 60, stride = W * 3;
    std::vector<uint8_t> bgr(static_cast<size_t>(stride) * H);
    for (size_t i = 0; i < bgr.size(); i += 3) { bgr[i] = 150; bgr[i + 1] = 170; bgr[i + 2] = 220; }
    auto pupil = [&](int cx, int cy) {
        for (int y = cy - 3; y <= cy + 3; ++y)
            for (int x = cx - 3; x <= cx + 3; ++x)
                if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= 9) {
                    uint8_t* p = &bgr[static_cast<size_t>(y) * stride + x * 3];
                    p[0] = 30; p[1] = 30; p[2] = 200;  // bright red
                }
    };
    pupil(30, 25); pupil(60, 25);  // both eyes of face A are red

    auto regs = photo::edit::auto_redeye_regions(
        bgr.data(), W, H, stride, {{30, 25, 60, 25}});
    ASSERT_EQ(regs.size(), 2u);
    EXPECT_NEAR(regs[0].x, 30.5f / 100, 0.03f);
    EXPECT_NEAR(regs[0].y, 25.5f / 60, 0.03f);
    EXPECT_NEAR(regs[1].x, 60.5f / 100, 0.03f);

    // A different eye pair over plain skin → nothing detected.
    auto none = photo::edit::auto_redeye_regions(
        bgr.data(), W, H, stride, {{15, 50, 40, 50}});
    EXPECT_TRUE(none.empty());
}

TEST(EditRender, HealClonesSurroundingContent) {
    // Uniform grey frame with a blue blemish square at the centre; healing should
    // pull the surrounding grey over the blemish.
    FrameBuffer fb = solid(40, 40, /*b=*/128, /*g=*/128, /*r=*/128);
    for (int y = 17; y < 23; ++y)
        for (int x = 17; x < 23; ++x) {
            uint8_t* p = &fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4];
            p[0] = 240; p[1] = 40; p[2] = 20;  // bright blue blemish
        }
    EditSpec e;
    e.heal.push_back({0.5f, 0.5f, 0.12f});  // ~5px radius covers the blemish
    photo::edit::apply_heal(fb, e);

    uint8_t* c = &fb.bgra[(20u * fb.stride) + 20 * 4];
    // Centre now resembles the grey surround, not the blue blemish.
    EXPECT_NEAR(c[0], 128, 40);
    EXPECT_NEAR(c[1], 128, 40);
    EXPECT_NEAR(c[2], 128, 40);
    EXPECT_LT(c[0], 200);  // clearly no longer the blemish's blue
}

TEST(EditRender, HealRemovesBrightSpotNearEdge) {
    // Reproduces the GUI case that a live smoke test surfaced: a large landscape
    // frame, a bright rectangular feature near the LEFT edge on a uniform
    // surround, healed with a UI-sized brush (r = 0.06 of the short edge). The
    // former feature's centre must be pulled toward the surround colour.
    const int W = 300, H = 200;
    FrameBuffer fb = solid(W, H, /*b=*/150, /*g=*/180, /*r=*/200);  // tan wall
    const int scx = 24, scy = 100;  // ~ normalized (0.08, 0.5)
    for (int y = scy - 12; y <= scy + 12; ++y)
        for (int x = scx - 8; x <= scx + 8; ++x) {
            uint8_t* p = &fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4];
            p[0] = 225; p[1] = 228; p[2] = 230;  // near-white "switch"
        }
    EditSpec e;
    e.heal.push_back({static_cast<float>(scx) / W,
                      static_cast<float>(scy) / H, 0.06f});
    photo::edit::apply_heal(fb, e);
    const uint8_t* c = &fb.bgra[(static_cast<size_t>(scy) * fb.stride) + scx * 4];
    EXPECT_LT(c[0], 195) << "B not pulled toward wall (150) — heal was a no-op";
    EXPECT_LT(c[2], 220) << "R still near the white switch (230)";
}

TEST(EditRender, HealTinyFrameIsSafeNoOp) {
    // Frame too small for a donor patch: heal must bail without touching pixels
    // (and without UB in the donor-centre clamp).
    FrameBuffer fb = solid(3, 3, 50, 60, 70);
    const std::vector<uint8_t> before = fb.bgra;
    EditSpec e;
    e.heal.push_back({0.5f, 0.5f, 0.3f});
    photo::edit::apply_heal(fb, e);
    EXPECT_EQ(fb.bgra, before);
}

// ── Non-opaque alpha: the un/re-premultiply path (dead code for opaque frames)
TEST(EditRender, ApplyPixelsPreservesNonOpaqueAlpha) {
    // A=128 premultiplied frame of straight (R=200,G=100,B=50); a bw filter
    // greys it while the alpha channel and premultiplied invariant survive.
    FrameBuffer fb = premul(4, 4, 200, 100, 50, 128);
    // Punch one fully-transparent pixel; it must remain zeroed.
    fb.bgra[0] = fb.bgra[1] = fb.bgra[2] = fb.bgra[3] = 0;
    EditSpec e;
    e.filter = "bw";
    photo::edit::apply_pixels(fb, e);

    // Transparent pixel stays fully transparent + zero colour.
    EXPECT_EQ(fb.bgra[3], 0);
    EXPECT_EQ(fb.bgra[0], 0);
    // An opaque-alpha-128 pixel: alpha preserved, greyed, still premultiplied.
    const uint8_t* p = &fb.bgra[4 * 4];  // pixel (1,0)
    EXPECT_EQ(p[3], 128);
    EXPECT_EQ(p[0], p[1]);       // bw → B==G==R
    EXPECT_EQ(p[1], p[2]);
    EXPECT_LE(p[0], 128);        // premultiplied: channel <= alpha
    EXPECT_GT(p[0], 0);
}

TEST(EditRender, RedeyeOnNonOpaqueAlpha) {
    // A=128 premultiplied red pixel: red-eye neutralizes it and keeps alpha=128.
    FrameBuffer fb = premul(6, 6, 220, 12, 12, 128);
    EditSpec e;
    e.redeye.push_back({0.5f, 0.5f, 0.5f});  // covers the whole frame
    photo::edit::apply_redeye(fb, e);
    const uint8_t* c = &fb.bgra[(3u * fb.stride) + 3 * 4];  // centre
    EXPECT_EQ(c[3], 128);        // alpha preserved
    EXPECT_LT(c[2], 40);         // premultiplied red channel neutralized (was ~110)
}

TEST(EditRender, HealOnNonOpaqueAlphaPreservesAlpha) {
    // Uniform A=128 grey with a blue blemish; heal keeps alpha=128 everywhere.
    FrameBuffer fb = premul(40, 40, 128, 128, 128, 128);
    // Premultiplied blue blemish (straight ~ (20,40,240) at A=128).
    for (int y = 17; y < 23; ++y)
        for (int x = 17; x < 23; ++x) {
            uint8_t* p = &fb.bgra[(static_cast<size_t>(y) * fb.stride) + x * 4];
            p[0] = static_cast<uint8_t>(240 * 128 / 255);
            p[1] = static_cast<uint8_t>(40 * 128 / 255);
            p[2] = static_cast<uint8_t>(20 * 128 / 255);
        }
    EditSpec e;
    e.heal.push_back({0.5f, 0.5f, 0.12f});
    photo::edit::apply_heal(fb, e);
    // Every pixel keeps alpha 128.
    for (size_t i = 3; i < fb.bgra.size(); i += 4) ASSERT_EQ(fb.bgra[i], 128);
    // Centre pulled back toward the grey surround (premul grey ≈ 64), off blue.
    const uint8_t* c = &fb.bgra[(20u * fb.stride) + 20 * 4];
    EXPECT_LT(c[0], 110);  // premul B down from the blemish's ~120
}

TEST(ThumbCacheKey, ContentRevDistinguishesButZeroMatches) {
    const std::string path = "/no/such/file.jpg";
    const uint64_t base = ThumbCache::key(1, 2, path);
    EXPECT_EQ(ThumbCache::key(1, 2, path, 0), base);     // rev 0 == unedited key
    EXPECT_NE(ThumbCache::key(1, 2, path, 1), base);     // rev 1 differs
    EXPECT_NE(ThumbCache::key(1, 2, path, 1),
              ThumbCache::key(1, 2, path, 2));           // revs are distinct
}

// ── SQLite-backed: catalog + engine ─────────────────────────────────────────
#ifdef PHOTO_HAVE_SQLITE

#include <chrono>
#include <filesystem>
#include <fstream>
#include <memory>
#include <thread>

#include "catalog/catalog.h"
#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::Engine;
using photo::catalog::AssetRecord;
using photo::catalog::Catalog;

namespace {

std::string fresh_edit_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_edit_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

int64_t insert_asset(Catalog& cat, const std::string& path) {
    AssetRecord r;
    r.path = path;
    r.folder = fs::path(path).parent_path().string();
    r.filename = fs::path(path).filename().string();
    r.format = "jpeg";
    return cat.upsert_asset(r);
}

}  // namespace

TEST(CatalogEdit, SetGetClearAndRevBump) {
    Catalog cat(fresh_edit_db("setget"));
    ASSERT_TRUE(cat.ok());
    const int64_t id = insert_asset(cat, "/lib/e.jpg");

    EXPECT_FALSE(cat.edit_for(id).has_value());

    const int64_t rev1 = cat.set_edit(id, "exposure=10;", 111);
    EXPECT_EQ(rev1, 1);
    auto row = cat.edit_for(id);
    ASSERT_TRUE(row.has_value());
    EXPECT_EQ(row->spec, "exposure=10;");
    EXPECT_EQ(row->content_rev, 1);
    EXPECT_EQ(row->updated_ns, 111);

    const int64_t rev2 = cat.set_edit(id, "exposure=20;", 222);
    EXPECT_EQ(rev2, 2);  // monotonic bump on the same asset
    EXPECT_EQ(cat.edit_for(id)->spec, "exposure=20;");

    cat.clear_edit(id);
    EXPECT_FALSE(cat.edit_for(id).has_value());
}

TEST(CatalogEdit, AllEditsAndForeignKeyCascade) {
    Catalog cat(fresh_edit_db("cascade"));
    const int64_t a = insert_asset(cat, "/lib/a.jpg");
    const int64_t b = insert_asset(cat, "/lib/b.jpg");
    cat.set_edit(a, "contrast=5;", 1);
    cat.set_edit(b, "saturation=9;", 2);

    EXPECT_EQ(cat.all_edits().size(), 2u);

    // Removing the asset must cascade-drop its edit row (remove_asset is a bare
    // DELETE, so this relies on the FK ON DELETE CASCADE).
    cat.remove_asset(a);
    EXPECT_FALSE(cat.edit_for(a).has_value());
    EXPECT_TRUE(cat.edit_for(b).has_value());
    EXPECT_EQ(cat.all_edits().size(), 1u);
}

namespace {

std::unique_ptr<Engine> make_engine(const fs::path& dir) {
    auto cat = (dir / "pablo.db").string();
    auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return Engine::create(cfg);
}

// Import one fake image and return its catalog asset id (0 on failure).
int64_t import_one(Engine& eng, const fs::path& dir) {
    const fs::path img = dir / "p.jpg";
    std::ofstream(img, std::ios::binary) << "x";
    const uint64_t req = eng.import_path(img.string());
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + seconds(8);
    photo_event_t buf[64];
    bool done = false;
    while (!done && steady_clock::now() < deadline) {
        size_t n = eng.events().pop_n(buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE && buf[i].request_id == req)
                done = true;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    if (!done) return 0;
    const auto assets = eng.list_assets();
    return assets.empty() ? 0 : assets.front().id;
}

}  // namespace

TEST(EngineEdit, SetContentRevGetRevert) {
    auto dir = fs::temp_directory_path() / "photo_edit_engine";
    fs::remove_all(dir);
    fs::create_directories(dir);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);

    const int64_t id = import_one(*eng, dir);
    ASSERT_GT(id, 0);

    EXPECT_EQ(eng->content_rev(id), 0u);
    EXPECT_TRUE(eng->get_edits(id).empty());

    const uint64_t rev = eng->set_edits(id, "exposure=25;filter=vivid;");
    EXPECT_EQ(rev, 1u);
    EXPECT_EQ(eng->content_rev(id), 1u);
    EXPECT_FALSE(eng->get_edits(id).empty());

    // An identity spec is a revert (clears the row, rev back to 0).
    EXPECT_EQ(eng->set_edits(id, "exposure=0;"), 0u);
    EXPECT_EQ(eng->content_rev(id), 0u);
    EXPECT_TRUE(eng->get_edits(id).empty());

    // Re-editing after a revert gets a FRESH, never-reused content_rev (the
    // catalog counter survives the revert as an empty placeholder row), so a
    // stale cached frame from the first edit can never be re-served. Here:
    // rev1 (edit) → revert bumps the stored counter to 2 → this edit → rev 3.
    eng->set_edits(id, "contrast=10;");
    EXPECT_EQ(eng->content_rev(id), 3u);
    eng->revert_edits(id);
    EXPECT_EQ(eng->content_rev(id), 0u);
    EXPECT_TRUE(eng->get_edits(id).empty());
}

#endif  // PHOTO_HAVE_SQLITE
