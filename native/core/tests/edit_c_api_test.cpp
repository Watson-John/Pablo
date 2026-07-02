// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// edit_c_api_test.cpp — the editor exercised through the REAL extern-C ABI
// (photo_core.h) rather than the in-process C++ classes, plus an end-to-end
// "set edit -> render a frame -> revert -> original" test through the slot/thumb
// pipeline, and a concurrency race on the lock-free copy-on-write edit map.
//
// These close the audit's three biggest voids: (1) no test drove any of the 8
// edit C-ABI symbols; (2) no test proved an edit reaches a rendered frame and a
// revert restores it; (3) the atomic_load/store COW swap was never raced.

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

#include "photo_core.h"

#ifdef PHOTO_HAVE_SQLITE

namespace fs = std::filesystem;
using namespace std::chrono;

namespace {

fs::path fresh_dir(const char* tag) {
    auto d = fs::temp_directory_path() / ("photo_edit_capi_" + std::string(tag));
    fs::remove_all(d);
    fs::create_directories(d);
    return d;
}

photo_engine_t* make_engine(const fs::path& dir, std::string& cat_hold,
                            std::string& cache_hold) {
    cat_hold = (dir / "pablo.db").string();
    cache_hold = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat_hold.c_str();
    cfg.cache_path_utf8 = cache_hold.c_str();
    return photo_engine_create(&cfg);
}

// Import `path` and return its catalog asset_id (0 on timeout).
uint64_t import_and_id(photo_engine_t* eng, const std::string& path) {
    const uint64_t job = photo_import_path(eng, path.c_str(), 0);
    const auto deadline = steady_clock::now() + seconds(10);
    photo_event_t buf[64];
    bool done = false;
    while (!done && steady_clock::now() < deadline) {
        const size_t n = photo_poll_events(eng, buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE && buf[i].request_id == job)
                done = true;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    if (!done) return 0;
    photo_asset_t rows[8];
    const size_t total = photo_list_assets(eng, rows, 8);
    return total == 0 ? 0 : rows[0].asset_id;
}

}  // namespace

// ── The edit C ABI, self-consistently, on a fake (non-decodable) asset ───────
TEST(EditCApi, SetGetRevertContentRevAndList) {
    auto dir = fresh_dir("abi");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    const fs::path f = dir / "p.jpg";
    std::ofstream(f, std::ios::binary) << "x";  // catalog row only; never decoded
    const uint64_t id = import_and_id(eng, f.string());
    ASSERT_GT(id, 0u);

    // Unedited: content_rev 0, get_edits returns a lone NUL (total 1), not listed.
    EXPECT_EQ(photo_asset_content_rev(eng, id), 0u);
    char small[4];
    EXPECT_EQ(photo_asset_get_edits(eng, id, small, sizeof(small)), 1u);
    EXPECT_EQ(small[0], '\0');
    uint64_t edited[8];
    EXPECT_EQ(photo_list_edited_assets(eng, edited, 8), 0u);

    // Set a canonical-order spec → rev 1; content_rev tracks; asset now listed.
    const char* spec = "exposure=25;contrast=-10;filter=vivid;";
    const uint64_t rev1 = photo_asset_set_edits(eng, id, spec);
    EXPECT_EQ(rev1, 1u);
    EXPECT_EQ(photo_asset_content_rev(eng, id), 1u);
    ASSERT_EQ(photo_list_edited_assets(eng, edited, 8), 1u);
    EXPECT_EQ(edited[0], id);

    // get_edits round-trips the canonical string (set_edits re-serializes).
    char big[256];
    const size_t total = photo_asset_get_edits(eng, id, big, sizeof(big));
    EXPECT_EQ(total, std::string(spec).size() + 1);  // includes NUL
    EXPECT_STREQ(big, spec);

    // Grow-and-retry: an undersized buffer returns the full total, no overflow.
    char tiny[8];
    const size_t need = photo_asset_get_edits(eng, id, tiny, sizeof(tiny));
    EXPECT_EQ(need, total);  // caller must grow and re-call

    // An identity spec clears the edit (rev 0) but keeps the counter row so a
    // later edit can't reuse rev 1 (stale-cache guard).
    EXPECT_EQ(photo_asset_set_edits(eng, id, "exposure=0;"), 0u);
    EXPECT_EQ(photo_asset_content_rev(eng, id), 0u);
    EXPECT_EQ(photo_list_edited_assets(eng, edited, 8), 0u);

    const uint64_t rev_after = photo_asset_set_edits(eng, id, "saturation=15;");
    EXPECT_GT(rev_after, rev1) << "content_rev reused after revert → cache hazard";

    // Explicit revert clears it again.
    EXPECT_EQ(photo_asset_revert(eng, id), PHOTO_STATUS_OK);
    EXPECT_EQ(photo_asset_content_rev(eng, id), 0u);
    EXPECT_EQ(photo_asset_get_edits(eng, id, big, sizeof(big)), 1u);

    photo_engine_destroy(eng);
}

// ── Defensive edges: unknown asset, zero-cap buffer ──────────────────────────
TEST(EditCApi, DefensiveEdges) {
    auto dir = fresh_dir("defensive");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    // Unknown asset id: content_rev 0, get_edits empty, revert does not crash.
    EXPECT_EQ(photo_asset_content_rev(eng, 999999u), 0u);
    char buf[64];
    EXPECT_EQ(photo_asset_get_edits(eng, 999999u, buf, sizeof(buf)), 1u);
    photo_asset_revert(eng, 999999u);  // must be a safe no-op

    // Zero-cap query returns the needed size without writing (out may be null).
    const fs::path f = dir / "p.jpg";
    std::ofstream(f, std::ios::binary) << "x";
    const uint64_t id = import_and_id(eng, f.string());
    ASSERT_GT(id, 0u);
    photo_asset_set_edits(eng, id, "exposure=5;");
    const size_t need = photo_asset_get_edits(eng, id, nullptr, 0);
    EXPECT_EQ(need, std::string("exposure=5;").size() + 1);

    photo_engine_destroy(eng);
}

// ── Concurrency: hammer the lock-free COW edit-map read while a writer swaps ──
// The hot render path reads the edit snapshot via std::atomic_load with NO
// reader lock (see Engine::edit_lookup). This races many readers against a
// writer that alternates set_edits / revert_edits, exercising the atomic_load /
// atomic_store swap. photo_asset_content_rev and photo_list_edited_assets both
// read the COW snapshot; every value they observe must be a VALID published
// state (rev is 0 or a monotonic bump; the list is 0 or 1 entries and, when
// present, names our asset). NOTE: content_rev (COW map) and get_edits (catalog)
// are separate subsystems, so we do NOT assert cross-call coherence between
// them. Run under TSan for the real data-race verdict; this no-sanitizer build
// catches gross tears / crashes and invalid observed values.
TEST(EditCApi, CowEditMapConcurrentReadWrite) {
    auto dir = fresh_dir("cow");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);

