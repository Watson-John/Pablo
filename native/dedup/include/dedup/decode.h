// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// Stage 3: decode + preprocess a single image into the form SSCD expects.
//
// RAW files (when built with LibRaw) yield their embedded JPEG thumbnail —
// full demosaicing is the pipeline's worst bottleneck and unnecessary for a
// copy-detection embedding. Everything else goes through OpenCV.
//
// Output is always 8-bit sRGB BGR (OpenCV's native order), resized so the short
// side is `cfg.input_size`. The embed stage handles channel-order swap +
// ImageNet normalization + NCHW packing — keeping decode free of model specifics.

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include <opencv2/core.hpp>

#include "dedup/config.h"
#include "dedup/types.h"

namespace dedup {

// Decode `rec` to a preprocessed BGR cv::Mat (8-bit, short side == input_size),
// ready for embedding. std::nullopt on any decode failure (unreadable, corrupt,
// unsupported). Thread-safe; safe to call from a decode worker pool.
std::optional<cv::Mat> decode_for_embedding(const ImageRecord& rec, const Config& cfg);

// Compute the 64-bit pHash of an already-decoded (or freshly decoded) image.
// Returns std::nullopt if the file can't be decoded. Uses OpenCV's img_hash.
std::optional<uint64_t> perceptual_hash(const std::string& path);

// Decode `path` (incl. RAW via embedded thumbnail) and re-encode as a JPEG that
// fits within `max_dim` on its long side, preserving aspect. Lets the review UI
// display any source format in the browser. std::nullopt on decode failure.
std::optional<std::vector<uint8_t>> encode_preview_jpeg(const std::string& path,
                                                        int max_dim,
                                                        int quality = 85);

// True if `format` is a RAW extension this build can pull a thumbnail from.
bool is_raw_format(const std::string& format);

}  // namespace dedup
