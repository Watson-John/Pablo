// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// edit_integration_test.cpp — exercises COMBINATIONS of edits end to end:
//   * permuted specs round-trip through serialize/parse stably,
//   * apply_pixels is deterministic + bounded over permuted tone/colour/filter,
//   * the Engine applies a permuted sequence with a monotonic content_rev,
//   * apply_geometry (libvips) produces the right dimensions + pixels for
//     rot90 / flip / crop / straighten and their combinations.

#include <gtest/gtest.h>

#include <algorithm>
#include <cstdint>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "edit/edit_spec.h"
#include "edit/render.h"
#include "thumb/slot.h"

using photo::FrameBuffer;
using photo::edit::EditSpec;
using photo::edit::parse_edit_spec;
using photo::edit::serialize_edit_spec;
using photo::edit::TextItem;

namespace {

using Mod = std::function<void(EditSpec&)>;

// A palette of single-field edits spanning every category.
const std::vector<std::pair<const char*, Mod>>& mods() {
    static const std::vector<std::pair<const char*, Mod>> m = {
        {"exposure", [](EditSpec& e) { e.exposure = 22; }},
        {"contrast", [](EditSpec& e) { e.contrast = -18; }},
        {"shadows", [](EditSpec& e) { e.shadows = 35; }},
        {"temp", [](EditSpec& e) { e.temperature = -25; }},
        {"saturation", [](EditSpec& e) { e.saturation = 40; }},
        {"vignette", [](EditSpec& e) { e.vignette = -30; }},
        {"sharpness", [](EditSpec& e) { e.sharpness = 50; }},
        {"filter", [](EditSpec& e) { e.filter = "vivid"; }},
        {"rot90", [](EditSpec& e) { e.rot90 = 1; }},
        {"flipH", [](EditSpec& e) { e.flipH = true; }},
        {"straighten", [](EditSpec& e) { e.straighten = 7.5; }},
        {"crop", [](EditSpec& e) {
             e.cropL = 0.1; e.cropT = 0.15; e.cropW = 0.75; e.cropH = 0.7;
         }},
        {"redeye", [](EditSpec& e) { e.redeye.push_back({0.35f, 0.4f, 0.05f}); }},
        {"heal", [](EditSpec& e) { e.heal.push_back({0.6f, 0.55f, 0.08f}); }},
    };
    return m;
}

// All single + pair + a few triple combinations of the palette.
std::vector<EditSpec> permutations() {
    std::vector<EditSpec> out;
    const auto& M = mods();
    for (size_t i = 0; i < M.size(); ++i) {
        EditSpec e;
        M[i].second(e);
        out.push_back(e);
        for (size_t j = i + 1; j < M.size(); ++j) {
            EditSpec p;
            M[i].second(p);
            M[j].second(p);
            out.push_back(p);
        }
    }
    // A few triples mixing geometry + tone + filter.
    EditSpec t1; M[0].second(t1); M[8].second(t1); M[11].second(t1);  // expo+rot+crop
    EditSpec t2; M[4].second(t2); M[7].second(t2); M[9].second(t2);   // sat+filter+flip
    EditSpec t3; M[1].second(t3); M[10].second(t3); M[5].second(t3);  // contrast+straighten+vignette
    out.push_back(t1); out.push_back(t2); out.push_back(t3);
    return out;
}

// A synthetic non-uniform frame (premultiplied BGRA, opaque) for apply_pixels.
FrameBuffer gradient(int w, int h) {
    FrameBuffer fb;
    fb.width = w; fb.height = h; fb.stride = w * 4;
    fb.bgra.resize(static_cast<size_t>(w) * h * 4);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            uint8_t* p = &fb.bgra[(static_cast<size_t>(y) * w + x) * 4];
            p[0] = static_cast<uint8_t>((x * 255) / std::max(1, w - 1));  // B
            p[1] = static_cast<uint8_t>((y * 255) / std::max(1, h - 1));  // G
            p[2] = static_cast<uint8_t>(((x + y) * 255) / std::max(1, w + h - 2));  // R
            p[3] = 255;
        }
    return fb;
}

}  // namespace

TEST(EditPermute, SpecRoundTripsStablyAndFlagsAgree) {
    for (const auto& spec : permutations()) {
        const std::string s1 = serialize_edit_spec(spec);
        const EditSpec parsed = parse_edit_spec(s1);
        const std::string s2 = serialize_edit_spec(parsed);
        EXPECT_EQ(s1, s2) << "unstable round-trip for: " << s1;
        // The combined edit is never identity (every permutation sets ≥1 field).
        EXPECT_FALSE(parsed.is_identity()) << s1;
        // is_identity ⇔ no geometry AND no pixel ops.
        EXPECT_EQ(parsed.is_identity(),
                  !parsed.has_geometry() && !parsed.has_pixel_ops());
    }
}

