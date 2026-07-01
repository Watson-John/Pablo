// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// onnx_embedder.cpp — the REAL text↔image semantic embedder (SigLIP2).
//
// Runs google/siglip2-base-patch16-224 exported to two ONNX graphs (image +
// text encoders) via ONNX Runtime, with the Gemma SentencePiece tokenizer for
// the text side. Image and text embeddings share one 768-d space, L2-normalized,
// compared by cosine — so a text query ranks the library's images. This is what
// turns on true `tree→trees` / `wedding` retrieval.
//
// Compiled only with SEMANTIC_HAVE_ORT (needs ONNX Runtime + SentencePiece).
// make_onnx_embedder returns nullptr unless all three model files are present in
// the models dir, so the app falls back to the deterministic backend.
//
// Exact preprocessing is pinned to the HF processor (see the golden fixtures in
// eval/retrieval/export_siglip2.py):
//   image: RGB, resize 224² bilinear, (px/255 - 0.5)/0.5  == px/127.5 - 1
//   text : lowercase → SentencePiece → append EOS(1), no BOS, pad 0 to len 64

#include "semantic/embedder.h"

#ifdef SEMANTIC_HAVE_ORT

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <memory>
#include <mutex>

#include <onnxruntime_cxx_api.h>
#include <sentencepiece_processor.h>

#include "util/log.h"

namespace fs = std::filesystem;

namespace photo::semantic {
namespace {

constexpr int kSide = 224;
constexpr int kSeq = 64;
constexpr int64_t kEos = 1;
constexpr int64_t kPad = 0;

void l2(std::vector<float>& v) {
    double s = 0.0;
    for (float x : v) s += static_cast<double>(x) * x;
    if (s <= 1e-12) return;
    const float inv = static_cast<float>(1.0 / std::sqrt(s));
    for (float& x : v) x *= inv;
}

// Bilinear resize an RGB/RGBA PixelView to kSide², planar CHW, SigLIP-normalized
// (px/127.5 - 1). RGB order (channels 0,1,2).
std::vector<float> preprocess_image(const PixelView& px) {
    std::vector<float> out(static_cast<size_t>(3) * kSide * kSide);
    const int ch = px.channels >= 3 ? px.channels : 3;
    const int stride = px.stride > 0 ? px.stride : px.width * ch;
    for (int y = 0; y < kSide; ++y) {
        const float fy = (y + 0.5f) * px.height / kSide - 0.5f;
        int y0 = static_cast<int>(std::floor(fy));
        const float wy = fy - y0;
        const int y0c = std::max(0, std::min(px.height - 1, y0));
        const int y1c = std::max(0, std::min(px.height - 1, y0 + 1));
        for (int x = 0; x < kSide; ++x) {
            const float fx = (x + 0.5f) * px.width / kSide - 0.5f;
            int x0 = static_cast<int>(std::floor(fx));
            const float wx = fx - x0;
            const int x0c = std::max(0, std::min(px.width - 1, x0));
            const int x1c = std::max(0, std::min(px.width - 1, x0 + 1));
            for (int c = 0; c < 3; ++c) {
                auto at = [&](int yy, int xx) {
                    return static_cast<float>(
                        px.pixels[static_cast<size_t>(yy) * stride +
                                  static_cast<size_t>(xx) * ch + c]);
                };
                const float top = at(y0c, x0c) * (1 - wx) + at(y0c, x1c) * wx;
                const float bot = at(y1c, x0c) * (1 - wx) + at(y1c, x1c) * wx;
                const float v = top * (1 - wy) + bot * wy;  // 0..255
                out[(static_cast<size_t>(c) * kSide + y) * kSide + x] =
                    v / 127.5f - 1.0f;
            }
        }
    }
    return out;
}

class SiglipEmbedder final : public Embedder {
public:
    // Sessions are LAZY, per tower: browsing the gallery costs zero model RAM,
    // indexing loads only the image tower, and the text tower loads on the
    // first actual search (measured: the two eager fp32/fp16 towers held ~3 GB
    // resident from engine start). The trade: a corrupt ONNX file surfaces as
    // a logged empty-embedding at first use (Failed row / empty search) rather
    // than a constructor throw — the deterministic fallback still covers the
    // files-absent case via make_onnx_embedder's existence check. The 4 MB
    // SentencePiece tokenizer stays eager so a bad file is caught at startup.
    SiglipEmbedder(std::string img_model, std::string txt_model,
                   const std::string& sp_model)
        : img_path_(std::move(img_model)),
          txt_path_(std::move(txt_model)),
          model_id_("siglip2-base-patch16-224"),
          model_version_("1") {
        opts_.SetIntraOpNumThreads(1);
        opts_.SetInterOpNumThreads(1);
        opts_.SetExecutionMode(ORT_SEQUENTIAL);
        opts_.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        const auto st = sp_.Load(sp_model);
        if (!st.ok())
            throw std::runtime_error("sentencepiece load failed: " +
                                     st.ToString());
    }

