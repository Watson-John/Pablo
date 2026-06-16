// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// detector.h — SCRFD-10G face detector (bbox + 5 landmarks).
//
// Model `scrfd_10g` (fal AuraFace re-release, Apache-2.0; see MANIFEST.md).
// Chosen by the eval bake-off: 97.7% recall on scanned photos vs YuNet 70.7%.
// Built only when FACES_HAVE_ORT (ONNX Runtime) is defined; otherwise the
// face pipeline reports unavailable, the same optional-dep discipline thumb_*
// uses for libvips.

#pragma once

#include <memory>
#include <string>
#include <vector>

#include <opencv2/core.hpp>

#include "faces/types.h"

namespace photo::faces {

class Detector {
public:
    // Loads the SCRFD ONNX model. Throws std::runtime_error on a missing model
    // or no-ORT build (callers gate on available()).
    explicit Detector(const std::string& model_path,
                      float score_threshold = 0.5f,
                      float nms_threshold = 0.45f);
    ~Detector();
    Detector(const Detector&) = delete;
    Detector& operator=(const Detector&) = delete;

    // Detect every face in a BGR image. Landmarks are returned in ArcFace
    // template order (eyes, nose, mouth corners) ready for align.h.
    std::vector<DetectedFace> detect(const cv::Mat& bgr);

    static bool available();  // true if compiled with ONNX Runtime

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace photo::faces