TEST(EditPermute, ApplyPixelsDeterministicBoundedAndEffective) {
    const FrameBuffer original = gradient(40, 30);
    for (const auto& spec : permutations()) {
        // apply_pixels is the tone/colour/filter domain only — a geometry- or
        // retouch-only spec is a no-op here (retouch has its own passes below).
        if (!spec.has_tone_ops()) continue;
        FrameBuffer a = original;
        FrameBuffer b = original;
        photo::edit::apply_pixels(a, spec);
        photo::edit::apply_pixels(b, spec);
        EXPECT_EQ(a.bgra, b.bgra) << "non-deterministic for: " << serialize_edit_spec(spec);
        // Alpha preserved; a tone/colour/filter op changes at least one pixel.
        EXPECT_NE(a.bgra, original.bgra) << "no effect for: " << serialize_edit_spec(spec);
        for (size_t i = 3; i < a.bgra.size(); i += 4) EXPECT_EQ(a.bgra[i], 255);
    }
}

TEST(EditPermute, RetouchDeterministicBoundedAndAlphaPreserved) {
    const FrameBuffer original = gradient(40, 30);
    for (const auto& spec : permutations()) {
        if (spec.redeye.empty() && spec.heal.empty()) continue;
        FrameBuffer a = original;
        FrameBuffer b = original;
        photo::edit::apply_redeye(a, spec);
        photo::edit::apply_heal(a, spec);
        photo::edit::apply_redeye(b, spec);
        photo::edit::apply_heal(b, spec);
        EXPECT_EQ(a.bgra, b.bgra)
            << "non-deterministic retouch for: " << serialize_edit_spec(spec);
        // Alpha is never touched by the retouch passes.
        for (size_t i = 3; i < a.bgra.size(); i += 4) EXPECT_EQ(a.bgra[i], 255);
    }
}

TEST(EditPermute, IdentityApplyPixelsIsNoOp) {
    const FrameBuffer original = gradient(16, 16);
    FrameBuffer f = original;
    photo::edit::apply_pixels(f, EditSpec{});  // identity
    EXPECT_EQ(f.bgra, original.bgra);
}

TEST(EditPermute, GeometryZoomMath) {
    EXPECT_DOUBLE_EQ(photo::edit::geometry_zoom(EditSpec{}), 1.0);
    EditSpec crop; crop.cropW = 0.5; crop.cropH = 0.5;
    EXPECT_NEAR(photo::edit::geometry_zoom(crop), 2.0, 1e-9);
    EditSpec str; str.straighten = 45;
    EXPECT_GT(photo::edit::geometry_zoom(str), 1.3);  // cos45+sin45 ≈ 1.414
}

TEST(EditAutoFix, StretchesContrast) {
    // A low-contrast frame: every channel confined to ~[100,150].
    FrameBuffer fb;
    fb.width = 32; fb.height = 32; fb.stride = 32 * 4;
    fb.bgra.resize(static_cast<size_t>(32) * 32 * 4);
    for (int i = 0; i < 32 * 32; ++i) {
        const uint8_t v = static_cast<uint8_t>(100 + (i % 32) * 50 / 31);
        fb.bgra[i * 4 + 0] = v;
        fb.bgra[i * 4 + 1] = v;
        fb.bgra[i * 4 + 2] = v;
        fb.bgra[i * 4 + 3] = 255;
    }
    EditSpec s; s.autoFix = true;
    EXPECT_TRUE(s.has_pixel_ops());
    photo::edit::apply_pixels(fb, s);
    uint8_t mn = 255, mx = 0;
    for (int i = 0; i < 32 * 32; ++i) {
        const uint8_t v = fb.bgra[i * 4 + 2];
        mn = std::min(mn, v);
        mx = std::max(mx, v);
    }
    EXPECT_LT(mn, 40);   // black point pulled down
    EXPECT_GT(mx, 215);  // white point pushed up
}

TEST(EditCurves, RoundTripAndDarkenMidtones) {
    EditSpec e;
    e.curve = {{0.f, 0.f}, {0.5f, 0.25f}, {1.f, 1.f}};  // pull midtones down
    EXPECT_FALSE(e.curve_is_identity());
    EXPECT_TRUE(e.has_pixel_ops());
    const std::string s = serialize_edit_spec(e);
    const EditSpec r = parse_edit_spec(s);
    ASSERT_EQ(r.curve.size(), 3u);
    EXPECT_NEAR(r.curve[1].second, 0.25f, 1e-3);
    EXPECT_EQ(serialize_edit_spec(r), s);

    // Mid-gray 128 → curve maps 0.5→0.25 → ~64.
    FrameBuffer fb;
    fb.width = 8; fb.height = 8; fb.stride = 8 * 4;
    fb.bgra.assign(8 * 8 * 4, 128);
    for (int i = 0; i < 8 * 8; ++i) fb.bgra[i * 4 + 3] = 255;
    photo::edit::apply_pixels(fb, r);
    EXPECT_NEAR(fb.bgra[2], 64, 8);  // R darkened toward 0.25*255
}

