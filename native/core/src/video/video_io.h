// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// video_io.h — FFmpeg-backed video probe, poster-frame extraction, and
// (Stage V4) lossless trim remux. Everything decode-related is gated on
// PHOTO_HAVE_FFMPEG (set by the CMake libav* probe, mirroring PHOTO_HAVE_VIPS);
// without it, probe() returns {ok:false} and poster_frame() returns null, so
// the core still builds and links on ffmpeg-less targets. is_video_path() is a
// pure extension check and is always available.
//
// The module name deliberately avoids any platform framework name (cf. the
// metadata/ vs macOS Metadata.framework collision) — "video_io" collides with
// nothing.

#pragma once

#include <cstdint>
#include <string>

#include "thumb/slot.h"  // FrameBuffer, FramePtr

namespace photo::video {

// True when `path`'s extension is a supported video container. Pure; always
// available (no ffmpeg needed). Mirrors engine.cpp's video_exts().
bool is_video_path(const std::string& path);

struct ProbeResult {
    bool ok = false;
    int width = 0;
    int height = 0;
    int64_t duration_ms = 0;
    std::string codec;  // e.g. "h264", "hevc"
};

// Read container/stream metadata for `path` (dims, duration, video codec).
// ok=false without ffmpeg or on any open/decode error.
ProbeResult probe(const std::string& path);

// Decode a representative frame (seeks to ~10% in, falling back to the first
// decodable frame) and return it as a premultiplied-BGRA FrameBuffer bounded to
// `max_dim` on the long edge (downscale only). null without ffmpeg or on error.
FramePtr poster_frame(const std::string& path, int max_dim);

// Stage V4: stream-copy `[start_ms, end_ms)` of `src` into `dst` with no
// re-encode (start snaps to the nearest preceding keyframe). end_ms <= 0 means
// "to the end". false without ffmpeg or on error.
bool remux_trim(const std::string& src, const std::string& dst,
                int64_t start_ms, int64_t end_ms);

}  // namespace photo::video