    // SigLIP2-base is 768-d by construction; verified against the graph's
    // output shape on first image-tower load. Constant here so dim() doesn't
    // force a 372 MB session into RAM at engine start (it's logged there).
    int dim() const override { return dim_; }
    const std::string& model_id() const override { return model_id_; }
    const std::string& model_version() const override { return model_version_; }

    std::vector<float> embed_image(const PixelView& px) const override {
        if (!px.pixels || px.width <= 0 || px.height <= 0) return {};
        // Hold a shared reference for the whole Run: release_sessions may drop
        // the member pointer concurrently; our copy keeps the session alive.
        std::shared_ptr<Ort::Session> s = image_session();
        if (!s) return {};
        auto blob = preprocess_image(px);
        const int64_t shape[4] = {1, 3, kSide, kSide};
        Ort::Value in = Ort::Value::CreateTensor<float>(
            mem_, blob.data(), blob.size(), shape, 4);
        const char* ins[] = {img_in_.c_str()};
        const char* outs[] = {img_out_.c_str()};
        try {
            auto o = s->Run(Ort::RunOptions{nullptr}, ins, &in, 1, outs, 1);
            const float* p = o[0].GetTensorData<float>();
            std::vector<float> v(p, p + dim_);
            l2(v);
            return v;
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_ERROR, "semantic: image inference failed: %s",
                       e.what());
            return {};
        }
    }

    std::vector<float> embed_text(const std::string& query) const override {
        std::string low;
        low.reserve(query.size());
        for (unsigned char c : query)
            low.push_back(static_cast<char>(std::tolower(c)));
        const std::vector<int> ids = sp_.EncodeAsIds(low);
        std::vector<int64_t> input(kSeq, kPad);
        const size_t n = std::min(ids.size(), static_cast<size_t>(kSeq - 1));
        for (size_t i = 0; i < n; ++i) input[i] = ids[i];
        input[n] = kEos;  // SigLIP: append EOS, no BOS, pad with 0
        std::shared_ptr<Ort::Session> s = text_session();
        if (!s) return {};
        const int64_t shape[2] = {1, kSeq};
        Ort::Value in = Ort::Value::CreateTensor<int64_t>(
            mem_, input.data(), input.size(), shape, 2);
        const char* ins[] = {txt_in_.c_str()};
        const char* outs[] = {txt_out_.c_str()};
        try {
            auto o = s->Run(Ort::RunOptions{nullptr}, ins, &in, 1, outs, 1);
            const float* p = o[0].GetTensorData<float>();
            std::vector<float> v(p, p + dim_);
            l2(v);
            return v;
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_ERROR, "semantic: text inference failed: %s",
                       e.what());
            return {};
        }
    }