TEST(EditCurves, IdentityCurveIsNoOp) {
    EditSpec e;
    e.curve = {{0.f, 0.f}, {1.f, 1.f}};  // straight line
    EXPECT_TRUE(e.curve_is_identity());
    EXPECT_TRUE(serialize_edit_spec(e).empty());
}

TEST(EditText, RoundTripsWithEscapedDelimiters) {
    EditSpec e;
    TextItem t;
    t.x = 0.25f; t.y = 0.8f; t.size = 0.1f; t.color = 0xFF8800;
    t.text = "a;b=c,d|e %weird";  // every delimiter + percent
    e.texts.push_back(t);
    EXPECT_TRUE(e.has_pixel_ops());
    const std::string s = serialize_edit_spec(e);
    const EditSpec r = parse_edit_spec(s);
    ASSERT_EQ(r.texts.size(), 1u);
    EXPECT_EQ(r.texts[0].text, "a;b=c,d|e %weird");
    EXPECT_NEAR(r.texts[0].x, 0.25f, 1e-3);
    EXPECT_EQ(r.texts[0].color, 0xFF8800u);
    EXPECT_EQ(serialize_edit_spec(r), s);  // stable
}

// ── Engine: a permuted sequence with a monotonic content_rev ────────────────
#ifdef PHOTO_HAVE_SQLITE

#include <chrono>
#include <filesystem>
#include <fstream>
#include <memory>
#include <thread>

#include "photo_core.h"
#include "runtime/engine.h"

namespace fs = std::filesystem;
using photo::Engine;

namespace {
int64_t import_one(Engine& eng, const fs::path& dir, const char* name) {
    const fs::path img = dir / name;
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
    for (const auto& a : eng.list_assets())
        if (a.filename == name) return a.id;
    return 0;
}
}  // namespace

TEST(EditPermute, EngineAppliesPermutedSequenceMonotonically) {
    auto dir = fs::temp_directory_path() / "photo_edit_perm_engine";
    fs::remove_all(dir);
    fs::create_directories(dir);
    photo_config_t cfg{};
    const auto cat = (dir / "pablo.db").string();
    const auto cache = (dir / "cache").string();
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    auto eng = Engine::create(cfg);
    ASSERT_NE(eng, nullptr);
    const int64_t id = import_one(*eng, dir, "p.jpg");
    ASSERT_GT(id, 0);

    uint64_t last_rev = 0;
    const auto specs = permutations();
    for (size_t k = 0; k < specs.size(); ++k) {
        const std::string spec = serialize_edit_spec(specs[k]);
        const uint64_t rev = eng->set_edits(id, spec);
        EXPECT_GT(rev, last_rev) << "content_rev must be monotonic at step " << k;
        last_rev = rev;
        // The stored spec round-trips (canonicalized) and the asset is "edited".
        EXPECT_EQ(eng->get_edits(id), spec);
        EXPECT_EQ(eng->content_rev(id), rev);
        const auto edited = eng->edited_asset_ids();
        EXPECT_EQ(edited.size(), 1u);
        EXPECT_EQ(edited[0], id);
    }
    // Revert clears the active edit but keeps the counter climbing.
    eng->revert_edits(id);
    EXPECT_EQ(eng->content_rev(id), 0u);
    EXPECT_TRUE(eng->get_edits(id).empty());
    EXPECT_TRUE(eng->edited_asset_ids().empty());
    const uint64_t after = eng->set_edits(id, "exposure=5;");
    EXPECT_GT(after, last_rev) << "rev reused after revert → cache collision risk";
}

#endif  // PHOTO_HAVE_SQLITE

// ── Geometry render (libvips): dims + pixels for combined transforms ────────
#ifdef PHOTO_HAVE_VIPS

#include <vips/vips.h>

namespace {
// 4-quadrant RGB image: TL red, TR green, BL blue, BR white. Owned (copy).
VipsImage* quadrants(int w, int h) {
    std::vector<uint8_t> buf(static_cast<size_t>(w) * h * 3);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            uint8_t* p = &buf[(static_cast<size_t>(y) * w + x) * 3];
            const bool right = x >= w / 2, bottom = y >= h / 2;
            if (!right && !bottom) { p[0] = 255; p[1] = 0; p[2] = 0; }    // TL red
            else if (right && !bottom) { p[0] = 0; p[1] = 255; p[2] = 0; } // TR green
            else if (!right && bottom) { p[0] = 0; p[1] = 0; p[2] = 255; } // BL blue
            else { p[0] = 255; p[1] = 255; p[2] = 255; }                   // BR white
        }
    return vips_image_new_from_memory_copy(buf.data(), buf.size(), w, h, 3,
                                           VIPS_FORMAT_UCHAR);
}

