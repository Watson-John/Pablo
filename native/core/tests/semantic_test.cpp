// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// semantic_test.cpp — the Stage 9 embedding backend, cosine search, and the
// per-asset service. Dependency-free: exercises the deterministic embedder on
// synthetic pixel buffers and the service with an injected decoder, so it runs
// in the lean faces-off / no-codec test build.

#include <gtest/gtest.h>

#include <cmath>
#include <fstream>
#include <string>
#include <vector>

#include "catalog/catalog.h"
#include "semantic/embedder.h"
#include "semantic/semantic_search.h"
#include "semantic/semantic_service.h"

using photo::catalog::Catalog;
using photo::semantic::cosine_rank;
using photo::semantic::Embedder;
using photo::semantic::make_deterministic_embedder;
using photo::semantic::PixelView;
using photo::semantic::SearchHit;
using photo::semantic::SemanticService;

namespace {

std::vector<uint8_t> solid(int w, int h, uint8_t r, uint8_t g, uint8_t b) {
    std::vector<uint8_t> px(static_cast<size_t>(w) * h * 4);
    for (size_t i = 0; i < px.size(); i += 4) {
        px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = 255;
    }
    return px;
}

std::vector<float> embed_solid(const Embedder& e, uint8_t r, uint8_t g, uint8_t b) {
    auto buf = solid(16, 16, r, g, b);
    PixelView v;
    v.pixels = buf.data(); v.width = 16; v.height = 16; v.channels = 4;
    return e.embed_image(v);
}

float dot(const std::vector<float>& a, const std::vector<float>& b) {
    float s = 0;
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) s += a[i] * b[i];
    return s;
}

}  // namespace

TEST(Semantic, ImageEmbeddingIsDeterministicAndNormalized) {
    auto e = make_deterministic_embedder();
    auto v1 = embed_solid(*e, 200, 30, 30);
    auto v2 = embed_solid(*e, 200, 30, 30);
    ASSERT_EQ(v1.size(), static_cast<size_t>(e->dim()));
    EXPECT_EQ(v1, v2);  // deterministic
    double norm = 0;
    for (float x : v1) norm += static_cast<double>(x) * x;
    EXPECT_NEAR(std::sqrt(norm), 1.0, 1e-4);  // L2-normalized
}

TEST(Semantic, TextRanksColourMatchingImagesHigher) {
    auto e = make_deterministic_embedder();
    const auto red = embed_solid(*e, 230, 20, 20);
    const auto blue = embed_solid(*e, 20, 20, 230);
    const auto green = embed_solid(*e, 20, 150, 40);

    // "red" prefers the red image over the blue one.
    const auto qred = e->embed_text("red");
    EXPECT_GT(dot(qred, red), dot(qred, blue));

    // "blue" / "sky" prefers the blue image over the green one.
    const auto qblue = e->embed_text("blue sky");
    EXPECT_GT(dot(qblue, blue), dot(qblue, green));

    // "tree" (foliage/green) prefers the green image over the red one.
    const auto qtree = e->embed_text("tree");
    EXPECT_GT(dot(qtree, green), dot(qtree, red));
}

TEST(Semantic, UnknownQueryFallsBackToNeutralNotEmpty) {
    auto e = make_deterministic_embedder();
    const auto q = e->embed_text("aardvark xyzzy");  // no colour signal
    ASSERT_EQ(q.size(), static_cast<size_t>(e->dim()));
    double norm = 0;
    for (float x : q) norm += static_cast<double>(x) * x;
    EXPECT_NEAR(std::sqrt(norm), 1.0, 1e-4);  // normalized, not all-zero
}

TEST(Semantic, CosineRankOrdersAndFiltersAndCaps) {
    std::vector<Catalog::EmbeddingVec> items = {
        {10, {1.0f, 0.0f, 0.0f}},
        {11, {0.0f, 1.0f, 0.0f}},
        {12, {0.8f, 0.2f, 0.0f}},
    };
    const std::vector<float> query = {1.0f, 0.0f, 0.0f};

    auto hits = cosine_rank(query, items, /*candidates=*/{}, /*cap=*/10);
    ASSERT_EQ(hits.size(), 3u);
    EXPECT_EQ(hits[0].asset_id, 10);  // exact match ranks first
    EXPECT_EQ(hits[1].asset_id, 12);  // partial next
    EXPECT_EQ(hits[2].asset_id, 11);

    // cap
    EXPECT_EQ(cosine_rank(query, items, {}, 2).size(), 2u);

    // candidate restriction: only 11 and 12 are eligible.
    auto restricted = cosine_rank(query, items, {11, 12}, 10);
    ASSERT_EQ(restricted.size(), 2u);
    EXPECT_EQ(restricted[0].asset_id, 12);
    EXPECT_EQ(restricted[1].asset_id, 11);
}

