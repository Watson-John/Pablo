// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "semantic/semantic_service.h"

#include <algorithm>
#include <utility>

#if defined(PHOTO_HAVE_FACES)
#include <opencv2/imgproc.hpp>
#include "codec/codec.h"  // photo::codec::decode_bgr (OpenCV/libvips)
#endif

namespace photo::semantic {

using catalog::Catalog;

namespace {

// Pack the mean colour of a downscaled RGBA buffer into 0xRRGGBB.
int32_t dominant_rgb(const std::vector<uint8_t>& rgba, int w, int h) {
    if (rgba.empty() || w <= 0 || h <= 0) return -1;
    const size_t px = static_cast<size_t>(w) * h;
    unsigned long long r = 0, g = 0, b = 0;
    for (size_t i = 0; i < px; ++i) {
        r += rgba[i * 4 + 0];
        g += rgba[i * 4 + 1];
        b += rgba[i * 4 + 2];
    }
    const int rr = static_cast<int>(r / px);
    const int gg = static_cast<int>(g / px);
    const int bb = static_cast<int>(b / px);
    return (rr << 16) | (gg << 8) | bb;
}

// Built-in decoder: routes through the face pipeline's codec (OpenCV + libvips)
// when compiled. On builds without it (lean tests, no-OpenCV plugins) returns
// false so the asset is Skipped rather than failing.
bool builtin_decode(const std::string& path, int target,
                    std::vector<uint8_t>& rgba, int& w, int& h) {
#if defined(PHOTO_HAVE_FACES)
    cv::Mat bgr = photo::codec::decode_bgr(path);
    if (bgr.empty()) return false;
    const int longest = std::max(bgr.cols, bgr.rows);
    if (longest > target) {
        const double s = static_cast<double>(target) / longest;
        cv::resize(bgr, bgr, cv::Size(), s, s, cv::INTER_AREA);
    }
    cv::Mat rgba_mat;
    cv::cvtColor(bgr, rgba_mat, cv::COLOR_BGR2RGBA);
    w = rgba_mat.cols;
    h = rgba_mat.rows;
    rgba.assign(rgba_mat.data,
                rgba_mat.data + static_cast<size_t>(w) * h * 4);
    return true;
#else
    (void)path; (void)target; (void)rgba; (void)w; (void)h;
    return false;
#endif
}

}  // namespace

SemanticService::SemanticService(std::unique_ptr<Embedder> embedder,
                                 DecodeFn decode)
    : embedder_(std::move(embedder)),
      // Members initialize in declaration order (decode_ before has_decoder_),
      // so `decode` must NOT be moved here — has_decoder_ still needs to read
      // it. Copy instead. (Moving emptied the std::function, which on a build
      // WITHOUT a built-in codec wrongly reported has_decoder_ == false and
      // Skipped assets that had a perfectly good injected decoder — a bug that
      // only showed on the no-OpenCV Linux CI, masked elsewhere by the codec.)
      decode_(decode ? decode : DecodeFn(&builtin_decode)),
      // A caller-injected decoder always counts; the built-in only when a codec
      // is compiled in. When neither, assets are Skipped (not Failed).
      has_decoder_(static_cast<bool>(decode) || has_builtin_decoder()) {}

bool SemanticService::has_builtin_decoder() {
#if defined(PHOTO_HAVE_FACES)
    return true;
#else
    return false;
#endif
}

Catalog::EmbeddingRecord SemanticService::embed_asset(
    int64_t asset_id, const std::string& path) const {
    Catalog::EmbeddingRecord rec;
    rec.asset_id = asset_id;
    rec.model_id = embedder_->model_id();
    rec.model_version = embedder_->model_version();
    rec.dim = embedder_->dim();

    if (!has_decoder_) {
        rec.status = Catalog::kEmbedSkipped;
        rec.error = "no decoder available in this build";
        return rec;
    }

    std::vector<uint8_t> rgba;
    int w = 0, h = 0;
    if (!decode_(path, /*target=*/256, rgba, w, h) || rgba.empty()) {
        rec.status = Catalog::kEmbedFailed;
        rec.error = "decode failed";
        return rec;
    }

    rec.dominant_rgb = dominant_rgb(rgba, w, h);

    PixelView view;
    view.pixels = rgba.data();
    view.width = w;
    view.height = h;
    view.channels = 4;
    rec.vec = embedder_->embed_image(view);
    if (rec.vec.empty()) {
        rec.status = Catalog::kEmbedFailed;
        rec.error = "embedding failed";
        return rec;
    }
    rec.dim = static_cast<int32_t>(rec.vec.size());
    rec.status = Catalog::kEmbedDone;
    return rec;
}

std::vector<float> SemanticService::embed_text(const std::string& query) const {
    return embedder_->embed_text(query);
}

}  // namespace photo::semantic