// Dominant channel index (0=R,1=G,2=B) of the pixel at (x,y).
int dominant(VipsImage* im, int x, int y) {
    double* v = nullptr; int n = 0;
    if (vips_getpoint(im, &v, &n, x, y, nullptr) != 0) { vips_error_clear(); return -1; }
    int best = 0;
    for (int c = 1; c < n && c < 3; ++c) if (v[c] > v[best]) best = c;
    g_free(v);
    return best;
}

struct VipsEnv : ::testing::Environment {
    void SetUp() override { vips_init("edit_integration_test"); }
};
const auto* kVipsEnv = ::testing::AddGlobalTestEnvironment(new VipsEnv);
}  // namespace

TEST(EditGeometry, Rot90SwapsDimsAndRotatesPixels) {
    VipsImage* in = quadrants(100, 60);
    ASSERT_NE(in, nullptr);
    EditSpec s; s.rot90 = 1;  // 90° clockwise
    VipsImage* out = photo::edit::apply_geometry(in, s);
    ASSERT_NE(out, nullptr);
    EXPECT_EQ(vips_image_get_width(out), 60);
    EXPECT_EQ(vips_image_get_height(out), 100);
    // 90° CW: original bottom-left (blue) lands at the new top-left.
    EXPECT_EQ(dominant(out, 2, 2), 2);  // blue
    g_object_unref(out);
    g_object_unref(in);
}

TEST(EditGeometry, FlipHorizontalKeepsDimsSwapsSides) {
    VipsImage* in = quadrants(100, 60);
    EditSpec s; s.flipH = true;
    VipsImage* out = photo::edit::apply_geometry(in, s);
    ASSERT_NE(out, nullptr);
    EXPECT_EQ(vips_image_get_width(out), 100);
    EXPECT_EQ(vips_image_get_height(out), 60);
    // Top-left now shows what was top-right: green.
    EXPECT_EQ(dominant(out, 2, 2), 1);  // green
    g_object_unref(out);
    g_object_unref(in);
}

TEST(EditGeometry, CropExtractsRegion) {
    VipsImage* in = quadrants(100, 60);
    EditSpec s; s.cropL = 0.5; s.cropT = 0.0; s.cropW = 0.5; s.cropH = 1.0;  // right half
    VipsImage* out = photo::edit::apply_geometry(in, s);
    ASSERT_NE(out, nullptr);
    EXPECT_NEAR(vips_image_get_width(out), 50, 1);
    EXPECT_NEAR(vips_image_get_height(out), 60, 1);
    EXPECT_EQ(dominant(out, 2, 2), 1);  // right-half top-left is green
    g_object_unref(out);
    g_object_unref(in);
}

TEST(EditGeometry, StraightenShrinksToInscribedRect) {
    VipsImage* in = quadrants(100, 60);
    EditSpec s; s.straighten = 10;
    VipsImage* out = photo::edit::apply_geometry(in, s);
    ASSERT_NE(out, nullptr);
    // Inscribed rect is strictly smaller than the original (border removed).
    EXPECT_LT(vips_image_get_width(out), 100);
    EXPECT_LT(vips_image_get_height(out), 60);
    EXPECT_GT(vips_image_get_width(out), 50);
    g_object_unref(out);
    g_object_unref(in);
}

TEST(EditGeometry, CombinedRotThenCropComposes) {
    VipsImage* in = quadrants(100, 60);
    EditSpec s; s.rot90 = 1; s.cropL = 0; s.cropT = 0; s.cropW = 0.5; s.cropH = 0.5;
    VipsImage* out = photo::edit::apply_geometry(in, s);
    ASSERT_NE(out, nullptr);
    // After rot90 dims are 60x100; cropping to the top-left quarter → ~30x50.
    EXPECT_NEAR(vips_image_get_width(out), 30, 1);
    EXPECT_NEAR(vips_image_get_height(out), 50, 1);
    g_object_unref(out);
    g_object_unref(in);
}