TEST(Semantic, CosineRankIgnoresDimMismatch) {
    std::vector<Catalog::EmbeddingVec> items = {
        {1, {1.0f, 0.0f}},          // wrong dim → ignored
        {2, {1.0f, 0.0f, 0.0f}},    // right dim
    };
    auto hits = cosine_rank({1.0f, 0.0f, 0.0f}, items, {}, 10);
    ASSERT_EQ(hits.size(), 1u);
    EXPECT_EQ(hits[0].asset_id, 2);
}

TEST(Semantic, ServiceEmbedsAssetWithInjectedDecoder) {
    auto decode = [](const std::string&, int, std::vector<uint8_t>& rgba, int& w,
                     int& h) {
        w = 8; h = 8; rgba = solid(8, 8, 230, 20, 20); return true;
    };
    SemanticService svc(make_deterministic_embedder(), decode);
    const auto rec = svc.embed_asset(42, "/lib/red.jpg");
    EXPECT_EQ(rec.asset_id, 42);
    EXPECT_EQ(rec.status, Catalog::kEmbedDone);
    EXPECT_FALSE(rec.vec.empty());
    EXPECT_EQ(rec.model_id, "deterministic-color");
    EXPECT_TRUE(rec.error.empty());
    EXPECT_GT((rec.dominant_rgb >> 16) & 0xff, 200);  // dominant colour ~red
}

TEST(Semantic, ServiceReportsFailedOnDecodeError) {
    auto bad = [](const std::string&, int, std::vector<uint8_t>&, int&, int&) {
        return false;  // corrupt / unsupported image
    };
    SemanticService svc(make_deterministic_embedder(), bad);
    const auto rec = svc.embed_asset(7, "/lib/broken.jpg");
    EXPECT_EQ(rec.status, Catalog::kEmbedFailed);
    EXPECT_FALSE(rec.error.empty());
    EXPECT_TRUE(rec.vec.empty());  // one bad image can't wedge the run
}

TEST(Semantic, ServiceSkipsWhenNoDecoderAndNoInjection) {
    // No injected decoder + lean build (no codec) → Skipped, not Failed.
    SemanticService svc(make_deterministic_embedder());
    const auto rec = svc.embed_asset(1, "/lib/x.jpg");
    if (!SemanticService::has_builtin_decoder())
        EXPECT_EQ(rec.status, Catalog::kEmbedSkipped);
}

// ── Engine-level: the semantic-search RAM cache (COW working set) ────────────
//
// Engine::semantic_search must NOT re-read every embedding BLOB from SQLite on
// each query. Contract under test: (1) results come from a cached snapshot —
// a write through a SECOND catalog connection (which the engine cannot see) is
// invisible to subsequent searches; (2) an engine-side write path
// (retry_failed_embeddings, the documented re-sync hook) invalidates the cache
// and the next search reflects the external row.

#ifdef PHOTO_HAVE_SQLITE

#include <filesystem>

#include "photo_core.h"
#include "runtime/engine.h"

namespace {

namespace fs = std::filesystem;

std::unique_ptr<photo::Engine> engine_at(const fs::path& dir) {
    const auto cat = (dir / "pablo.db").string();
    const auto cache = (dir / "cache").string();
    photo_config_t cfg{};
    cfg.catalog_path_utf8 = cat.c_str();
    cfg.cache_path_utf8 = cache.c_str();
    return photo::Engine::create(cfg);
}

Catalog::EmbeddingRecord done_rec(int64_t asset_id, std::vector<float> vec) {
    Catalog::EmbeddingRecord r;
    r.asset_id = asset_id;
    r.model_id = "m";
    r.model_version = "1";
    r.dim = static_cast<int>(vec.size());
    r.vec = std::move(vec);
    r.status = Catalog::kEmbedDone;
    return r;
}

}  // namespace