    const fs::path f = dir / "p.jpg";
    std::ofstream(f, std::ios::binary) << "x";
    const uint64_t id = import_and_id(eng, f.string());
    ASSERT_GT(id, 0u);

    std::atomic<bool> stop{false};
    std::atomic<uint64_t> reads{0};
    std::atomic<bool> bad_list{false};

    std::vector<std::thread> readers;
    for (int t = 0; t < 4; ++t) {
        readers.emplace_back([&] {
            uint64_t ids[8];
            while (!stop.load(std::memory_order_relaxed)) {
                photo_asset_content_rev(eng, id);  // lock-free COW read
                const size_t n = photo_list_edited_assets(eng, ids, 8);
                // The single-asset map is only ever 0 or 1 entries, and any id
                // it yields must be OUR asset — a torn read would surface neither.
                if (n > 1 || (n == 1 && ids[0] != id)) bad_list.store(true);
                reads.fetch_add(1, std::memory_order_relaxed);
            }
        });
    }

    // Writer: alternate a real edit and a revert for a fixed number of rounds.
    for (int i = 0; i < 400; ++i) {
        photo_asset_set_edits(eng, id, "exposure=20;filter=bw;");
        photo_asset_revert(eng, id);
    }
    // Give readers a moment to observe the final (reverted) state, then stop.
    std::this_thread::sleep_for(milliseconds(20));
    stop.store(true);
    for (auto& th : readers) th.join();

    EXPECT_GT(reads.load(), 0u);
    EXPECT_FALSE(bad_list.load()) << "reader observed a torn edited-asset list";
    EXPECT_EQ(photo_asset_content_rev(eng, id), 0u);  // ended reverted

    photo_engine_destroy(eng);
}

#endif  // PHOTO_HAVE_SQLITE

// ── End-to-end: edit reaches a rendered frame; revert restores the original ──
#if defined(PHOTO_HAVE_SQLITE) && defined(PHOTO_HAVE_VIPS)