// ── map_region_through_geometry pinned against the REAL apply_geometry ──────
namespace {

// Quadrants image with a 3x3 magenta marker at (mx,my). Owned (copy).
VipsImage* quadrants_with_marker(int w, int h, int mx, int my) {
    std::vector<uint8_t> buf(static_cast<size_t>(w) * h * 3);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            uint8_t* p = &buf[(static_cast<size_t>(y) * w + x) * 3];
            const bool right = x >= w / 2, bottom = y >= h / 2;
            if (!right && !bottom) { p[0] = 255; p[1] = 0; p[2] = 0; }
            else if (right && !bottom) { p[0] = 0; p[1] = 255; p[2] = 0; }
            else if (!right && bottom) { p[0] = 0; p[1] = 0; p[2] = 255; }
            else { p[0] = 255; p[1] = 255; p[2] = 255; }
        }
    for (int dy = -1; dy <= 1; ++dy)
        for (int dx = -1; dx <= 1; ++dx) {
            const int x = mx + dx, y = my + dy;
            if (x < 0 || x >= w || y < 0 || y >= h) continue;
            uint8_t* p = &buf[(static_cast<size_t>(y) * w + x) * 3];
            p[0] = 255; p[1] = 0; p[2] = 255;  // magenta
        }
    return vips_image_new_from_memory_copy(buf.data(), buf.size(), w, h, 3,
                                           VIPS_FORMAT_UCHAR);
}

// Centroid of near-magenta pixels in `im`; false when none found.
bool find_marker(VipsImage* im, double& cx, double& cy) {
    size_t n = 0;
    VipsImage* mem = vips_image_copy_memory(im);
    if (mem == nullptr) return false;
    const int W = vips_image_get_width(mem), H = vips_image_get_height(mem);
    const int bands = vips_image_get_bands(mem);
    const uint8_t* d = static_cast<const uint8_t*>(vips_image_get_data(mem));
    double sx = 0, sy = 0;
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            const uint8_t* p = d + (static_cast<size_t>(y) * W + x) * bands;
            if (p[0] > 180 && p[1] < 90 && p[2] > 180) { sx += x; sy += y; ++n; }
        }
    g_object_unref(mem);
    if (n == 0) return false;
    cx = sx / n; cy = sy / n;
    return true;
}

// Apply `spec` to a marked source, then check that map_region_through_geometry
// sends the marker's source position to where the marker ACTUALLY landed.
void expect_mapping_matches(const EditSpec& spec, const char* tag,
                            double tol = 3.0) {
    const int W = 120, H = 80, mx = 34, my = 22;
    VipsImage* in = quadrants_with_marker(W, H, mx, my);
    ASSERT_NE(in, nullptr);
    VipsImage* out = photo::edit::apply_geometry(in, spec);
    ASSERT_NE(out, nullptr);
    double gx = 0, gy = 0;
    const bool visible = find_marker(out, gx, gy);

    photo::edit::Region src;
    src.x = static_cast<float>(mx) / W;
    src.y = static_cast<float>(my) / H;
    src.r = 0.05f;
    photo::edit::Region dst;
    const bool mapped =
        photo::edit::map_region_through_geometry(src, W, H, spec, &dst);

    if (visible) {
        ASSERT_TRUE(mapped) << tag << ": marker visible but mapping dropped it";
        const int OW = vips_image_get_width(out);
        const int OH = vips_image_get_height(out);
        EXPECT_NEAR(dst.x * OW, gx, tol) << tag;
        EXPECT_NEAR(dst.y * OH, gy, tol) << tag;
    } else {
        EXPECT_FALSE(mapped) << tag << ": marker cropped away but mapping kept it";
    }
    g_object_unref(out);
    g_object_unref(in);
}

}  // namespace

TEST(EditGeometry, MapRegionMatchesApplyGeometry) {
    { EditSpec s; s.flipH = true; expect_mapping_matches(s, "flipH"); }
    { EditSpec s; s.flipV = true; expect_mapping_matches(s, "flipV"); }
    { EditSpec s; s.rot90 = 1; expect_mapping_matches(s, "rot90=1"); }
    { EditSpec s; s.rot90 = 2; s.flipV = true; expect_mapping_matches(s, "rot180+flipV"); }
    { EditSpec s; s.rot90 = 3; expect_mapping_matches(s, "rot90=3"); }
    { EditSpec s; s.cropL = 0.1; s.cropT = 0.1; s.cropW = 0.6; s.cropH = 0.7;
      expect_mapping_matches(s, "crop"); }
    { EditSpec s; s.rot90 = 1; s.cropL = 0.05; s.cropT = 0.1; s.cropW = 0.8;
      s.cropH = 0.7; expect_mapping_matches(s, "rot90+crop"); }
    { EditSpec s; s.straighten = 12; expect_mapping_matches(s, "straighten=12"); }
    { EditSpec s; s.straighten = -8; expect_mapping_matches(s, "straighten=-8"); }
    { EditSpec s; s.flipH = true; s.rot90 = 3; s.straighten = 5; s.cropL = 0.05;
      s.cropT = 0.05; s.cropW = 0.85; s.cropH = 0.85;
      expect_mapping_matches(s, "full-chain"); }
    // Marker cropped away entirely → the mapping must DROP the dab.
    { EditSpec s; s.cropL = 0.6; s.cropT = 0.6; s.cropW = 0.4; s.cropH = 0.4;
      expect_mapping_matches(s, "cropped-away"); }
}

