// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// embed.h — face embedder (AuraFace 512-d, SFace 128-d fallback). Takes an
// aligned 112x112 BGR crop, runs the ONNX model, returns an L2-normalized
// vector. Built only when FACES_HAVE_ORT. Preprocessing (RGB, mean/scale) is
// per-model; see native/models/MANIFEST.md.

#pragma once

#include <memory>
#include <string>

#include <opencv2/core.hpp>

#include "faces/types.h"

namespace photo::faces {

class Embedder {
public:
    // Loads the embedder ONNX model. `mean`/`scale` set the per-model
    // preprocessing: pixel -> (pixel/255 - mean) ... but here we use the
    // ArcFace convention (px - mean)/scale with RGB channel order. AuraFace:
    // mean=127.5, scale=127.5. SFace: mean=127.5, scale=128.0.
    Embedder(const std::string& model_path, float mean = 127.5f, float scale = 127.5f);
    ~Embedder();
    Embedder(const Embedder&) = delete;
    Embedder& operator=(const Embedder&) = delete;

    // Embed one aligned 112x112 BGR crop. Returns an L2-normalized embedding.
    // `tta` averages the embedding with its horizontal flip (+~2 pts, the one
    // adaptation that held up on small data; see eval/).
    Embedding embed(const cv::Mat& aligned_112, bool tta = true);

    int dim() const;            // 512 (AuraFace) or 128 (SFace)
    static bool available();    // FACES_HAVE_ORT

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace photo::faces