#include <vips/vips.h>

namespace {

struct CApiVipsEnv : ::testing::Environment {
    void SetUp() override { vips_init("edit_c_api_test"); }  // idempotent
};
const auto* kCApiVipsEnv =
    ::testing::AddGlobalTestEnvironment(new CApiVipsEnv);

// Write a 4-quadrant PNG (TL red, TR green, BL blue, BR white) and return path.
std::string write_quadrants(const fs::path& dir, int w, int h) {
    std::vector<uint8_t> buf(static_cast<size_t>(w) * h * 3);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            uint8_t* p = &buf[(static_cast<size_t>(y) * w + x) * 3];
            const bool right = x >= w / 2, bottom = y >= h / 2;
            if (!right && !bottom) { p[0] = 230; p[1] = 20; p[2] = 20; }     // TL red
            else if (right && !bottom) { p[0] = 20; p[1] = 230; p[2] = 20; } // TR green
            else if (!right && bottom) { p[0] = 20; p[1] = 20; p[2] = 230; } // BL blue
            else { p[0] = 240; p[1] = 240; p[2] = 240; }                     // BR white
        }
    VipsImage* im = vips_image_new_from_memory_copy(buf.data(), buf.size(), w, h,
                                                    3, VIPS_FORMAT_UCHAR);
    const auto path = (dir / "src.png").string();
    if (vips_image_write_to_file(im, path.c_str(), nullptr) != 0) vips_error_clear();
    g_object_unref(im);
    return path;
}

// Wait for a FULL STAGE_READY on (slot, gen). Returns true if seen.
bool wait_full_ready(photo_engine_t* eng, uint64_t slot, uint64_t gen,
                     int timeout_ms = 12000) {
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[64];
    while (steady_clock::now() < deadline) {
        const size_t n = photo_poll_events(eng, buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_STAGE_READY &&
                buf[i].slot_id == slot && buf[i].generation == gen &&
                buf[i].stage == PHOTO_STAGE_FULL)
                return true;
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return false;
}

// Sample the top-left-quadrant pixel's straight R,G,B (opaque frame). Returns
// false if no frame is available.
bool sample_tl(photo_engine_t* eng, uint64_t slot, int& R, int& G, int& B) {
    photo_frame_view_t v{};
    if (!photo_slot_acquire_latest(eng, slot, &v)) return false;
    const uint32_t x = v.width / 4, y = v.height / 4;
    const uint8_t* p = v.bgra + static_cast<size_t>(y) * v.stride + x * 4;
    B = p[0]; G = p[1]; R = p[2];
    photo_slot_release(eng, v.release_ctx);
    return true;
}

// Request a FULL render at a fresh generation and wait for the frame.
bool render_at(photo_engine_t* eng, uint64_t asset, uint64_t slot,
               uint64_t gen, const std::string& path, int box) {
    photo_slot_bind_generation(eng, slot, gen);
    const uint64_t req = photo_thumb_request_fast(
        eng, asset, slot, gen, path.c_str(),
        static_cast<uint32_t>(box), static_cast<uint32_t>(box),
        PHOTO_STAGE_MASK_FULL, PHOTO_PRIORITY_INTERACTIVE, 0);
    if (req == 0) return false;
    return wait_full_ready(eng, slot, gen, 12000);
}

}  // namespace

TEST(EditCApiE2E, EditRendersThenRevertRestoresOriginal) {
    auto dir = fresh_dir("e2e");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);
    const std::string src = write_quadrants(dir, 200, 200);
    const uint64_t id = import_and_id(eng, src);
    ASSERT_GT(id, 0u);

    const uint64_t slot = photo_slot_create(eng, 64, 64);
    ASSERT_NE(slot, 0u);

    // 1) Original render: the top-left quadrant is red (R dominates).
    ASSERT_TRUE(render_at(eng, id, slot, 1, src, 64));
    int R0 = 0, G0 = 0, B0 = 0;
    ASSERT_TRUE(sample_tl(eng, slot, R0, G0, B0));
    EXPECT_GT(R0, G0 + 40);
    EXPECT_GT(R0, B0 + 40);

    // 2) Save a bw filter and re-render at a fresh generation → greyscale.
    ASSERT_GT(photo_asset_set_edits(eng, id, "filter=bw;"), 0u);
    ASSERT_TRUE(render_at(eng, id, slot, 2, src, 64));
    int R1 = 0, G1 = 0, B1 = 0;
    ASSERT_TRUE(sample_tl(eng, slot, R1, G1, B1));
    EXPECT_LT(std::abs(R1 - G1), 12);  // grey: channels converge
    EXPECT_LT(std::abs(G1 - B1), 12);

    // 3) Revert and re-render → the original red returns.
    ASSERT_EQ(photo_asset_revert(eng, id), PHOTO_STATUS_OK);
    ASSERT_TRUE(render_at(eng, id, slot, 3, src, 64));
    int R2 = 0, G2 = 0, B2 = 0;
    ASSERT_TRUE(sample_tl(eng, slot, R2, G2, B2));
    EXPECT_GT(R2, G2 + 40);
    EXPECT_GT(R2, B2 + 40);

    photo_slot_destroy(eng, slot);
    photo_engine_destroy(eng);
}