    // Reclaim tower RAM. In-flight embeds hold their own shared_ptr, so this
    // only drops the member reference — the session frees when the last Run
    // returns. The next embed lazily reloads from disk (~1 s).
    void release_sessions(uint32_t mask) override {
        if (mask & kReleaseImageTower) {
            std::lock_guard<std::mutex> lk(img_mu_);
            if (img_) {
                img_.reset();
                PHOTO_LOGF(PHOTO_LOG_INFO,
                           "semantic: image tower released (RAM reclaimed)");
            }
        }
        if (mask & kReleaseTextTower) {
            std::lock_guard<std::mutex> lk(txt_mu_);
            if (txt_) {
                txt_.reset();
                PHOTO_LOGF(PHOTO_LOG_INFO,
                           "semantic: text tower released (RAM reclaimed)");
            }
        }
    }

private:
    // Lazy per-tower session init. The tiny mutex guards only creation; embeds
    // copy the shared_ptr under the mutex and Run outside it (Ort::Session::Run
    // is safe for concurrent calls). A failed load is logged and retried on the
    // next call (cheap: fs + ORT error path).
    std::shared_ptr<Ort::Session> image_session() const {
        std::lock_guard<std::mutex> lk(img_mu_);
        if (!img_) {
            try {
                img_ = std::make_shared<Ort::Session>(env_, img_path_.c_str(),
                                                      opts_);
                img_in_ = img_->GetInputNameAllocated(0, alloc_).get();
                img_out_ = img_->GetOutputNameAllocated(0, alloc_).get();
                const auto shape = img_->GetOutputTypeInfo(0)
                                       .GetTensorTypeAndShapeInfo()
                                       .GetShape();
                const int d =
                    shape.empty() ? dim_ : static_cast<int>(shape.back());
                if (d != dim_)
                    PHOTO_LOGF(PHOTO_LOG_ERROR,
                               "semantic: image tower dim %d != expected %d", d,
                               dim_);
                PHOTO_LOGF(PHOTO_LOG_INFO,
                           "semantic: image tower loaded (lazy)");
            } catch (const std::exception& e) {
                PHOTO_LOGF(PHOTO_LOG_ERROR,
                           "semantic: image tower load failed: %s", e.what());
                img_.reset();
            }
        }
        return img_;
    }

    std::shared_ptr<Ort::Session> text_session() const {
        std::lock_guard<std::mutex> lk(txt_mu_);
        if (!txt_) {
            try {
                txt_ = std::make_shared<Ort::Session>(env_, txt_path_.c_str(),
                                                      opts_);
                txt_in_ = txt_->GetInputNameAllocated(0, alloc_).get();
                txt_out_ = txt_->GetOutputNameAllocated(0, alloc_).get();
                PHOTO_LOGF(PHOTO_LOG_INFO,
                           "semantic: text tower loaded (lazy)");
            } catch (const std::exception& e) {
                PHOTO_LOGF(PHOTO_LOG_ERROR,
                           "semantic: text tower load failed: %s", e.what());
                txt_.reset();
            }
        }
        return txt_;
    }

    Ort::Env env_{ORT_LOGGING_LEVEL_WARNING, "pablo-semantic"};
    Ort::SessionOptions opts_;
    std::string img_path_, txt_path_;
    mutable std::mutex img_mu_, txt_mu_;
    // shared_ptr so release_sessions can drop the member while an in-flight
    // embed keeps the session alive through its own reference.
    mutable std::shared_ptr<Ort::Session> img_;  // Run() is non-const
    mutable std::shared_ptr<Ort::Session> txt_;
    mutable Ort::AllocatorWithDefaultOptions alloc_;
    Ort::MemoryInfo mem_ =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    sentencepiece::SentencePieceProcessor sp_;
    mutable std::string img_in_, img_out_, txt_in_, txt_out_;
    int dim_ = 768;
    std::string model_id_;
    std::string model_version_;
};

}  // namespace

std::unique_ptr<Embedder> make_onnx_embedder(const std::string& models_dir) {
    try {
        const fs::path dir(models_dir);
        const fs::path img = dir / "semantic_image.onnx";
        const fs::path txt = dir / "semantic_text.onnx";
        const fs::path sp = dir / "semantic_tokenizer.model";
        if (!fs::exists(img) || !fs::exists(txt) || !fs::exists(sp)) {
            return nullptr;  // → deterministic fallback
        }
        auto e = std::make_unique<SiglipEmbedder>(img.string(), txt.string(),
                                                  sp.string());
        PHOTO_LOGF(PHOTO_LOG_INFO,
                   "semantic: SigLIP2 ONNX embedder ready (dim=%d; towers "
                   "load lazily on first index/search)", e->dim());
        return e;
    } catch (const std::exception& e) {
        PHOTO_LOGF(PHOTO_LOG_ERROR, "semantic: ONNX embedder load failed: %s",
                   e.what());
        return nullptr;
    }
}

}  // namespace photo::semantic

#endif  // SEMANTIC_HAVE_ORT