TEST(EditGeometry, IdentityReturnsRefNotNull) {
    VipsImage* in = quadrants(20, 20);
    VipsImage* out = photo::edit::apply_geometry(in, EditSpec{});  // identity
    ASSERT_NE(out, nullptr);
    EXPECT_EQ(vips_image_get_width(out), 20);
    g_object_unref(out);  // apply_geometry added a ref even for identity
    g_object_unref(in);
}

TEST(EditTextRender, DrawsGlyphsOntoFrame) {
    FrameBuffer fb;
    fb.width = 240; fb.height = 80; fb.stride = 240 * 4;
    fb.bgra.assign(static_cast<size_t>(240) * 80 * 4, 0);  // black
    for (int i = 0; i < 240 * 80; ++i) fb.bgra[i * 4 + 3] = 255;  // opaque
    EditSpec e;
    TextItem t;
    t.x = 0.5f; t.y = 0.5f; t.size = 0.4f; t.color = 0xFFFFFF; t.text = "Hi!";
    e.texts.push_back(t);
    photo::edit::apply_text(fb, e);
    int bright = 0;
    for (int i = 0; i < 240 * 80; ++i)
        if (fb.bgra[i * 4 + 2] > 128) ++bright;  // white glyph pixels
    EXPECT_GT(bright, 10);
}

// ── Export + layered save (full pipeline through the Engine) ────────────────
#include <chrono>
#include <filesystem>
#include <thread>

#include "photo_core.h"
#include "runtime/engine.h"

namespace exportns = std::filesystem;

namespace {
bool wait_export(photo::Engine& eng, uint64_t req, int timeout_ms = 12000) {
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[32];
    while (steady_clock::now() < deadline) {
        size_t n = eng.events().pop_n(buf, 32);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE && buf[i].request_id == req)
                return buf[i].status == PHOTO_STATUS_OK;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return false;
}

std::unique_ptr<photo::Engine> export_engine(const exportns::path& dir) {
    const auto cat = (dir / "p.db").string();
    const auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return photo::Engine::create(cfg);
}

std::string write_src(const exportns::path& dir, int w, int h) {
    VipsImage* q = quadrants(w, h);
    const auto p = (dir / "src.png").string();
    if (vips_image_write_to_file(q, p.c_str(), nullptr) != 0) vips_error_clear();
    g_object_unref(q);
    return p;
}
}  // namespace

TEST(EditExport, WritesEditedFlattenedCopyAtRightDims) {
    auto dir = exportns::temp_directory_path() / "photo_edit_export";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 120, 80);
    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto out = (dir / "out.jpg").string();
    // Right half + auto-fix: output is ~60x80.
    const uint64_t req =
        eng->export_path(src, out, "crop=0.5,0,0.5,1;autofix=1;", 90);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));
    ASSERT_TRUE(exportns::exists(out));

    VipsImage* got = nullptr;
    ASSERT_EQ(vips_thumbnail(out.c_str(), &got, 4096, "size", VIPS_SIZE_DOWN,
                            nullptr), 0);
    EXPECT_NEAR(vips_image_get_width(got), 60, 2);
    EXPECT_NEAR(vips_image_get_height(got), 80, 2);
    g_object_unref(got);
}

TEST(EditExport, LayeredTiffHasTwoPagesAndEmbeddedSpec) {
    auto dir = exportns::temp_directory_path() / "photo_edit_layered";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 100, 100);
    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto out = (dir / "layered.tif").string();
    const uint64_t req = eng->save_layered(src, out, "rot=1;saturation=30;");
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));
    ASSERT_TRUE(exportns::exists(out));

    // The TIFF must have 2 pages and carry the embedded spec marker.
    VipsImage* tif = vips_image_new_from_file(out.c_str(), "page", 0, nullptr);
    ASSERT_NE(tif, nullptr);
    int n_pages = 0;
    if (vips_image_get_typeof(tif, "n-pages"))
        vips_image_get_int(tif, "n-pages", &n_pages);
    EXPECT_EQ(n_pages, 2);
    if (vips_image_get_typeof(tif, "image-description")) {
        const char* desc = nullptr;
        vips_image_get_string(tif, "image-description", &desc);
        EXPECT_NE(std::string(desc ? desc : "").find("pablo-edit"),
                  std::string::npos);
    }
    g_object_unref(tif);
}

