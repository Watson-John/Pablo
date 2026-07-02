// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// collage_test.cpp — the §11/collage compositor. Renders solid-colour sources
// into a canvas and checks output dims, per-cell placement (sampled cell-centre
// colours), the background between cells, and the full C-ABI request→event flow.

#include <gtest/gtest.h>

#ifdef PHOTO_HAVE_VIPS

#include <vips/vips.h>

#include <chrono>
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

namespace {

fs::path fresh_dir(const char* tag) {
    auto d = fs::temp_directory_path() / ("photo_collage_" + std::string(tag));
    fs::remove_all(d);
    fs::create_directories(d);
    return d;
}

// Write a solid RGB image to `path`.
std::string solid(const fs::path& dir, const char* name, int w, int h,
                  uint8_t r, uint8_t g, uint8_t b) {
    std::vector<uint8_t> buf(static_cast<size_t>(w) * h * 3);
    for (size_t i = 0; i < buf.size(); i += 3) {
        buf[i] = r; buf[i + 1] = g; buf[i + 2] = b;
    }
    VipsImage* im = vips_image_new_from_memory_copy(buf.data(), buf.size(), w, h,
                                                    3, VIPS_FORMAT_UCHAR);
    const auto p = (dir / name).string();
    if (vips_image_write_to_file(im, p.c_str(), nullptr) != 0) vips_error_clear();
    g_object_unref(im);
    return p;
}

struct Pix {
    int w = 0, h = 0;
    std::vector<uint8_t> rgb;
    void at(int x, int y, int* r, int* g, int* b) const {
        const uint8_t* p = &rgb[(static_cast<size_t>(y) * w + x) * 3];
        *r = p[0]; *g = p[1]; *b = p[2];
    }
};

Pix read_pix(const std::string& path) {
    Pix out;
    VipsImage* im = vips_image_new_from_file(path.c_str(), nullptr);
    if (im == nullptr) { vips_error_clear(); return out; }
    VipsImage* rgb = nullptr;
    if (vips_colourspace(im, &rgb, VIPS_INTERPRETATION_sRGB, nullptr) != 0) {
        vips_error_clear(); g_object_unref(im); return out;
    }
    g_object_unref(im);
    out.w = vips_image_get_width(rgb);
    out.h = vips_image_get_height(rgb);
    size_t n = 0;
    auto* mem = static_cast<uint8_t*>(vips_image_write_to_memory(rgb, &n));
    g_object_unref(rgb);
    if (mem == nullptr) return Pix{};
    out.rgb.assign(mem, mem + n);
    g_free(mem);
    return out;
}

std::unique_ptr<photo::Engine> make_engine(const fs::path& dir) {
    const auto cat = (dir / "p.db").string();
    const auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return photo::Engine::create(cfg);
}

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

struct VipsEnv : ::testing::Environment {
    void SetUp() override { vips_init("collage_test"); }
};
const auto* kEnv = ::testing::AddGlobalTestEnvironment(new VipsEnv);

}  // namespace

TEST(Collage, TwoCellsPlacedWithBackgroundBetween) {
    auto dir = fresh_dir("twocell");
    const std::string red = solid(dir, "red.png", 40, 40, 220, 20, 20);
    const std::string blue = solid(dir, "blue.png", 40, 40, 20, 20, 220);

    photo::ThumbService svc(nullptr, nullptr, nullptr);
    std::vector<photo::ThumbService::CollageCell> cells = {
        {0.05f, 0.30f, 0.40f, 0.40f, red, ""},
        {0.55f, 0.30f, 0.40f, 0.40f, blue, ""},
    };
    const auto out = (dir / "collage.jpg").string();
    ASSERT_TRUE(svc.create_collage(cells, out, 200, 100, 0x00FF00, 95));

    const Pix p = read_pix(out);
    ASSERT_EQ(p.w, 200);
    ASSERT_EQ(p.h, 100);
    int r, g, b;
    // Left cell centre (~x=0.25*200=50, y=0.5*100=50) is red.
    p.at(50, 50, &r, &g, &b);
    EXPECT_GT(r, 150); EXPECT_LT(g, 90); EXPECT_LT(b, 90);
    // Right cell centre (~x=0.75*200=150) is blue.
    p.at(150, 50, &r, &g, &b);
    EXPECT_LT(r, 90); EXPECT_LT(g, 90); EXPECT_GT(b, 150);
    // The gap between the cells (x≈100, top strip y=5) shows the green bg.
    p.at(100, 5, &r, &g, &b);
    EXPECT_LT(r, 90); EXPECT_GT(g, 150); EXPECT_LT(b, 90);
}