TEST(SemanticEngine, SearchCachesWorkingSetAndInvalidatesOnEngineWrite) {
    const auto dir = fs::temp_directory_path() / "photo_semantic_engine_cache";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const auto db = (dir / "pablo.db").string();

    // Seed one asset + one Done embedding BEFORE the engine opens the catalog.
    int64_t ida = 0;
    {
        Catalog cat(db);
        photo::catalog::AssetRecord a;
        a.path = "/lib/a.jpg"; a.folder = "/lib"; a.filename = "a.jpg";
        a.size = 1; a.mtime_ns = 1; a.format = "jpeg"; a.import_time = 1;
        ida = cat.upsert_asset(a);
        cat.upsert_embedding(done_rec(ida, {1.0f, 0.0f}));
    }

    auto eng = engine_at(dir);
    ASSERT_NE(eng, nullptr);

    // First search: lazily builds the RAM cache from the catalog.
    const std::vector<float> q{1.0f, 0.0f};
    auto hits = eng->semantic_search(q, {}, 10);
    ASSERT_EQ(hits.size(), 1u);
    EXPECT_EQ(hits[0].asset_id, ida);

    // External write through a SECOND connection — the engine can't see it, so
    // the cached snapshot (correctly) still serves. This asserts the cache is
    // real: pre-cache code re-read the DB every query and would return 2 hits.
    int64_t idb = 0;
    {
        Catalog cat2(db);
        photo::catalog::AssetRecord b;
        b.path = "/lib/b.jpg"; b.folder = "/lib"; b.filename = "b.jpg";
        b.size = 1; b.mtime_ns = 1; b.format = "jpeg"; b.import_time = 1;
        idb = cat2.upsert_asset(b);
        cat2.upsert_embedding(done_rec(idb, {0.9f, 0.1f}));
    }
    hits = eng->semantic_search(q, {}, 10);
    EXPECT_EQ(hits.size(), 1u) << "cache should serve the snapshot, not re-read";

    // Engine-side write path invalidates → next search rebuilds and sees both.
    eng->retry_failed_embeddings();
    hits = eng->semantic_search(q, {}, 10);
    ASSERT_EQ(hits.size(), 2u);
    EXPECT_EQ(hits[0].asset_id, ida);  // exact match ranks above the off-axis vec

    // Candidate filtering still applies on the cached set.
    auto only_b = eng->semantic_search(q, {idb}, 10);
    ASSERT_EQ(only_b.size(), 1u);
    EXPECT_EQ(only_b[0].asset_id, idb);
}

#endif  // PHOTO_HAVE_SQLITE

// ── SidecarIndex: the disk-resident int8 search index ────────────────────────

#ifdef PHOTO_HAVE_SQLITE

#include "semantic/semantic_search.h"

namespace {

using photo::semantic::SidecarIndex;

Catalog::EmbeddingVec ev(int64_t id, std::vector<float> v) {
    Catalog::EmbeddingVec e;
    e.asset_id = id;
    e.vec = std::move(v);
    return e;
}

std::vector<float> unit(std::vector<float> v) {
    double s = 0;
    for (float x : v) s += double(x) * x;
    const float n = float(std::sqrt(s));
    for (float& x : v) x /= n;
    return v;
}

}  // namespace

TEST(SidecarIndex, RoundTripMatchesFp32Ranking) {
    const auto dir = fs::temp_directory_path() / "photo_sidecar_unit";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const std::string path = (dir / "semantic_index.bin").string();

    // A small set of L2-normalized vectors with a known ranking for the query.
    std::vector<Catalog::EmbeddingVec> items;
    items.push_back(ev(1, unit({1.0f, 0.0f, 0.0f, 0.0f})));
    items.push_back(ev(2, unit({0.9f, 0.4f, 0.1f, 0.0f})));
    items.push_back(ev(3, unit({0.0f, 1.0f, 0.0f, 0.0f})));
    items.push_back(ev(4, unit({0.5f, 0.5f, 0.5f, 0.5f})));
    items.push_back(ev(5, {0.1f, 0.2f}));  // wrong dim → skipped at write

    Catalog::EmbeddingStamp st;
    st.count = 4;
    st.max_updated_ns = 777;
    const uint64_t mh = SidecarIndex::model_hash("m", "1", 4);
    ASSERT_TRUE(SidecarIndex::write(path, items, 4, mh, st));

    auto idx = SidecarIndex::open(path);
    ASSERT_NE(idx, nullptr);
    EXPECT_EQ(idx->dim(), 4);
    EXPECT_EQ(idx->count(), 4);  // the 2-dim row was dropped
    EXPECT_EQ(idx->stamp_model_hash(), mh);
    EXPECT_EQ(idx->stamp_count(), 4);
    EXPECT_EQ(idx->stamp_max_updated_ns(), 777);

    const auto query = unit({1.0f, 0.1f, 0.0f, 0.0f});
    const auto got = idx->scan(query, {}, 10);
    const auto want = photo::semantic::cosine_rank(query, items, {}, 10);
    ASSERT_EQ(got.size(), 4u);
    ASSERT_EQ(want.size(), 4u);
    for (size_t i = 0; i < got.size(); ++i) {
        EXPECT_EQ(got[i].asset_id, want[i].asset_id) << "rank " << i;
        EXPECT_NEAR(got[i].score, want[i].score, 0.02f) << "rank " << i;
    }

    // Candidate filter applies on the mapped rows too.
    const auto only = idx->scan(query, {3}, 10);
    ASSERT_EQ(only.size(), 1u);
    EXPECT_EQ(only[0].asset_id, 3);
}