// The layered TIFF's SECOND page is the untouched original — the D1
// reversibility invariant on disk. A heavy edit on page 1 must leave page 2
// byte-equivalent to the source pixels (page 1 exists to look edited; page 2
// exists so the edit can always be re-derived or reverted).
TEST(EditExport, LayeredTiffPreservesOriginalPixelsOnPage2) {
    auto dir = exportns::temp_directory_path() / "photo_edit_layered_orig";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 96, 64);
    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto out = (dir / "layered.tif").string();
    // Desaturate hard so edited != original is unambiguous.
    const uint64_t req = eng->save_layered(src, out, "saturation=-100;");
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));

    VipsImage* orig = vips_image_new_from_file(src.c_str(), nullptr);
    VipsImage* p1 = vips_image_new_from_file(out.c_str(), "page", 0, nullptr);
    VipsImage* p2 = vips_image_new_from_file(out.c_str(), "page", 1, nullptr);
    ASSERT_NE(orig, nullptr);
    ASSERT_NE(p1, nullptr);
    ASSERT_NE(p2, nullptr);

    // Layered pages share one canvas; the source is embedded top-left. Sample
    // inside the source bounds. quadrants() puts saturated red top-left and
    // green top-right.
    auto rgb = [](VipsImage* im, int x, int y, double out3[3]) {
        double* v = nullptr; int n = 0;
        ASSERT_EQ(vips_getpoint(im, &v, &n, x, y, nullptr), 0);
        ASSERT_GE(n, 3);
        out3[0] = v[0]; out3[1] = v[1]; out3[2] = v[2];
        g_free(v);
    };
    double o[3], edited[3], kept[3];
    rgb(orig, 10, 10, o);
    rgb(p1, 10, 10, edited);
    rgb(p2, 10, 10, kept);
    // Page 2 == original (allow codec jitter); page 1 visibly desaturated
    // (red channel pulled toward the grey point).
    for (int c = 0; c < 3; ++c) EXPECT_NEAR(kept[c], o[c], 4.0) << "chan " << c;
    EXPECT_LT(edited[0] - edited[1], (o[0] - o[1]) * 0.5)
        << "page 1 does not look desaturated — edit missing from edited layer";

    g_object_unref(orig);
    g_object_unref(p1);
    g_object_unref(p2);
}

// File-level tone check: the pixels WRITTEN to disk carry the edit (the buffer
// pipeline is unit-tested elsewhere; this pins decode→edit→encode→decode).
TEST(EditExport, ExportedFileCarriesToneEdit) {
    auto dir = exportns::temp_directory_path() / "photo_edit_tone_export";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 80, 80);
    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);

    const auto out = (dir / "grey.jpg").string();
    const uint64_t req = eng->export_path(src, out, "saturation=-100;", 95);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));

    // Fully desaturated: every sampled pixel has near-equal channels, where
    // the source quadrants were saturated primaries.
    VipsImage* got = vips_image_new_from_file(out.c_str(), nullptr);
    ASSERT_NE(got, nullptr);
    for (const auto [x, y] : {std::pair{10, 10}, {70, 10}, {10, 70}, {70, 70}}) {
        double* v = nullptr; int n = 0;
        ASSERT_EQ(vips_getpoint(got, &v, &n, x, y, nullptr), 0);
        ASSERT_GE(n, 3);
        const double spread = std::max({v[0], v[1], v[2]}) -
                              std::min({v[0], v[1], v[2]});
        EXPECT_LT(spread, 12.0) << "pixel (" << x << "," << y
                                << ") still saturated in the written file";
        g_free(v);
    }
    g_object_unref(got);
}


// ── In-place save mode (overwrite with backup, Picasa-style) ────────────────

namespace {
std::vector<char> slurp(const std::string& p) {
    std::ifstream in(p, std::ios::binary);
    return std::vector<char>(std::istreambuf_iterator<char>(in), {});
}

photo_event_t wait_import_ev(photo::Engine& eng, uint64_t req,
                             int timeout_ms = 10000) {
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[32];
    while (steady_clock::now() < deadline) {
        size_t n = eng.events().pop_n(buf, 32);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE &&
                buf[i].request_id == req)
                return buf[i];
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    photo_event_t none{};
    none.status = PHOTO_STATUS_CANCELLED;
    return none;
}

bool wait_import_ok(photo::Engine& eng, uint64_t req, int timeout_ms = 10000) {
    return wait_import_ev(eng, req, timeout_ms).status == PHOTO_STATUS_OK;
}

bool wait_has_backup(photo::Engine& eng, const std::string& src, bool want,
                     int timeout_ms = 10000) {
    using namespace std::chrono;
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    while (steady_clock::now() < deadline) {
        if (eng.has_inplace_backup(src) == want) return true;
        std::this_thread::sleep_for(milliseconds(10));
    }
    return false;
}
}  // namespace

