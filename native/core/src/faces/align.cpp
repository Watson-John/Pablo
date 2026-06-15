// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/align.h"

#include <opencv2/calib3d.hpp>   // estimateAffinePartial2D
#include <opencv2/imgproc.hpp>

namespace photo::faces {

// Canonical ArcFace 112x112 landmark template (InsightFace's arcface_src), the
// same five points eval/common.py:ARCFACE_5PT warps to. Order matches
// Landmarks5: left eye, right eye, nose, left mouth, right mouth.
const std::array<cv::Point2f, 5> kArcFaceTemplate112 = {{
    {38.2946f, 51.6963f},
    {73.5318f, 51.5014f},
    {56.0252f, 71.7366f},
    {41.5493f, 92.3655f},
    {70.7299f, 92.2041f},
}};

cv::Mat align_arcface(const cv::Mat& bgr, const Landmarks5& lm) {
    std::array<cv::Point2f, 5> src;
    for (int i = 0; i < 5; ++i) src[i] = {lm[i * 2], lm[i * 2 + 1]};

    // Similarity transform (rotation + uniform scale + translation) — the
    // ArcFace convention. LMEDS is robust to a single bad landmark.
    cv::Mat M = cv::estimateAffinePartial2D(src, kArcFaceTemplate112, cv::noArray(),
                                            cv::LMEDS);
    cv::Mat out;
    if (M.empty()) {
        // Degenerate landmarks: fall back to a plain resize of the box region's
        // caller-supplied crop is not available here, so warp identity-ish.
        cv::resize(bgr, out, cv::Size(112, 112));
        return out;
    }
    cv::warpAffine(bgr, out, M, cv::Size(112, 112), cv::INTER_LINEAR,
                   cv::BORDER_CONSTANT, cv::Scalar(0, 0, 0));
    return out;
}

float face_quality(const cv::Mat& aligned_112) {
    // Variance of the Laplacian = sharpness; the aligned crop is fixed-size so
    // size is already normalized. Picasa's facequality is a similar blur+size
    // product; here size is constant (112), so we report sharpness directly and
    // let the caller gate on the detector box pixel-size separately.
    cv::Mat gray, lap;
    cv::cvtColor(aligned_112, gray, cv::COLOR_BGR2GRAY);
    cv::Laplacian(gray, lap, CV_64F);
    cv::Scalar mean, stddev;
    cv::meanStdDev(lap, mean, stddev);
    return static_cast<float>(stddev[0] * stddev[0]);
}

}  // namespace photo::faces