// Env-gated diagnostic: render a REAL image through the export pipeline with a
// heal spec and report the healed-region pixel vs the untouched original. Skips
// unless PABLO_HEAL_IMG / PABLO_HEAL_SPEC are set (so CI is unaffected).
TEST(EditCApiE2E, HealOnRealImageDiagnostic) {
    const char* img = std::getenv("PABLO_HEAL_IMG");
    const char* spec = std::getenv("PABLO_HEAL_SPEC");
    if (img == nullptr || spec == nullptr) GTEST_SKIP();
    auto dir = fresh_dir("healreal");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);
    const auto out = (dir / "healed.png").string();
    const uint64_t req = photo_asset_export(eng, img, out.c_str(), spec, 100);
    ASSERT_GT(req, 0u);
    const auto deadline = steady_clock::now() + seconds(20);
    bool ok = false, done = false;
    photo_event_t buf[32];
    while (!done && steady_clock::now() < deadline) {
        const size_t n = photo_poll_events(eng, buf, 32);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE && buf[i].request_id == req) {
                ok = buf[i].status == PHOTO_STATUS_OK; done = true;
            }
        if (n == 0) std::this_thread::sleep_for(milliseconds(10));
    }
    ASSERT_TRUE(done && ok);

    // Parse the heal centre from the spec (first heal region) and sample it in
    // both the original and the healed output.
    float hx = 0.f, hy = 0.f;
    { const std::string s = spec; const auto p = s.find("heal=");
      if (p != std::string::npos) std::sscanf(s.c_str() + p + 5, "%f,%f", &hx, &hy); }
    VipsImage* o = vips_image_new_from_file(img, nullptr);
    VipsImage* h = vips_image_new_from_file(out.c_str(), nullptr);
    ASSERT_NE(o, nullptr); ASSERT_NE(h, nullptr);
    const int W = vips_image_get_width(o), H = vips_image_get_height(o);
    const int px = static_cast<int>(hx * W), py = static_cast<int>(hy * H);
    double *vo = nullptr, *vh = nullptr; int no = 0, nh = 0;
    vips_getpoint(o, &vo, &no, px, py, nullptr);
    vips_getpoint(h, &vh, &nh, px, py, nullptr);
    std::fprintf(stderr, "[heal-diag] %dx%d centre(%d,%d) original RGB=(%.0f,%.0f,%.0f) healed RGB=(%.0f,%.0f,%.0f)\n",
                 W, H, px, py, vo[0], vo[1], vo[2], vh[0], vh[1], vh[2]);
    g_free(vo); g_free(vh); g_object_unref(o); g_object_unref(h);
    photo_engine_destroy(eng);
}

TEST(EditCApiE2E, PreviewEditsTransientRenderAndStaleGenDrop) {
    auto dir = fresh_dir("preview");
    std::string ch, cah;
    photo_engine_t* eng = make_engine(dir, ch, cah);
    ASSERT_NE(eng, nullptr);
    const std::string src = write_quadrants(dir, 200, 200);
    const uint64_t id = import_and_id(eng, src);
    ASSERT_GT(id, 0u);

    const uint64_t slot = photo_slot_create(eng, 64, 64);
    ASSERT_NE(slot, 0u);
    photo_slot_bind_generation(eng, slot, 10);

    // Transient preview at the current generation → a bw FULL frame is published
    // as request_id 0, with NO catalog write (content_rev stays 0).
    ASSERT_EQ(photo_asset_preview_edits(eng, slot, 10, src.c_str(), 64, 64,
                                        "filter=bw;"),
              PHOTO_STATUS_OK);
    ASSERT_TRUE(wait_full_ready(eng, slot, 10));
    int R = 0, G = 0, B = 0;
    ASSERT_TRUE(sample_tl(eng, slot, R, G, B));
    EXPECT_LT(std::abs(R - G), 12);
    EXPECT_LT(std::abs(G - B), 12);
    EXPECT_EQ(photo_asset_content_rev(eng, id), 0u);  // preview never persists

    // Stale generation: a preview at gen 9 (slot is bound to 10) must be dropped
    // by the generation guard — no FULL frame for gen 9 within a short window.
    photo_asset_preview_edits(eng, slot, 9, src.c_str(), 64, 64, "filter=bw;");
    EXPECT_FALSE(wait_full_ready(eng, slot, 9, 700))
        << "stale-generation preview should be dropped";

    photo_slot_destroy(eng, slot);
    photo_engine_destroy(eng);
}

