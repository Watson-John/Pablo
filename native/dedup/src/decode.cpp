// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/decode.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <unordered_set>

#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/img_hash.hpp>

#include "dedup/log.h"

#ifdef DEDUP_HAVE_LIBRAW
#include <libraw/libraw.h>
#endif

namespace dedup {
namespace {

const std::unordered_set<std::string>& raw_exts() {
    static const std::unordered_set<std::string> kRaw = {
        "cr2", "cr3", "nef", "arw", "dng", "raf", "rw2",
        "orf", "pef", "srw", "sr2", "raw", "3fr", "erf", "kdc", "mrw", "nrw",
    };
    return kRaw;
}

std::string ext_of(const std::string& path) {
    auto dot = path.find_last_of('.');
    if (dot == std::string::npos) return {};
    std::string e = path.substr(dot + 1);
    for (char& c : e) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return e;
}

// Normalize any decoded matrix to 8-bit 3-channel BGR.
cv::Mat to_bgr8(const cv::Mat& src) {
    if (src.empty()) return {};
    cv::Mat depth8;
    if (src.depth() == CV_16U) {
        src.convertTo(depth8, CV_8U, 1.0 / 257.0);   // 16-bit -> 8-bit
    } else if (src.depth() != CV_8U) {
        src.convertTo(depth8, CV_8U);
    } else {
        depth8 = src;
    }
    cv::Mat bgr;
    switch (depth8.channels()) {
        case 1: cv::cvtColor(depth8, bgr, cv::COLOR_GRAY2BGR); break;
        case 4: cv::cvtColor(depth8, bgr, cv::COLOR_BGRA2BGR); break;
        case 3: bgr = depth8; break;
        default: return {};
    }
    return bgr;
}

#ifdef DEDUP_HAVE_LIBRAW
// Pull the embedded JPEG/bitmap thumbnail from a RAW file — avoids the cost of
// full demosaicing, which we don't need for a copy-detection embedding.
cv::Mat read_raw_thumb(const std::string& path) {
    LibRaw rp;
    if (rp.open_file(path.c_str()) != LIBRAW_SUCCESS) return {};
    if (rp.unpack_thumb() != LIBRAW_SUCCESS) { rp.recycle(); return {}; }
    int err = 0;
    libraw_processed_image_t* th = rp.dcraw_make_mem_thumb(&err);
    cv::Mat out;
    if (th && err == LIBRAW_SUCCESS) {
        if (th->type == LIBRAW_IMAGE_JPEG) {
            cv::Mat enc(1, static_cast<int>(th->data_size), CV_8UC1, th->data);
            out = cv::imdecode(enc, cv::IMREAD_COLOR);     // owns its own buffer
        } else if (th->type == LIBRAW_IMAGE_BITMAP &&
                   th->colors == 3 && th->bits == 8) {
            cv::Mat rgb(th->height, th->width, CV_8UC3, th->data);
            cv::cvtColor(rgb, out, cv::COLOR_RGB2BGR);     // clones into out
        }
    }
    if (th) LibRaw::dcraw_clear_mem(th);
    rp.recycle();
    return out;
}
#endif

// Decode a file to BGR 8-bit at native resolution (any size). `reduced` asks
// OpenCV for a half-size decode where the codec supports it (pHash fast path).
cv::Mat load_bgr(const std::string& path, bool reduced) {
    const std::string ext = ext_of(path);
    const bool is_raw = raw_exts().count(ext) != 0;

    if (!is_raw) {
        int flags = reduced ? cv::IMREAD_REDUCED_COLOR_2 : cv::IMREAD_COLOR;
        cv::Mat img = cv::imread(path, flags);
        if (!img.empty()) return to_bgr8(img);
        // Some containers (.heic, odd .tif) may not decode at the reduced flag;
        // retry full-res before giving up.
        if (reduced) {
            img = cv::imread(path, cv::IMREAD_UNCHANGED);
            if (!img.empty()) return to_bgr8(img);
        }
    }
#ifdef DEDUP_HAVE_LIBRAW
    if (is_raw) {
        cv::Mat t = read_raw_thumb(path);
        if (!t.empty()) return to_bgr8(t);
    }
#endif
    return {};
}

}  // namespace

bool is_raw_format(const std::string& format) {
#ifdef DEDUP_HAVE_LIBRAW
    return raw_exts().count(format) != 0;
#else
    (void)format;
    return false;
#endif
}

std::optional<cv::Mat> decode_for_embedding(const ImageRecord& rec, const Config& cfg) {
    cv::Mat img = load_bgr(rec.path, /*reduced=*/false);
    if (img.empty()) {
        LOG_DEBUG("decode failed: " << rec.path);
        return std::nullopt;
    }
    const int S = std::max(1, cfg.input_size);
    const int w = img.cols, h = img.rows;
    const double scale = static_cast<double>(S) / std::min(w, h);
    const int nw = std::max(S, static_cast<int>(std::lround(w * scale)));
    const int nh = std::max(S, static_cast<int>(std::lround(h * scale)));

    cv::Mat resized;
    cv::resize(img, resized, cv::Size(nw, nh), 0, 0,
               scale < 1.0 ? cv::INTER_AREA : cv::INTER_LINEAR);

    // Center-crop to a fixed S×S square so a batch shares one tensor shape.
    const int x = (nw - S) / 2, y = (nh - S) / 2;
    return resized(cv::Rect(x, y, S, S)).clone();
}

std::optional<std::vector<uint8_t>> encode_preview_jpeg(const std::string& path,
                                                        int max_dim, int quality) {
    cv::Mat img = load_bgr(path, /*reduced=*/false);
    if (img.empty()) return std::nullopt;
    const int longest = std::max(img.cols, img.rows);
    if (max_dim > 0 && longest > max_dim) {
        const double scale = static_cast<double>(max_dim) / longest;
        cv::resize(img, img,
                   cv::Size(std::max(1, static_cast<int>(std::lround(img.cols * scale))),
                            std::max(1, static_cast<int>(std::lround(img.rows * scale)))),
                   0, 0, cv::INTER_AREA);
    }
    std::vector<uint8_t> out;
    std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, quality};
    if (!cv::imencode(".jpg", img, out, params)) return std::nullopt;
    return out;
}

std::optional<uint64_t> perceptual_hash(const std::string& path) {
    cv::Mat img = load_bgr(path, /*reduced=*/true);
    if (img.empty()) return std::nullopt;
    static thread_local cv::Ptr<cv::img_hash::PHash> hasher = cv::img_hash::PHash::create();
    cv::Mat hash;  // 1x8 CV_8U
    hasher->compute(img, hash);
    if (hash.total() < 8) return std::nullopt;
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i) {
        v |= static_cast<uint64_t>(hash.at<uchar>(0, i)) << (8 * i);
    }
    return v;
}

}  // namespace dedup
