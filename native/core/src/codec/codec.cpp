// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "codec/codec.h"

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>

#ifdef PHOTO_HAVE_VIPS
#include <mutex>

#include <vips/vips.h>
#endif

namespace photo::codec {

#ifdef PHOTO_HAVE_VIPS
namespace {

bool ensure_vips() {
    static std::once_flag once;
    static bool ok = false;
    std::call_once(once, [] { ok = (VIPS_INIT("pablo") == 0); });
    return ok;
}

// Decode at source resolution -> 8-bit sRGB, 3 bands -> BGR cv::Mat.
cv::Mat decode_via_vips(const std::string& path) {
    if (!ensure_vips()) return {};

    VipsImage* in = vips_image_new_from_file(
        path.c_str(), "access", VIPS_ACCESS_SEQUENTIAL, nullptr);
    if (in == nullptr) {
        vips_error_clear();
        return {};
    }

    // Normalize to 8-bit sRGB (handles CMYK, 16-bit, grayscale, RAW, …).
    VipsImage* srgb = nullptr;
    if (vips_colourspace(in, &srgb, VIPS_INTERPRETATION_sRGB, nullptr) != 0) {
        g_object_unref(in);
        vips_error_clear();
        return {};
    }
    g_object_unref(in);

    // Drop alpha / keep exactly 3 bands.
    VipsImage* rgb = srgb;
    if (vips_image_get_bands(srgb) > 3) {
        VipsImage* ex = nullptr;
        if (vips_extract_band(srgb, &ex, 0, "n", 3, nullptr) != 0) {
            g_object_unref(srgb);
            vips_error_clear();
            return {};
        }
        g_object_unref(srgb);
        rgb = ex;
    }

    const int w = vips_image_get_width(rgb);
    const int h = vips_image_get_height(rgb);
    if (w <= 0 || h <= 0 || vips_image_get_bands(rgb) != 3) {
        g_object_unref(rgb);
        return {};
    }

    size_t n = 0;
    auto* mem = static_cast<unsigned char*>(vips_image_write_to_memory(rgb, &n));
    g_object_unref(rgb);
    if (mem == nullptr) return {};

    // mem is tightly-packed RGB; wrap (no copy) then convert to an owned BGR Mat.
    const cv::Mat rgb_view(h, w, CV_8UC3, mem);
    cv::Mat bgr;
    cv::cvtColor(rgb_view, bgr, cv::COLOR_RGB2BGR);
    g_free(mem);
    return bgr;
}

}  // namespace
#endif  // PHOTO_HAVE_VIPS

cv::Mat decode_bgr(const std::string& path) {
#ifdef PHOTO_HAVE_VIPS
    cv::Mat m = decode_via_vips(path);
    if (!m.empty()) return m;
    // fall through to cv::imread for anything libvips couldn't open
#endif
    return cv::imread(path, cv::IMREAD_COLOR);
}

}  // namespace photo::codec