TEST(SidecarIndex, RejectsCorruptAndTruncatedFiles) {
    const auto dir = fs::temp_directory_path() / "photo_sidecar_corrupt";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const std::string path = (dir / "semantic_index.bin").string();

    EXPECT_EQ(SidecarIndex::open(path), nullptr);  // missing

    {
        std::ofstream f(path, std::ios::binary);
        f << "not a sidecar file";
    }
    EXPECT_EQ(SidecarIndex::open(path), nullptr);  // bad magic

    std::vector<Catalog::EmbeddingVec> items{ev(1, unit({1.0f, 0.0f}))};
    ASSERT_TRUE(SidecarIndex::write(path, items, 2,
                                    SidecarIndex::model_hash("m", "1", 2), {}));
    ASSERT_NE(SidecarIndex::open(path), nullptr);
    fs::resize_file(path, fs::file_size(path) - 4);  // truncate a row
    EXPECT_EQ(SidecarIndex::open(path), nullptr);
}

TEST(SemanticEngine, SidecarPersistsAndRefreshesAcrossRestart) {
    const auto dir = fs::temp_directory_path() / "photo_sidecar_restart";
    fs::remove_all(dir);
    fs::create_directories(dir);
    const auto db = (dir / "pablo.db").string();

    int64_t ida = 0;
    {
        Catalog cat(db);
        photo::catalog::AssetRecord a;
        a.path = "/lib/a.jpg"; a.folder = "/lib"; a.filename = "a.jpg";
        a.size = 1; a.mtime_ns = 1; a.format = "jpeg"; a.import_time = 1;
        ida = cat.upsert_asset(a);
        cat.upsert_embedding(done_rec(ida, {1.0f, 0.0f}));
    }

    const std::vector<float> q{1.0f, 0.0f};
    {
        auto eng = engine_at(dir);
        ASSERT_NE(eng, nullptr);
        ASSERT_EQ(eng->semantic_search(q, {}, 10).size(), 1u);
    }
    // The search materialized the on-disk index in the cache dir.
    const auto sidecar = dir / "cache" / "semantic_index.bin";
    ASSERT_TRUE(fs::exists(sidecar));

    // External catalog change while the engine is DOWN → the stamp no longer
    // matches, so the next engine must rebuild (not adopt) and see both rows.
    {
        Catalog cat(db);
        photo::catalog::AssetRecord b;
        b.path = "/lib/b.jpg"; b.folder = "/lib"; b.filename = "b.jpg";
        b.size = 1; b.mtime_ns = 1; b.format = "jpeg"; b.import_time = 1;
        cat.upsert_embedding(done_rec(cat.upsert_asset(b), {0.9f, 0.1f}));
    }
    {
        auto eng = engine_at(dir);
        auto hits = eng->semantic_search(q, {}, 10);
        ASSERT_EQ(hits.size(), 2u);
        EXPECT_EQ(hits[0].asset_id, ida);
    }
    // Unchanged catalog → the restart adopts the existing file and still
    // serves both rows.
    {
        auto eng = engine_at(dir);
        EXPECT_EQ(eng->semantic_search(q, {}, 10).size(), 2u);
    }
}

#endif  // PHOTO_HAVE_SQLITE