TEST(Collage, PerCellEditSpecIsApplied) {
    auto dir = fresh_dir("spec");
    // A green source; a heavy desaturate spec should visibly grey the cell.
    const std::string green = solid(dir, "green.png", 60, 60, 30, 200, 30);
    photo::ThumbService svc(nullptr, nullptr, nullptr);

    const auto plain = (dir / "plain.jpg").string();
    const auto edited = (dir / "edited.jpg").string();
    ASSERT_TRUE(svc.create_collage(
        {{0.0f, 0.0f, 1.0f, 1.0f, green, ""}}, plain, 60, 60, 0, 95));
    ASSERT_TRUE(svc.create_collage(
        {{0.0f, 0.0f, 1.0f, 1.0f, green, "saturation=-100;"}}, edited, 60, 60,
        0, 95));

    int r0, g0, b0, r1, g1, b1;
    read_pix(plain).at(30, 30, &r0, &g0, &b0);
    read_pix(edited).at(30, 30, &r1, &g1, &b1);
    // Desaturating collapses the channels toward each other (grey): the
    // green channel drops sharply vs the un-edited cell.
    EXPECT_GT(g0, 150);
    EXPECT_LT(g1, g0 - 40);
}

TEST(Collage, CApiRequestEmitsExportEvent) {
    auto dir = fresh_dir("capi");
    const std::string a = solid(dir, "a.png", 30, 30, 200, 0, 0);
    const std::string b = solid(dir, "b.png", 30, 30, 0, 0, 200);
    std::string ch, cah;
    ch = (dir / "p.db").string();
    cah = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = ch.c_str();
    cfg.cache_path_utf8 = cah.c_str();
    photo_engine_t* eng = photo_engine_create(&cfg);
    ASSERT_NE(eng, nullptr);

    photo_collage_cell_t cells[2] = {
        {0.0f, 0.0f, 0.5f, 1.0f, a.c_str(), nullptr},
        {0.5f, 0.0f, 0.5f, 1.0f, b.c_str(), nullptr},
    };
    const auto out = (dir / "c.jpg").string();
    const uint64_t req =
        photo_create_collage(eng, cells, 2, out.c_str(), 100, 50, 0, 90);
    ASSERT_GT(req, 0u);

    // Poll the ring through the C ABI.
    bool ok = false;
    const auto deadline = steady_clock::now() + seconds(15);
    photo_event_t buf[16];
    while (!ok && steady_clock::now() < deadline) {
        const size_t n = photo_poll_events(eng, buf, 16);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE &&
                buf[i].request_id == req && buf[i].status == PHOTO_STATUS_OK)
                ok = true;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    EXPECT_TRUE(ok);
    EXPECT_TRUE(fs::exists(out));
    photo_engine_destroy(eng);
}

// The Engine wrapper runs the same job on the idle lane + emits event 11.
TEST(Collage, EngineJobEmitsEvent) {
    auto dir = fresh_dir("engine");
    const std::string a = solid(dir, "a.png", 20, 20, 10, 10, 10);
    auto eng = make_engine(dir);
    ASSERT_NE(eng, nullptr);
    std::vector<photo::ThumbService::CollageCell> cells = {
        {0.1f, 0.1f, 0.8f, 0.8f, a, ""}};
    const auto out = (dir / "e.jpg").string();
    const uint64_t req = eng->create_collage(cells, out, 80, 80, 0xFFFFFF, 90);
    ASSERT_GT(req, 0u);
    EXPECT_TRUE(wait_export(*eng, req));
    EXPECT_TRUE(fs::exists(out));
}

#endif  // PHOTO_HAVE_VIPS