TEST(EditInPlace, SaveBacksUpBakesAndClearsSpecThenRevertRestores) {
    auto dir = exportns::temp_directory_path() / "photo_edit_inplace";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    // JPEG source: the mode's real-world case (same-extension re-encode).
    const std::string png = write_src(dir, 80, 80);
    const std::string src = (dir / "photo.jpg").string();
    {   // transcode the quadrant fixture to jpg via vips
        VipsImage* im = vips_image_new_from_file(png.c_str(), nullptr);
        ASSERT_NE(im, nullptr);
        ASSERT_EQ(vips_image_write_to_file(im, src.c_str(), nullptr), 0);
        g_object_unref(im);
    }
    const std::vector<char> original_bytes = slurp(src);

    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);
    ASSERT_TRUE(wait_import_ok(*eng, eng->import_path(dir.string())));
    int64_t id = 0;
    for (const auto& a : eng->list_assets())
        if (a.path == src) id = a.id;
    ASSERT_GT(id, 0);
    eng->set_starred(id, true);
    ASSERT_GT(eng->set_edits(id, "saturation=-100;"), 0u);

    // Save in place: backup appears, file changes, spec clears (rev stays >0
    // per the kept-row rule so caches rebind).
    EXPECT_FALSE(eng->has_inplace_backup(src));
    const uint64_t req = eng->save_in_place(id, src, "saturation=-100;", 95);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wait_export(*eng, req));
    EXPECT_TRUE(eng->has_inplace_backup(src));
    EXPECT_NE(slurp(src), original_bytes) << "file was not rewritten";
    EXPECT_TRUE(eng->get_edits(id).empty()) << "spec must clear after bake";
    {   // backup holds the pristine original
        const auto backup =
            (dir / ".pablo-originals" / "photo.jpg").string();
        EXPECT_EQ(slurp(backup), original_bytes);
    }

    // Second save must NOT clobber the first backup (first-save-wins).
    ASSERT_GT(eng->set_edits(id, "exposure=30;"), 0u);
    const uint64_t req2 = eng->save_in_place(id, src, "exposure=30;", 95);
    ASSERT_GT(req2, 0u);
    ASSERT_TRUE(wait_export(*eng, req2));
    EXPECT_EQ(slurp((dir / ".pablo-originals" / "photo.jpg").string()),
              original_bytes);

    // Rescan: same id, user state intact, backup dir NOT imported.
    auto ev = wait_import_ev(*eng, eng->rescan());
    ASSERT_EQ(ev.status, PHOTO_STATUS_OK);
    bool found = false;
    for (const auto& a : eng->list_assets()) {
        EXPECT_EQ(a.path.find(".pablo-originals"), std::string::npos)
            << "backup dir leaked into the catalog: " << a.path;
        if (a.path == src) {
            found = true;
            EXPECT_EQ(a.id, id) << "asset identity lost across in-place save";
            EXPECT_TRUE(a.starred);
        }
    }
    EXPECT_TRUE(found);

    // Revert: byte-identical original restored, backup gone.
    const uint64_t req3 = eng->revert_in_place(id, src);
    ASSERT_GT(req3, 0u);
    ASSERT_TRUE(wait_export(*eng, req3));
    EXPECT_EQ(slurp(src), original_bytes);
    EXPECT_FALSE(eng->has_inplace_backup(src));
    EXPECT_TRUE(eng->get_edits(id).empty());
}

TEST(EditInPlace, BackupFailureAbortsWithoutTouchingTheSource) {
    auto dir = exportns::temp_directory_path() / "photo_edit_inplace_abort";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 40, 40);
    const std::vector<char> original_bytes = slurp(src);
    // Occupy the backup path with a FILE so create_directories fails.
    { std::ofstream((dir / ".pablo-originals").string()) << "not a dir"; }

    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);
    ASSERT_TRUE(wait_import_ok(*eng, eng->import_path(dir.string())));
    int64_t id = eng->list_assets().at(0).id;

    const uint64_t req = eng->save_in_place(id, src, "saturation=-100;", 95);
    ASSERT_GT(req, 0u);
    EXPECT_FALSE(wait_export(*eng, req)) << "save must FAIL without a backup";
    EXPECT_EQ(slurp(src), original_bytes) << "source must be untouched";
}

TEST(EditInPlace, RevertWithoutBackupReportsNotFound) {
    auto dir = exportns::temp_directory_path() / "photo_edit_inplace_nf";
    exportns::remove_all(dir);
    exportns::create_directories(dir);
    const std::string src = write_src(dir, 40, 40);
    auto eng = export_engine(dir);
    ASSERT_NE(eng, nullptr);
    ASSERT_TRUE(wait_import_ok(*eng, eng->import_path(dir.string())));
    const uint64_t req = eng->revert_in_place(eng->list_assets().at(0).id, src);
    ASSERT_GT(req, 0u);
    EXPECT_FALSE(wait_export(*eng, req));  // NOT_FOUND status → not OK
}

#endif  // PHOTO_HAVE_VIPS
