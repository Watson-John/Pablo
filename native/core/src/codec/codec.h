// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// codec.h — full-resolution image decode for the face pipeline.
//
// The thumbnail path already decodes every format libvips supports
// (JPEG/PNG/WebP/GIF/TIFF/HEIC/AVIF/RAW/JXL). The face pipeline historically
// used cv::imread, which only handles a few formats; this routes it through the
// same libvips path so faces work on HEIC/RAW/JXL/TIFF too, with cv::imread as
// the fallback when libvips is unavailable.
//
// Decode is at SOURCE resolution (no shrink) so detected face boxes stay in
// source-image pixel coordinates, matching the catalog/asset dimensions the UI
// normalizes against.

#pragma once

#include <string>

#include <opencv2/core.hpp>

namespace photo::codec {

// Decode `path` to a full-resolution 8-bit BGR cv::Mat. Returns an empty Mat on
// failure (unsupported / unreadable). Uses libvips when built with it, else
// cv::imread.
cv::Mat decode_bgr(const std::string& path);

}  // namespace photo::codec
