// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// semantic_onnx_test.cpp — proves the REAL SigLIP2 embedder does true text→image
// retrieval in C++ (not the colour fallback). Gated on SEMANTIC_HAVE_ORT and on
// the exported model files being present; otherwise it skips.
//
// Fixtures (from eval/retrieval/make_fixtures.py) live in the dir named by
// $PABLO_SEMANTIC_MODELS (default ~/pablo-semantic-models):
//   semantic_{image,text}.onnx, semantic_tokenizer.model  (the model)
//   fixture_{tree,dog,car}.rgba  (real 224x224 RGBA images)
//   golden_{img_*,txt_*}.f32     (Python embeddings, for exact parity)

#include <gtest/gtest.h>

#ifdef SEMANTIC_HAVE_ORT

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "semantic/embedder.h"

using photo::semantic::Embedder;
using photo::semantic::make_onnx_embedder;
using photo::semantic::PixelView;

namespace {

std::string models_dir() {
    if (const char* e = std::getenv("PABLO_SEMANTIC_MODELS")) return e;
    if (const char* h = std::getenv("HOME"))
        return std::string(h) + "/pablo-semantic-models";
    return "";
}

std::vector<uint8_t> read_bytes(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

std::vector<float> read_floats(const std::string& path) {
    auto b = read_bytes(path);
    std::vector<float> v(b.size() / sizeof(float));
    std::memcpy(v.data(), b.data(), v.size() * sizeof(float));
    return v;
}

float dot(const std::vector<float>& a, const std::vector<float>& b) {
    double s = 0;
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) s += double(a[i]) * b[i];
    return float(s);  // both L2-normalized ⇒ cosine
}

std::vector<float> embed_rgba(const Embedder& e, const std::string& path) {
    auto bytes = read_bytes(path);
    PixelView v;
    v.pixels = bytes.data();
    v.width = 224;
    v.height = 224;
    v.channels = 4;
    return e.embed_image(v);
}

}  // namespace

class SemanticOnnx : public ::testing::Test {
protected:
    void SetUp() override {
        dir_ = models_dir();
        emb_ = make_onnx_embedder(dir_);
        if (!emb_)
            GTEST_SKIP() << "SigLIP2 models not found in " << dir_
                         << " (run eval/retrieval/export_siglip2.py) — skipping";
    }
    std::string dir_;
    std::unique_ptr<Embedder> emb_;
};

TEST_F(SemanticOnnx, DimIs768AndModelId) {
    EXPECT_EQ(emb_->dim(), 768);
    EXPECT_EQ(emb_->model_id(), "siglip2-base-patch16-224");
}

TEST_F(SemanticOnnx, MatchesPythonEmbeddingsExactly) {
    // IMAGE tower: strict. These vectors ARE the index — fp32 and fp16 must
    // match the Python reference near-exactly (measured drift 1.00000). A drop
    // below 0.999 means wrong preprocessing or a disqualified quantization
    // (int8-image drifts to ~0.81-0.85 and is not shipped).
    for (const char* lab : {"tree", "dog", "car"}) {
        auto cpp = embed_rgba(*emb_, dir_ + "/fixture_" + lab + ".rgba");
        auto py = read_floats(dir_ + "/golden_img_" + std::string(lab) + ".f32");
        ASSERT_EQ(cpp.size(), 768u);
        ASSERT_EQ(py.size(), 768u);
        EXPECT_GT(dot(cpp, py), 0.999f) << "image parity for " << lab;
    }
    // TEXT tower: tolerant to the SHIPPED int8 quantization (query drift vs
    // fp32 measured 0.965-0.991 with retrieval metrics identical on 3,000
    // images — mAP delta 0.000). 0.95 still catches tokenizer/preprocessing
    // bugs, which push cosine far below that; ranking correctness is gated by
    // TextRetrievesTheMatchingImage below.
    EXPECT_GT(dot(emb_->embed_text("tree"),
                  read_floats(dir_ + "/golden_txt_tree.f32")), 0.95f);
    EXPECT_GT(dot(emb_->embed_text("a dog"),
                  read_floats(dir_ + "/golden_txt_a_dog.f32")), 0.95f);
}

TEST_F(SemanticOnnx, TextRetrievesTheMatchingImage) {
    const auto tree = embed_rgba(*emb_, dir_ + "/fixture_tree.rgba");
    const auto dog = embed_rgba(*emb_, dir_ + "/fixture_dog.rgba");
    const auto car = embed_rgba(*emb_, dir_ + "/fixture_car.rgba");

    struct Q { const char* text; const std::vector<float>* want; };
    const std::vector<Q> qs = {
        {"tree", &tree}, {"a dog", &dog}, {"a car", &car},
    };
    for (const auto& q : qs) {
        const auto t = emb_->embed_text(q.text);
        const float s_tree = dot(t, tree), s_dog = dot(t, dog), s_car = dot(t, car);
        const float s_want = dot(t, *q.want);
        // The matching image must be the top hit among the three.
        EXPECT_GE(s_want, s_tree) << q.text;
        EXPECT_GE(s_want, s_dog) << q.text;
        EXPECT_GE(s_want, s_car) << q.text;
    }
}

#endif  // SEMANTIC_HAVE_ORT