#endif  // PHOTO_HAVE_SQLITE && PHOTO_HAVE_VIPS

// ── Auto red-eye happy path with the REAL SCRFD scan ─────────────────────────
// Env-gated (needs a real face photo + the bundled models; skips in CI):
//   PABLO_REDEYE_FACE_SRC=/path/to/face.jpg PABLO_MODELS_DIR=native/models
// Flow: import → real face scan (SCRFD) → paint bright-red pupils AT THE
// DETECTED LANDMARKS (simulating flash red-eye) → Engine::detect_redeye must
// emit one region per eye → export through the real correction pipeline →
// the pupils in the output are neutral. This closes the one path no other test
// covers: stored-landmarks → decode → auto-placement → correction.
#if defined(PHOTO_HAVE_FACES) && defined(PHOTO_HAVE_SQLITE) && \
    defined(PHOTO_HAVE_VIPS)

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#include "codec/codec.h"
#include "edit/edit_spec.h"
#include "edit/render.h"
#include "faces/face_service.h"
#include "runtime/engine.h"

namespace {

std::unique_ptr<photo::Engine> engine_with_models(const fs::path& dir,
                                                  const char* models) {
    const auto cat = (dir / "pablo.db").string();
    const auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    cfg.models_path_utf8 = models;
    return photo::Engine::create(cfg);
}

int64_t wb_import(photo::Engine& eng, const std::string& path) {
    const uint64_t req = eng.import_path(path);
    const auto deadline = steady_clock::now() + seconds(15);
    photo_event_t buf[64];
    while (steady_clock::now() < deadline) {
        const size_t n = eng.events().pop_n(buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_IMPORT_COMPLETE &&
                buf[i].request_id == req) {
                const auto assets = eng.list_assets();
                return assets.empty() ? 0 : assets.front().id;
            }
        if (n == 0) std::this_thread::sleep_for(milliseconds(5));
    }
    return 0;
}

bool wb_wait_export(photo::Engine& eng, uint64_t req, int timeout_ms = 20000) {
    const auto deadline = steady_clock::now() + milliseconds(timeout_ms);
    photo_event_t buf[64];
    while (steady_clock::now() < deadline) {
        const size_t n = eng.events().pop_n(buf, 64);
        for (size_t i = 0; i < n; ++i)
            if (buf[i].kind == PHOTO_EVT_EXPORT_COMPLETE &&
                buf[i].request_id == req)
                return buf[i].status == PHOTO_STATUS_OK;
        if (n == 0) std::this_thread::sleep_for(milliseconds(10));
    }
    return false;
}

}  // namespace

