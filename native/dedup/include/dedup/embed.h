// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 4: SSCD copy-detection embedding via ONNX Runtime.
//
// One Embedder owns one ORT session (thread-safe for concurrent Run calls, but
// we drive it with explicit batches off the decode pool). Output vectors are
// L2-normalized so cosine similarity == dot product downstream.
//
// Built without ONNX Runtime (DEDUP_HAVE_ORT undefined), construction throws a
// clear "rebuild with -DONNXRUNTIME_ROOT" error — there is no meaningful
// fallback for a learned embedding.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <opencv2/core.hpp>

#include "dedup/config.h"

namespace dedup {

class Embedder {
public:
    // Loads `cfg.model_path`, selects the execution provider (cpu/cuda), and
    // discovers the output embedding dimension from the model. Throws
    // std::runtime_error on a missing model / unavailable provider / no-ORT build.
    explicit Embedder(const Config& cfg);
    ~Embedder();

    Embedder(const Embedder&) = delete;
    Embedder& operator=(const Embedder&) = delete;

    // Embed a batch of preprocessed BGR images (from decode_for_embedding).
    // Returns one L2-normalized row of `dim()` floats per input, row-major:
    // result.size() == images.size() * dim(). ImageNet normalization and the
    // BGR->RGB swap happen here.
    std::vector<float> embed_batch(const std::vector<cv::Mat>& images);

    // Embedding dimensionality (e.g. 512 for SSCD ResNet-50).
    int dim() const;

    // True if compiled with ONNX Runtime support.
    static bool available();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace dedup
