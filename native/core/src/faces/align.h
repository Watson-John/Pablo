// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// align.h — 5-point similarity warp to the 112x112 ArcFace template. Crops a
// detected face into the canonical pose the embedder expects. Header-light:
// implemented with cv::estimateAffinePartial2D + cv::warpAffine (no ORT).

#pragma once

#include <array>

#include <opencv2/core.hpp>

#include "faces/types.h"

namespace photo::faces {

// The canonical ArcFace 112x112 destination landmarks (left eye, right eye,
// nose, left mouth, right mouth), as used across InsightFace/ArcFace. Defined
// in align.cpp; declared here for embedders/tests that need the template.
extern const std::array<cv::Point2f, 5> kArcFaceTemplate112;

// Warp `bgr` so the face at `landmarks` lands on the 112x112 template.
// Returns a 112x112 BGR Mat ready for the embedder's preprocessing.
cv::Mat align_arcface(const cv::Mat& bgr, const Landmarks5& landmarks);

// Picasa-style face quality: sharpness (variance of Laplacian) gated by face
// size in pixels. Used to drop blurry/tiny faces before they poison clusters.
float face_quality(const cv::Mat& aligned_112);

}  // namespace photo::faces