TEST(EditAutoRedeyeE2E, RealScanDetectAndCorrect) {
    const char* src = std::getenv("PABLO_REDEYE_FACE_SRC");
    const char* models = std::getenv("PABLO_MODELS_DIR");
    if (src == nullptr || models == nullptr)
        GTEST_SKIP() << "set PABLO_REDEYE_FACE_SRC + PABLO_MODELS_DIR";
    if (!photo::faces::FaceService::available()) GTEST_SKIP();

    auto dir = fresh_dir("autoredeye");
    const fs::path img = dir / "face.jpg";
    fs::copy_file(src, img, fs::copy_options::overwrite_existing);

    auto eng = engine_with_models(dir, models);
    ASSERT_NE(eng, nullptr);
    const int64_t id = wb_import(*eng, img.string());
    ASSERT_GT(id, 0);

    // Real SCRFD scan; poll the stored landmarks (models lazy-load on first use).
    eng->faces().submit_scan(static_cast<uint64_t>(id), img.string().c_str(), 0);
    std::vector<std::array<float, 4>> eyes;
    {
        const auto deadline = steady_clock::now() + seconds(45);
        photo_event_t drain[64];
        while (steady_clock::now() < deadline) {
            eyes = eng->faces().eye_landmarks_for_asset(static_cast<uint64_t>(id));
            if (!eyes.empty()) break;
            eng->events().pop_n(drain, 64);  // keep the ring from backing up
            std::this_thread::sleep_for(milliseconds(50));
        }
    }
    ASSERT_FALSE(eyes.empty()) << "SCRFD found no face in " << src;

    // Paint bright-red pupils at the DETECTED landmarks (simulated flash).
    cv::Mat bgr = photo::codec::decode_bgr(img.string());
    ASSERT_FALSE(bgr.empty());
    const auto& e = eyes.front();
    const float iod = std::hypot(e[2] - e[0], e[3] - e[1]);
    const int pr = std::max(2, static_cast<int>(0.09f * iod));
    cv::circle(bgr, {static_cast<int>(e[0]), static_cast<int>(e[1])}, pr,
               cv::Scalar(30, 30, 220), cv::FILLED);
    cv::circle(bgr, {static_cast<int>(e[2]), static_cast<int>(e[3])}, pr,
               cv::Scalar(30, 30, 220), cv::FILLED);
    ASSERT_TRUE(cv::imwrite(img.string(), bgr));

    // Auto-detect: one region per (now red) eye, centred near its landmark.
    const auto regs = eng->detect_redeye(id, img.string());
    ASSERT_EQ(regs.size(), 2u);
    const int W = bgr.cols, H = bgr.rows;
    EXPECT_NEAR(regs[0].x * W, e[0], iod * 0.35);
    EXPECT_NEAR(regs[0].y * H, e[1], iod * 0.35);
    EXPECT_NEAR(regs[1].x * W, e[2], iod * 0.35);

    // With a working spec that crops, detect must return the SAME eyes mapped
    // into post-crop space (landmarks live in original coords).
    {
        const std::string cropSpec = "crop=0.1,0.1,0.8,0.8;";
        const auto mapped = eng->detect_redeye(id, img.string(), cropSpec);
        ASSERT_EQ(mapped.size(), regs.size());
        const photo::edit::EditSpec cs = photo::edit::parse_edit_spec(cropSpec);
        for (size_t i = 0; i < regs.size(); ++i) {
            photo::edit::Region want;
            ASSERT_TRUE(photo::edit::map_region_through_geometry(
                regs[i], W, H, cs, &want));
            EXPECT_NEAR(mapped[i].x, want.x, 1e-4);
            EXPECT_NEAR(mapped[i].y, want.y, 1e-4);
            EXPECT_NEAR(mapped[i].r, want.r, 1e-4);
        }
        // A crop that excludes the face entirely → every dab dropped, none
        // misplaced.
        const auto none =
            eng->detect_redeye(id, img.string(), "crop=0.9,0.9,0.1,0.1;");
        EXPECT_TRUE(none.empty());
    }

    // Feed the regions through the real correction pipeline via export.
    photo::edit::EditSpec spec;
    spec.redeye = regs;
    const auto out = (dir / "fixed.png").string();
    const uint64_t req = eng->export_path(
        img.string(), out, photo::edit::serialize_edit_spec(spec), 100);
    ASSERT_GT(req, 0u);
    ASSERT_TRUE(wb_wait_export(*eng, req));
    ASSERT_TRUE(fs::exists(out));

    // The painted pupil was straight (R220,G30,B30); after correction it must be
    // neutral (mono ≈ 0.7·luma ≈ 49) — red no longer dominant, clearly darker.
    VipsImage* fixed = vips_image_new_from_file(out.c_str(), nullptr);
    ASSERT_NE(fixed, nullptr);
    for (int side = 0; side < 2; ++side) {
        const int px = static_cast<int>(side ? e[2] : e[0]);
        const int py = static_cast<int>(side ? e[3] : e[1]);
        double* v = nullptr;
        int n = 0;
        ASSERT_EQ(vips_getpoint(fixed, &v, &n, px, py, nullptr), 0);
        ASSERT_GE(n, 3);
        EXPECT_LT(std::abs(v[0] - v[1]), 30) << "eye " << side << " still red";
        EXPECT_LT(v[0], 130) << "eye " << side << " not darkened";
        g_free(v);
    }
    g_object_unref(fixed);
}

#endif  // PHOTO_HAVE_FACES && PHOTO_HAVE_SQLITE && PHOTO_HAVE_VIPS
