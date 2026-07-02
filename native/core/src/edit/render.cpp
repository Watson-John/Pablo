// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "edit/render.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <string>
#include <utility>
#include <vector>

#ifdef PHOTO_HAVE_VIPS
#include <vips/vips.h>
#endif

#include "edit/edit_spec.h"
#include "thumb/slot.h"  // FrameBuffer

namespace photo::edit {

namespace {

constexpr float kLR = 0.2126f, kLG = 0.7152f, kLB = 0.0722f;

// NaN-safe clamp to [0,1]: the (v > 0) test is false for NaN, so NaN maps to 0
// rather than propagating through the detail passes and smearing across the
// frame via the separable blur's running sum.
inline float clamp01(float v) { return v >= 1.f ? 1.f : (v > 0.f ? v : 0.f); }
inline float luma(float r, float g, float b) { return kLR * r + kLG * g + kLB * b; }

using Mat = std::array<float, 20>;  // Flutter ColorFilter.matrix layout (0..255)

// Port of filter_matrices.dart _saturate(s, c, b): a saturation/contrast/
// brightness matrix in 0..255 space.
Mat saturate_mat(float s, float c = 1.f, float b = 1.f) {
    const float r1 = (1 - s) * kLR + s, g1 = (1 - s) * kLG, b1 = (1 - s) * kLB;
    const float r2 = (1 - s) * kLR, g2 = (1 - s) * kLG + s, b2 = (1 - s) * kLB;
    const float r3 = (1 - s) * kLR, g3 = (1 - s) * kLG, b3 = (1 - s) * kLB + s;
    const float off = 128.f * (1 - c) * b;
    return Mat{
        r1 * c * b, g1 * c * b, b1 * c * b, 0, off,
        r2 * c * b, g2 * c * b, b2 * c * b, 0, off,
        r3 * c * b, g3 * c * b, b3 * c * b, 0, off,
        0, 0, 0, 1, 0};
}

// Port of filter_matrices.dart _hueShift(degrees, sat, bright).
Mat hue_shift_mat(float degrees, float sat, float bright) {
    const float s = sat;
    const float r1 = (1 - s) * kLR + s, g1 = (1 - s) * kLG, b1 = (1 - s) * kLB;
    const float r2 = (1 - s) * kLR, g2 = (1 - s) * kLG + s, b2 = (1 - s) * kLB;
    const float r3 = (1 - s) * kLR, g3 = (1 - s) * kLG, b3 = (1 - s) * kLB + s;
    const float warm = degrees > 0 ? degrees / 180.f : 0.f;
    const float cool = degrees < 0 ? -degrees / 180.f : 0.f;
    return Mat{
        r1 * bright + warm * 20.f, g1 * bright, b1 * bright, 0, 0,
        r2 * bright, g2 * bright, b2 * bright, 0, 0,
        r3 * bright, g3 * bright, b3 * bright + cool * 20.f, 0, 0,
        0, 0, 0, 1, 0};
}

constexpr Mat kBW = {
    0.2126f, 0.7152f, 0.0722f, 0, 0,
    0.2126f, 0.7152f, 0.0722f, 0, 0,
    0.2126f, 0.7152f, 0.0722f, 0, 0,
    0, 0, 0, 1, 0};

constexpr Mat kNoir = {
    0.2976f, 1.0013f, 0.1011f, 0, -32,
    0.2976f, 1.0013f, 0.1011f, 0, -32,
    0.2976f, 1.0013f, 0.1011f, 0, -32,
    0, 0, 0, 1, 0};

constexpr Mat kFilm = {
    0.39f, 0.769f, 0.189f, 0, -10,
    0.349f, 0.686f, 0.168f, 0, -10,
    0.272f, 0.534f, 0.131f, 0, -10,
    0, 0, 0, 1, 0};

constexpr Mat kGolden = {
    0.42f, 0.85f, 0.20f, 0, 10,
    0.38f, 0.77f, 0.18f, 0, 10,
    0.30f, 0.60f, 0.14f, 0, 5,
    0, 0, 0, 1, 0};

// Resolve a filter id to its matrix. Returns false for "none"/unknown.
bool filter_matrix(const std::string& id, Mat& out) {
    if (id == "vivid")    { out = saturate_mat(1.6f, 1.12f); return true; }
    if (id == "cool")     { out = hue_shift_mat(-25.f, 1.1f, 1.02f); return true; }
    if (id == "warm")     { out = hue_shift_mat(18.f, 1.2f, 1.04f); return true; }
    if (id == "bw")       { out = kBW; return true; }
    if (id == "fade")     { out = saturate_mat(0.7f, 0.82f, 1.1f); return true; }
    if (id == "dramatic") { out = saturate_mat(1.25f, 1.45f); return true; }
    if (id == "noir")     { out = kNoir; return true; }
    if (id == "matte")    { out = saturate_mat(0.6f, 0.88f, 1.06f); return true; }
    if (id == "film")     { out = kFilm; return true; }
    if (id == "golden")   { out = kGolden; return true; }
    if (id == "lush")     { out = saturate_mat(1.3f, 1.05f); return true; }
    return false;  // "none"/"original"/unknown
}

// Separable box blur of a single-channel float plane. radius >= 1.
void box_blur(const std::vector<float>& src, std::vector<float>& dst,
              int w, int h, int radius) {
    if (radius < 1) { dst = src; return; }
    std::vector<float> tmp(src.size());
    const float norm = 1.f / (2 * radius + 1);
    // Horizontal pass.
    for (int y = 0; y < h; ++y) {
        const float* sr = &src[static_cast<size_t>(y) * w];
        float* tr = &tmp[static_cast<size_t>(y) * w];
        float sum = 0.f;
        for (int x = -radius; x <= radius; ++x)
            sum += sr[std::clamp(x, 0, w - 1)];
        for (int x = 0; x < w; ++x) {
            tr[x] = sum * norm;
            const int add = std::clamp(x + radius + 1, 0, w - 1);
            const int sub = std::clamp(x - radius, 0, w - 1);
            sum += sr[add] - sr[sub];
        }
    }
    // Vertical pass.
    for (int x = 0; x < w; ++x) {
        float sum = 0.f;
        for (int y = -radius; y <= radius; ++y)
            sum += tmp[static_cast<size_t>(std::clamp(y, 0, h - 1)) * w + x];
        for (int y = 0; y < h; ++y) {
            dst[static_cast<size_t>(y) * w + x] = sum * norm;
            const int add = std::clamp(y + radius + 1, 0, h - 1);
            const int sub = std::clamp(y - radius, 0, h - 1);
            sum += tmp[static_cast<size_t>(add) * w + x] -
                   tmp[static_cast<size_t>(sub) * w + x];
        }
    }
}

// Per-channel auto-levels: the 0.5th / 99.5th percentile of each channel's
// straight values, normalized to [0,1] — the black/white points a contrast
// stretch maps to 0 and 1.
void compute_auto_levels(const FrameBuffer& fb, float lo[3], float hi[3]) {
    const int w = static_cast<int>(fb.width), h = static_cast<int>(fb.height);
    const int stride = static_cast<int>(fb.stride);
    const uint8_t* data = fb.bgra.data();
    uint32_t hist[3][256] = {{0}};
    size_t count = 0;
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = data + static_cast<size_t>(y) * stride;
        for (int x = 0; x < w; ++x) {
            const uint8_t* p = row + static_cast<size_t>(x) * 4;
            const uint8_t A = p[3];
            if (A == 0) continue;
            int R, G, B;
            if (A == 255) { B = p[0]; G = p[1]; R = p[2]; }
            else {
                B = std::min(255, p[0] * 255 / A);
                G = std::min(255, p[1] * 255 / A);
                R = std::min(255, p[2] * 255 / A);
            }
            ++hist[0][R]; ++hist[1][G]; ++hist[2][B];
            ++count;
        }
    }
    if (count == 0) { for (int c = 0; c < 3; ++c) { lo[c] = 0; hi[c] = 1; } return; }
    const size_t loCut = static_cast<size_t>(count * 0.005);
    const size_t hiCut = static_cast<size_t>(count * 0.995);
    for (int c = 0; c < 3; ++c) {
        size_t acc = 0; int loV = 0, hiV = 255;
        for (int i = 0; i < 256; ++i) { acc += hist[c][i]; if (acc >= loCut) { loV = i; break; } }
        acc = 0;
        for (int i = 0; i < 256; ++i) { acc += hist[c][i]; if (acc >= hiCut) { hiV = i; break; } }
        if (hiV <= loV) { loV = 0; hiV = 255; }
        lo[c] = loV / 255.f; hi[c] = hiV / 255.f;
    }
}

// Build a 256-entry tone LUT from sorted (x,y) control points (linear interp;
// endpoints extended to 0 and 1). Values normalized [0,1].
void build_curve_lut(const std::vector<std::pair<float, float>>& pts,
                     float lut[256]) {
    std::vector<std::pair<float, float>> p(pts.begin(), pts.end());
    std::sort(p.begin(), p.end(),
              [](const auto& a, const auto& b) { return a.first < b.first; });
    if (p.empty() || p.front().first > 0.f)
        p.insert(p.begin(), {0.f, p.empty() ? 0.f : p.front().second});
    if (p.back().first < 1.f) p.push_back({1.f, p.back().second});
    for (int i = 0; i < 256; ++i) {
        const float x = i / 255.f;
        float y = p.back().second;
        for (size_t k = 1; k < p.size(); ++k) {
            if (x <= p[k].first) {
                const float x0 = p[k - 1].first, y0 = p[k - 1].second;
                const float x1 = p[k].first, y1 = p[k].second;
                const float t = (x1 > x0) ? (x - x0) / (x1 - x0) : 0.f;
                y = y0 + (y1 - y0) * t;
                break;
            }
        }
        lut[i] = clamp01(y);
    }
}

}  // namespace

void apply_pixels(FrameBuffer& fb, const EditSpec& spec) {
    // Only the tone/colour/filter/detail domain runs here; red-eye, heal and
    // text have their own passes, so a retouch-only spec skips this entirely.
    if (!spec.has_tone_ops()) return;
    const int w = static_cast<int>(fb.width);
    const int h = static_cast<int>(fb.height);
    if (w <= 0 || h <= 0 || fb.bgra.empty()) return;
    const size_t px = static_cast<size_t>(w) * static_cast<size_t>(h);
    const int stride = static_cast<int>(fb.stride);
    uint8_t* data = fb.bgra.data();

    // ── Precompute scalar factors ───────────────────────────────────────────
    const float expo = std::pow(2.f, static_cast<float>(spec.exposure) / 100.f);
    const float contrastF = 1.f + static_cast<float>(spec.contrast) / 100.f;
    const float sh = static_cast<float>(spec.shadows) / 100.f;
    const float hl = static_cast<float>(spec.highlights) / 100.f;
    const float wh = static_cast<float>(spec.whites) / 100.f;
    const float bl = static_cast<float>(spec.blacks) / 100.f;
    const float dh = static_cast<float>(spec.dehaze) / 100.f;
    const float tempT = static_cast<float>(spec.temperature) / 100.f;
    const float tintT = static_cast<float>(spec.tint) / 100.f;
    const float satF = 1.f + static_cast<float>(spec.saturation) / 100.f;
    const float vibF = static_cast<float>(spec.vibrance) / 100.f;

    Mat fm{};
    const bool has_filter = filter_matrix(spec.filter, fm);

    // Auto-levels (one-click enhance) — computed once, applied first per pixel.
    float autoLo[3] = {0, 0, 0}, autoHi[3] = {1, 1, 1};
    const bool auto_fix = spec.autoFix;
    if (auto_fix) compute_auto_levels(fb, autoLo, autoHi);

    float curveLut[256];
    const bool has_curve = !spec.curve_is_identity();
    if (has_curve) build_curve_lut(spec.curve, curveLut);

    // ── Pass 1: un-premultiply → tone/colour/filter → straight float RGB ─────
    std::vector<float> work(px * 3);
    std::vector<uint8_t> alpha(px);
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = data + static_cast<size_t>(y) * stride;
        for (int x = 0; x < w; ++x) {
            const uint8_t* p = row + static_cast<size_t>(x) * 4;
            const uint8_t A = p[3];
            const size_t i = static_cast<size_t>(y) * w + x;
            alpha[i] = A;
            // Un-premultiply to straight [0,1].
            float r, g, b;
            if (A == 0) {
                r = g = b = 0.f;
            } else if (A == 255) {
                b = p[0] / 255.f; g = p[1] / 255.f; r = p[2] / 255.f;
            } else {
                const float inv = 255.f / A;
                b = std::min(1.f, p[0] * inv / 255.f);
                g = std::min(1.f, p[1] * inv / 255.f);
                r = std::min(1.f, p[2] * inv / 255.f);
            }

            // Auto-levels: stretch each channel between its black/white points.
            if (auto_fix) {
                r = clamp01((r - autoLo[0]) / std::max(1e-4f, autoHi[0] - autoLo[0]));
                g = clamp01((g - autoLo[1]) / std::max(1e-4f, autoHi[1] - autoLo[1]));
                b = clamp01((b - autoLo[2]) / std::max(1e-4f, autoHi[2] - autoLo[2]));
            }
            // Exposure.
            r *= expo; g *= expo; b *= expo;
            // Global contrast (pivot 0.5).
            r = (r - 0.5f) * contrastF + 0.5f;
            g = (g - 0.5f) * contrastF + 0.5f;
            b = (b - 0.5f) * contrastF + 0.5f;
            // Tone regions (per-channel, weighted by the channel value).
            auto tone = [&](float v) {
                const float wS = (1 - v) * (1 - v);            // shadows
                const float wH = v * v;                         // highlights
                const float wB = std::max(0.f, 1.f - 3.f * v);  // blacks (deep)
                const float wW = std::max(0.f, 3.f * v - 2.f);  // whites (bright)
                v += 0.5f * (sh * wS + hl * wH + bl * wB + wh * wW);
                return v;
            };
            r = tone(r); g = tone(g); b = tone(b);
            // Dehaze: extra mid contrast + black-point lift.
            if (dh != 0.f) {
                const float k = 1.f + 0.3f * dh;
                r = (r - 0.5f) * k + 0.5f;
                g = (g - 0.5f) * k + 0.5f;
                b = (b - 0.5f) * k + 0.5f;
                const float bp = 0.05f * dh;
                if (bp != 0.f) {
                    const float d = 1.f - bp;
                    r = (r - bp) / d; g = (g - bp) / d; b = (b - bp) / d;
                }
            }
            // White balance.
            if (tempT != 0.f) { r *= 1.f + 0.3f * tempT; b *= 1.f - 0.3f * tempT; }
            if (tintT != 0.f) { g *= 1.f - 0.2f * tintT; }

            r = clamp01(r); g = clamp01(g); b = clamp01(b);

            // Master tone curve (LUT).
            if (has_curve) {
                r = curveLut[std::clamp(static_cast<int>(std::lround(r * 255.f)), 0, 255)];
                g = curveLut[std::clamp(static_cast<int>(std::lround(g * 255.f)), 0, 255)];
                b = curveLut[std::clamp(static_cast<int>(std::lround(b * 255.f)), 0, 255)];
            }

            // Saturation + vibrance.
            if (satF != 1.f || vibF != 0.f) {
                const float L = luma(r, g, b);
                const float mx = std::max({r, g, b});
                const float mn = std::min({r, g, b});
                const float chroma = mx - mn;               // 0..1
                const float eff = satF + vibF * (1.f - chroma);
                r = L + (r - L) * eff;
                g = L + (g - L) * eff;
                b = L + (b - L) * eff;
                r = clamp01(r); g = clamp01(g); b = clamp01(b);
            }

            // Filter preset matrix (0..255 space; offsets scaled to [0,1]).
            if (has_filter) {
                const float nr = fm[0] * r + fm[1] * g + fm[2] * b + fm[4] / 255.f;
                const float ng = fm[5] * r + fm[6] * g + fm[7] * b + fm[9] / 255.f;
                const float nb = fm[10] * r + fm[11] * g + fm[12] * b + fm[14] / 255.f;
                r = clamp01(nr); g = clamp01(ng); b = clamp01(nb);
            }

            work[i * 3 + 0] = r;
            work[i * 3 + 1] = g;
            work[i * 3 + 2] = b;
        }
    }

    // ── Pass 2: detail (clarity / sharpness / noise) via blurred luma/RGB ────
    const float clarity = static_cast<float>(spec.clarity) / 100.f;
    const float sharp = static_cast<float>(spec.sharpness) / 100.f;
    const float nr = static_cast<float>(spec.noise) / 100.f;
    if (clarity != 0.f || sharp > 0.f) {
        std::vector<float> L(px);
        for (size_t i = 0; i < px; ++i)
            L[i] = luma(work[i * 3], work[i * 3 + 1], work[i * 3 + 2]);
        std::vector<float> blur(px);
        if (sharp > 0.f) {
            box_blur(L, blur, w, h, 1);
            const float amt = sharp * 1.5f;
            for (size_t i = 0; i < px; ++i) {
                const float d = amt * (L[i] - blur[i]);
                for (int c = 0; c < 3; ++c)
                    work[i * 3 + c] = clamp01(work[i * 3 + c] + d);
            }
        }
        if (clarity != 0.f) {
            const int radius = std::max(2, std::min(w, h) / 50);
            box_blur(L, blur, w, h, radius);
            const float amt = clarity * 0.6f;
            for (size_t i = 0; i < px; ++i) {
                const float mid = 1.f - std::fabs(2.f * L[i] - 1.f);  // midtone weight
                const float d = amt * mid * (L[i] - blur[i]);
                for (int c = 0; c < 3; ++c)
                    work[i * 3 + c] = clamp01(work[i * 3 + c] + d);
            }
        }
    }
    if (nr > 0.f) {
        const float mix = nr * 0.7f;
        std::vector<float> plane(px), blur(px);
        for (int c = 0; c < 3; ++c) {
            for (size_t i = 0; i < px; ++i) plane[i] = work[i * 3 + c];
            box_blur(plane, blur, w, h, 1);
            for (size_t i = 0; i < px; ++i)
                work[i * 3 + c] = plane[i] + (blur[i] - plane[i]) * mix;
        }
    }

    // ── Pass 3: vignette + re-premultiply → write back ──────────────────────
    const float vig = static_cast<float>(spec.vignette) / 100.f;
    const float cx = (w - 1) * 0.5f, cy = (h - 1) * 0.5f;
    const float maxd2 = cx * cx + cy * cy;
    for (int y = 0; y < h; ++y) {
        uint8_t* row = data + static_cast<size_t>(y) * stride;
        for (int x = 0; x < w; ++x) {
            const size_t i = static_cast<size_t>(y) * w + x;
            float r = work[i * 3 + 0], g = work[i * 3 + 1], b = work[i * 3 + 2];
            if (vig != 0.f && maxd2 > 0.f) {
                const float dx = x - cx, dy = y - cy;
                const float rr = (dx * dx + dy * dy) / maxd2;  // 0 center → 1 corner
                const float m = 1.f + vig * rr;                 // <1 at edge when vig<0
                r *= m; g *= m; b *= m;
            }
            r = clamp01(r); g = clamp01(g); b = clamp01(b);
            const uint8_t A = alpha[i];
            uint8_t* p = row + static_cast<size_t>(x) * 4;
            // Re-premultiply (identity when A==255).
            const float af = A / 255.f;
            p[0] = static_cast<uint8_t>(std::lround(b * 255.f * af));
            p[1] = static_cast<uint8_t>(std::lround(g * 255.f * af));
            p[2] = static_cast<uint8_t>(std::lround(r * 255.f * af));
            p[3] = A;
        }
    }
}

namespace {

// Read a pixel's STRAIGHT (un-premultiplied) 0..255 RGB from a BGRA row pointer.
inline void read_straight(const uint8_t* p, int& R, int& G, int& B) {
    const uint8_t A = p[3];
    if (A == 0 || A == 255) { B = p[0]; G = p[1]; R = p[2]; return; }
    B = std::min(255, p[0] * 255 / A);
    G = std::min(255, p[1] * 255 / A);
    R = std::min(255, p[2] * 255 / A);
}

// Write STRAIGHT 0..255 RGB back into a BGRA pixel, re-premultiplying by its
// existing alpha (identity when A==255).
inline void write_straight(uint8_t* p, float R, float G, float B) {
    const float af = p[3] / 255.f;
    p[0] = static_cast<uint8_t>(std::lround(clamp01(B / 255.f) * 255.f * af));
    p[1] = static_cast<uint8_t>(std::lround(clamp01(G / 255.f) * 255.f * af));
    p[2] = static_cast<uint8_t>(std::lround(clamp01(R / 255.f) * 255.f * af));
}

// Region centre + radius in pixels. Radius is a fraction of the SHORT edge
// (matches the Region doc + the Dart brush), clamped to at least 1px.
struct RegionPx { int cx, cy, r; };
RegionPx region_px(const Region& rg, int W, int H) {
    const int shortEdge = std::min(W, H);
    RegionPx o;
    o.cx = static_cast<int>(std::lround(rg.x * W));
    o.cy = static_cast<int>(std::lround(rg.y * H));
    o.r = std::max(1, static_cast<int>(std::lround(rg.r * shortEdge)));
    return o;
}

// Tone-invariant "redness" in rg-chromaticity (the HP / Gaubatz-Ulichney
// p-metric): normalize out luminance first, then project onto the red axis. Skin
// of EVERY tone pools tightly near ~0.07..0.21, a flash pupil sits near ~0.65 —
// so a single cutoff works where the old brightness-sensitive R/((G+B)/2) ratio
// put warm skin (~1.37) and dark skin (~1.82) on both sides of its 1.35 constant.
// Undefined at black; callers pair it with a luma floor.
inline float redness_p(int R, int G, int B) {
    const int s = R + G + B;
    if (s <= 0) return 0.f;
    const float r = static_cast<float>(R) / s;
    const float g = static_cast<float>(G) / s;
    const float p = (r - 1.f / 3.f) * 1.2f - (g - 1.f / 3.f) * 0.6f;
    return p < 0.f ? 0.f : (p > 1.f ? 1.f : p);
}

inline float luma8(int R, int G, int B) {
    return kLR * R + kLG * G + kLB * B;
}

// Correct one red-eye brush dab. Rather than thresholding every pixel in the disc
// (which greys warm/dark skin), it (1) measures redness with the tone-invariant
// p-metric, (2) derives an ADAPTIVE cutoff from the skin ring just outside the
// brush, (3) seeds at the reddest central pixel and (4) grows ONLY the connected
// red blob — so the skin background (large, low-redness, disconnected) is
// structurally excluded. The blob is shape-validated; on failure it falls back to
// a per-pixel adaptive-threshold pass (still skin-safe). Correction preserves
// luminance (recolor to 0.7·luma, keeping intra-pupil gradient), skips the bright
// specular catch-light, and feathers the edge. Pure C++/CPU; cost scales with the
// tiny brush, not the frame.
void redeye_region(uint8_t* data, int W, int H, int stride, const RegionPx& c) {
    const int r = c.r;
    const int ringw = std::max(2, static_cast<int>(std::lround(0.35 * r)));
    const int rr = r + ringw;
    const int x0 = std::max(0, c.cx - rr), x1 = std::min(W - 1, c.cx + rr);
    const int y0 = std::max(0, c.cy - rr), y1 = std::min(H - 1, c.cy + rr);
    const int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    if (bw <= 0 || bh <= 0) return;
    const size_t n = static_cast<size_t>(bw) * bh;
    const int r2 = r * r, rr2 = rr * rr;

    std::vector<float> pv(n, -1.f);   // redness inside the disc; -1 elsewhere
    std::vector<float> lum(n, 0.f);
    int hist[64] = {0};               // ring-redness histogram (skin calibration)
    int ringN = 0;

    for (int ly = 0; ly < bh; ++ly) {
        const int gy = y0 + ly, dy = gy - c.cy;
        const uint8_t* row = data + static_cast<size_t>(gy) * stride;
        for (int lx = 0; lx < bw; ++lx) {
            const int gx = x0 + lx, dx = gx - c.cx;
            const int d2 = dx * dx + dy * dy;
            if (d2 > rr2) continue;
            int R, G, B;
            read_straight(row + static_cast<size_t>(gx) * 4, R, G, B);
            const float pp = redness_p(R, G, B);
            const size_t i = static_cast<size_t>(ly) * bw + lx;
            if (d2 <= r2) {
                pv[i] = pp;
                lum[i] = luma8(R, G, B);
            } else if (R >= 30) {  // ring: skin stats (skip near-black lash/brow)
                int b = static_cast<int>(pp * 63.f);
                b = b < 0 ? 0 : (b > 63 ? 63 : b);
                ++hist[b];
                ++ringN;
            }
        }
    }

    // Adaptive cutoff = median + 3σ of the skin ring, clamped. The 0.30 floor is
    // the hard "must be clearly red" gate; 0.60 caps it so an all-pupil ring can't
    // raise the bar past the pupil itself.
    float thr = 0.30f;
    if (ringN > 0) {
        int acc = 0, medBin = 0;
        for (int b = 0; b < 64; ++b) { acc += hist[b]; if (acc >= ringN / 2) { medBin = b; break; } }
        const double median = (medBin + 0.5) / 64.0;
        double mean = 0;
        for (int b = 0; b < 64; ++b) mean += hist[b] * ((b + 0.5) / 64.0);
        mean /= ringN;
        double var = 0;
        for (int b = 0; b < 64; ++b) { const double d = (b + 0.5) / 64.0 - mean; var += hist[b] * d * d; }
        var /= ringN;
        thr = static_cast<float>(median + 3.0 * std::sqrt(var));
        thr = std::clamp(thr, 0.30f, 0.60f);
    }

    // Seed: reddest pixel in the central 35% of the brush. If nothing there clears
    // the cutoff, the brush missed the pupil (or there's no red) → no-op.
    const int seedR2 = static_cast<int>(std::lround(0.35 * r * 0.35 * r));
    float best = -1.f; int bestIdx = -1;
    for (int ly = 0; ly < bh; ++ly) {
        const int dy = (y0 + ly) - c.cy;
        for (int lx = 0; lx < bw; ++lx) {
            const int dx = (x0 + lx) - c.cx;
            if (dx * dx + dy * dy > seedR2) continue;
            const size_t i = static_cast<size_t>(ly) * bw + lx;
            if (pv[i] > best) { best = pv[i]; bestIdx = static_cast<int>(i); }
        }
    }
    if (bestIdx < 0 || best <= thr) return;

    // Grow the single 8-connected red component from the seed.
    std::vector<uint8_t> mask(n, 0);
    std::vector<int> st;
    st.push_back(bestIdx);
    mask[bestIdx] = 1;
    while (!st.empty()) {
        const int i = st.back(); st.pop_back();
        const int ly = i / bw, lx = i % bw;
        for (int oy = -1; oy <= 1; ++oy)
            for (int ox = -1; ox <= 1; ++ox) {
                if (!ox && !oy) continue;
                const int nx = lx + ox, ny = ly + oy;
                if (nx < 0 || nx >= bw || ny < 0 || ny >= bh) continue;
                const size_t ni = static_cast<size_t>(ny) * bw + nx;
                if (mask[ni] || pv[ni] <= thr) continue;
                mask[ni] = 1;
                st.push_back(static_cast<int>(ni));
            }
    }

    // Morphological OPEN (erode → dilate, 3×3) to shave thin lash/hair bridges
    // without filling the catch-light hole (which a close would).
    auto morph = [&](bool dilate) {
        std::vector<uint8_t> out(n, 0);
        for (int ly = 0; ly < bh; ++ly)
            for (int lx = 0; lx < bw; ++lx) {
                bool v = dilate ? false : true;
                for (int oy = -1; oy <= 1; ++oy)
                    for (int ox = -1; ox <= 1; ++ox) {
                        const int nx = std::clamp(lx + ox, 0, bw - 1);
                        const int ny = std::clamp(ly + oy, 0, bh - 1);
                        const bool m = mask[static_cast<size_t>(ny) * bw + nx] != 0;
                        if (dilate) v = v || m; else v = v && m;
                    }
                out[static_cast<size_t>(ly) * bw + lx] = v ? 1 : 0;
            }
        mask.swap(out);
    };
    morph(false);
    morph(true);

    // Validate the blob shape; fall back to a per-pixel adaptive pass if it looks
    // nothing like a pupil (leak into skin, stray speckle, …). The fallback is
    // still skin-safe because `thr` is calibrated above the skin ring.
    int area = 0, minx = bw, maxx = -1, miny = bh, maxy = -1, perim = 0;
    double sx = 0, sy = 0;
    for (int ly = 0; ly < bh; ++ly)
        for (int lx = 0; lx < bw; ++lx) {
            if (!mask[static_cast<size_t>(ly) * bw + lx]) continue;
            ++area; sx += lx; sy += ly;
            minx = std::min(minx, lx); maxx = std::max(maxx, lx);
            miny = std::min(miny, ly); maxy = std::max(maxy, ly);
            const bool edge =
                (lx == 0 || !mask[static_cast<size_t>(ly) * bw + lx - 1]) ||
                (lx == bw - 1 || !mask[static_cast<size_t>(ly) * bw + lx + 1]) ||
                (ly == 0 || !mask[static_cast<size_t>(ly - 1) * bw + lx]) ||
                (ly == bh - 1 || !mask[static_cast<size_t>(ly + 1) * bw + lx]);
            if (edge) ++perim;
        }
    const double discArea = 3.14159265358979 * r2;
    bool ok = area > 0;
    if (ok) {
        const int bbw = maxx - minx + 1, bbh = maxy - miny + 1;
        const double fill = static_cast<double>(area) / (bbw * bbh);
        const double circ = perim > 0 ? 4.0 * 3.14159265 * area / (static_cast<double>(perim) * perim) : 0;
        const double cxL = sx / area, cyL = sy / area;
        const double cdx = cxL - (c.cx - x0), cdy = cyL - (c.cy - y0);
        ok = area >= 0.01 * discArea && area <= 0.60 * discArea && fill > 0.55 &&
             (area <= 15 || circ > 0.40) &&
             (cdx * cdx + cdy * cdy) < 0.36 * r2;
    }
    if (!ok) {
        std::fill(mask.begin(), mask.end(), 0);
        area = 0; sx = sy = 0;
        for (size_t i = 0; i < n; ++i)
            if (pv[i] > thr) {
                mask[i] = 1; ++area;
                sx += static_cast<int>(i) % bw; sy += static_cast<int>(i) / bw;
            }
        if (area == 0) return;
    }

    // Recolor: luminance-preserving desaturation, skipping the bright specular
    // catch-light, feathered from the blob centroid so there's no hard ring.
    float maxL = 0;
    for (size_t i = 0; i < n; ++i) if (mask[i]) maxL = std::max(maxL, lum[i]);
    const float bcx = static_cast<float>(sx / area), bcy = static_cast<float>(sy / area);
    const float brad = std::sqrt(area / 3.14159265f);
    const float feather = std::max(1.f, 0.2f * brad);
    const float glintL = std::max(180.f, 0.92f * maxL);

    for (int ly = 0; ly < bh; ++ly) {
        const int gy = y0 + ly;
        uint8_t* row = data + static_cast<size_t>(gy) * stride;
        for (int lx = 0; lx < bw; ++lx) {
            const size_t i = static_cast<size_t>(ly) * bw + lx;
            if (!mask[i]) continue;
            uint8_t* p = row + static_cast<size_t>(x0 + lx) * 4;
            int R, G, B; read_straight(p, R, G, B);
            const float L = luma8(R, G, B);
            if (L >= glintL && redness_p(R, G, B) < 0.30f) continue;  // keep glint
            const float mono = 0.7f * L;
            const float ddx = lx - bcx, ddy = ly - bcy;
            const float dist = std::sqrt(ddx * ddx + ddy * ddy);
            float w = 1.f;
            if (dist > brad - feather) {
                float t = std::clamp((brad - dist) / feather, 0.f, 1.f);
                w = t * t * (3.f - 2.f * t);
            }
            write_straight(p, R + (mono - R) * w, G + (mono - G) * w,
                           B + (mono - B) * w);
        }
    }
}

}  // namespace

void apply_redeye(FrameBuffer& fb, const EditSpec& spec) {
    if (spec.redeye.empty()) return;
    const int W = static_cast<int>(fb.width), H = static_cast<int>(fb.height);
    const int stride = static_cast<int>(fb.stride);
    if (W <= 0 || H <= 0 || fb.bgra.empty()) return;
    for (const Region& rg : spec.redeye)
        redeye_region(fb.bgra.data(), W, H, stride, region_px(rg, W, H));
}

std::vector<Region> auto_redeye_regions(
    const uint8_t* bgr, int W, int H, int stride,
    const std::vector<std::array<float, 4>>& eyes) {
    std::vector<Region> out;
    if (bgr == nullptr || W <= 0 || H <= 0) return out;
    const int shortEdge = std::min(W, H);
    for (const auto& e : eyes) {
        const float lx = e[0], ly = e[1], rx = e[2], ry = e[3];
        const float iod = std::sqrt((rx - lx) * (rx - lx) + (ry - ly) * (ry - ly));
        if (iod < 4.f) continue;  // faces too small to place a pupil brush
        const int win = std::max(3, static_cast<int>(std::lround(0.16f * iod)));
        for (int side = 0; side < 2; ++side) {
            const int ex = static_cast<int>(std::lround(side ? rx : lx));
            const int ey = static_cast<int>(std::lround(side ? ry : ly));
            // Scan a window around the eye landmark: record the peak redness (does
            // this eye have a red pupil at all?) and the CENTROID of the red pixels
            // (where to centre the brush — robust vs. an argmax on a flat pupil).
            float best = -1.f; double sx = 0, sy = 0; int rc = 0;
            for (int yy = std::max(0, ey - win); yy <= std::min(H - 1, ey + win); ++yy) {
                const uint8_t* row = bgr + static_cast<size_t>(yy) * stride;
                for (int xx = std::max(0, ex - win); xx <= std::min(W - 1, ex + win); ++xx) {
                    const uint8_t* p = row + static_cast<size_t>(xx) * 3;
                    const int B = p[0], G = p[1], R = p[2];
                    if (R < 55) continue;               // dark → skip (lash/pupil rim)
                    const float pp = redness_p(R, G, B);
                    if (pp > best) best = pp;
                    if (pp > 0.35f) { sx += xx; sy += yy; ++rc; }
                }
            }
            if (best <= 0.35f || rc == 0) continue;  // no red pupil → leave it alone
            Region rg;
            rg.x = static_cast<float>((sx / rc + 0.5) / W);
            rg.y = static_cast<float>((sy / rc + 0.5) / H);
            // Brush a bit larger than the pupil (~0.12·IOD); apply_redeye then
            // segments the actual blob inside it.
            rg.r = std::clamp(0.14f * iod / shortEdge, 0.02f, 0.20f);
            out.push_back(rg);
        }
    }
    return out;
}

// ─── Heal ────────────────────────────────────────────────────────────────────
// Classical spot-heal: clone a donor patch offset from the blemish, correct its
// mean colour to the target boundary (a cheap seamless-clone approximation), and
// feather it in. The MI-GAN ONNX hook below is the drop-in replacement point for
// content-aware inpainting where onnxruntime is linked; until then every target
// uses this dependency-free fallback.
namespace {

// Mean straight RGB of the ring at radius [r0, r1) around (cx,cy), clipped to the
// frame. Returns false if the ring is empty (fully off-frame).
bool ring_mean(const uint8_t* data, int W, int H, int stride,
               int cx, int cy, int r0, int r1, float& mR, float& mG, float& mB) {
    long sR = 0, sG = 0, sB = 0, n = 0;
    const int rr0 = r0 * r0, rr1 = r1 * r1;
    for (int y = std::max(0, cy - r1); y <= std::min(H - 1, cy + r1); ++y) {
        const int dy = y - cy;
        const uint8_t* row = data + static_cast<size_t>(y) * stride;
        for (int x = std::max(0, cx - r1); x <= std::min(W - 1, cx + r1); ++x) {
            const int dx = x - cx, d2 = dx * dx + dy * dy;
            if (d2 < rr0 || d2 >= rr1) continue;
            const uint8_t* p = row + static_cast<size_t>(x) * 4;
            int R, G, B; read_straight(p, R, G, B);
            sR += R; sG += G; sB += B; ++n;
        }
    }
    if (n == 0) return false;
    mR = static_cast<float>(sR) / n;
    mG = static_cast<float>(sG) / n;
    mB = static_cast<float>(sB) / n;
    return true;
}

// The classical per-region heal (see file-level note). `scratch` is a snapshot of
// the pre-heal pixels so overlapping regions don't clone already-healed output.
void heal_region_classical(uint8_t* data, const std::vector<uint8_t>& scratch,
                           int W, int H, int stride, const RegionPx& c) {
    const int r = c.r;
    // Donor centre: try the four axis offsets at ~2.4r, keep the first whose
    // patch + boundary ring fits inside the frame; fall back to the closest.
    const int off = static_cast<int>(std::lround(r * 2.4)) + 2;
    const int ring1 = static_cast<int>(std::lround(r * 1.35)) + 2;
    // Frame smaller than a donor patch on either axis: nothing clean to clone.
    if (W - 1 - ring1 < ring1 || H - 1 - ring1 < ring1) return;
    const struct { int dx, dy; } cand[4] = {{off, 0}, {-off, 0}, {0, off}, {0, -off}};
    int dcx = c.cx + off, dcy = c.cy;  // default: right
    bool found = false;
    for (const auto& k : cand) {
        const int nx = c.cx + k.dx, ny = c.cy + k.dy;
        if (nx - ring1 >= 0 && nx + ring1 < W && ny - ring1 >= 0 && ny + ring1 < H) {
            dcx = nx; dcy = ny; found = true; break;
        }
    }
    if (!found) {  // clamp the default donor centre into the valid range
        dcx = std::clamp(dcx, ring1, W - 1 - ring1);
        dcy = std::clamp(dcy, ring1, H - 1 - ring1);
    }

    // Seam correction: shift the donor patch so its boundary ring matches the
    // target's — approximates seamless cloning without solving Poisson.
    float tR, tG, tB, sR, sG, sB;
    const bool haveT = ring_mean(data, W, H, stride, c.cx, c.cy, r, ring1, tR, tG, tB);
    const bool haveS = ring_mean(scratch.data(), W, H, stride, dcx, dcy, r, ring1, sR, sG, sB);
    float corrR = 0, corrG = 0, corrB = 0;
    if (haveT && haveS) { corrR = tR - sR; corrG = tG - sG; corrB = tB - sB; }

    const int r2 = r * r;
    const float rf = static_cast<float>(r);
    for (int y = std::max(0, c.cy - r); y <= std::min(H - 1, c.cy + r); ++y) {
        const int dy = y - c.cy;
        uint8_t* row = data + static_cast<size_t>(y) * stride;
        for (int x = std::max(0, c.cx - r); x <= std::min(W - 1, c.cx + r); ++x) {
            const int dx = x - c.cx, d2 = dx * dx + dy * dy;
            if (d2 > r2) continue;
            const int sx = dcx + dx, sy = dcy + dy;
            if (sx < 0 || sx >= W || sy < 0 || sy >= H) continue;
            const uint8_t* dp =
                scratch.data() + static_cast<size_t>(sy) * stride + static_cast<size_t>(sx) * 4;
            int R, G, B; read_straight(dp, R, G, B);
            const float donR = R + corrR, donG = G + corrG, donB = B + corrB;
            // Feather: full donor at centre → 0 at the circle edge (smoothstep).
            const float dist = std::sqrt(static_cast<float>(d2)) / rf;  // 0..1
            const float e = 1.f - std::clamp(dist, 0.f, 1.f);
            const float a = e * e * (3.f - 2.f * e);  // smoothstep
            uint8_t* p = row + static_cast<size_t>(x) * 4;
            int oR, oG, oB; read_straight(p, oR, oG, oB);
            write_straight(p, donR * a + oR * (1 - a),
                              donG * a + oG * (1 - a),
                              donB * a + oB * (1 - a));
        }
    }
}

}  // namespace

void apply_heal(FrameBuffer& fb, const EditSpec& spec) {
    if (spec.heal.empty()) return;
    const int W = static_cast<int>(fb.width), H = static_cast<int>(fb.height);
    const int stride = static_cast<int>(fb.stride);
    if (W <= 0 || H <= 0 || fb.bgra.empty()) return;
    // Snapshot so overlapping strokes clone from the original, not partial output.
    const std::vector<uint8_t> scratch = fb.bgra;
    for (const Region& rg : spec.heal) {
        const RegionPx c = region_px(rg, W, H);
        heal_region_classical(fb.bgra.data(), scratch, W, H, stride, c);
    }
}

#ifdef PHOTO_HAVE_VIPS
namespace {

// Rasterize `text` with Pango at `fontpx` and alpha-blend it (colour `rgb`
// 0xRRGGBB, extra opacity `alpha` 0..1) over the frame. `place(tw, th, &x0,
// &y0)` maps the rasterized mask size to the box's top-left, so callers can
// centre (apply_text) or corner-anchor (draw_watermark); off-frame pixels are
// clipped per row/column. Shared by apply_text and draw_watermark.
template <typename PlaceFn>
void blend_text_mask(FrameBuffer& fb, const std::string& text, int fontpx,
                     uint32_t rgb, float alpha, PlaceFn place) {
    const int W = static_cast<int>(fb.width), H = static_cast<int>(fb.height);
    const int stride = static_cast<int>(fb.stride);
    if (W <= 0 || H <= 0 || text.empty() || alpha <= 0.f) return;
    const std::string font = "sans " + std::to_string(std::max(6, fontpx));
    VipsImage* mask = nullptr;
    if (vips_text(&mask, text.c_str(), "font", font.c_str(), "dpi", 72,
                  nullptr) != 0) {
        vips_error_clear();
        return;
    }
    const int tw = vips_image_get_width(mask);
    const int th = vips_image_get_height(mask);
    size_t n = 0;
    auto* mem = static_cast<uint8_t*>(vips_image_write_to_memory(mask, &n));
    g_object_unref(mask);
    if (mem == nullptr || tw <= 0 || th <= 0) { if (mem) g_free(mem); return; }
    const int bands = static_cast<int>(n / (static_cast<size_t>(tw) * th));
    int x0 = 0, y0 = 0;
    place(tw, th, &x0, &y0);
    const uint8_t cr = (rgb >> 16) & 0xFF;
    const uint8_t cg = (rgb >> 8) & 0xFF;
    const uint8_t cb = rgb & 0xFF;
    for (int yy = 0; yy < th; ++yy) {
        const int dy = y0 + yy;
        if (dy < 0 || dy >= H) continue;
        for (int xx = 0; xx < tw; ++xx) {
            const int dx = x0 + xx;
            if (dx < 0 || dx >= W) continue;
            const uint8_t a =
                mem[(static_cast<size_t>(yy) * tw + xx) * bands];  // coverage
            if (a == 0) continue;
            const float af = (a / 255.f) * alpha;
            uint8_t* p = fb.bgra.data() + static_cast<size_t>(dy) * stride +
                         static_cast<size_t>(dx) * 4;
            // Opaque frame (A=255) → premultiplied == straight; blend over.
            p[0] = static_cast<uint8_t>(std::lround(cb * af + p[0] * (1 - af)));
            p[1] = static_cast<uint8_t>(std::lround(cg * af + p[1] * (1 - af)));
            p[2] = static_cast<uint8_t>(std::lround(cr * af + p[2] * (1 - af)));
        }
    }
    g_free(mem);
}

}  // namespace

void apply_text(FrameBuffer& fb, const EditSpec& spec) {
    if (spec.texts.empty()) return;
    const int W = static_cast<int>(fb.width), H = static_cast<int>(fb.height);
    if (W <= 0 || H <= 0) return;
    for (const TextItem& t : spec.texts) {
        const int fontpx = std::max(6, static_cast<int>(std::lround(t.size * H)));
        blend_text_mask(fb, t.text, fontpx, t.color, 1.f,
                        [&](int tw, int th, int* x0, int* y0) {
                            // (x,y) is the CENTRE of the text box.
                            *x0 = static_cast<int>(std::lround(t.x * W)) - tw / 2;
                            *y0 = static_cast<int>(std::lround(t.y * H)) - th / 2;
                        });
    }
}

void draw_watermark(FrameBuffer& fb, const Watermark& wm) {
    const int W = static_cast<int>(fb.width), H = static_cast<int>(fb.height);
    if (W <= 0 || H <= 0 || wm.text.empty()) return;
    const float alpha = ((wm.argb >> 24) & 0xFF) / 255.f;
    if (alpha <= 0.f) return;
    const int short_edge = std::min(W, H);
    const float size = wm.size > 0.f ? wm.size : 0.04f;
    const float margin_f = wm.margin >= 0.f ? wm.margin : 0.02f;
    const int fontpx =
        std::max(6, static_cast<int>(std::lround(size * short_edge)));
    const int margin =
        std::max(0, static_cast<int>(std::lround(margin_f * short_edge)));
    blend_text_mask(fb, wm.text, fontpx, wm.argb & 0xFFFFFFu, alpha,
                    [&](int tw, int th, int* x0, int* y0) {
                        switch (wm.anchor) {
                            case 1:  // bottom-left
                                *x0 = margin; *y0 = H - margin - th; break;
                            case 2:  // top-right
                                *x0 = W - margin - tw; *y0 = margin; break;
                            case 3:  // top-left
                                *x0 = margin; *y0 = margin; break;
                            case 4:  // centre
                                *x0 = (W - tw) / 2; *y0 = (H - th) / 2; break;
                            default:  // bottom-right
                                *x0 = W - margin - tw; *y0 = H - margin - th;
                        }
                    });
}
#else
void apply_text(FrameBuffer&, const EditSpec&) {}
void draw_watermark(FrameBuffer&, const Watermark&) {}
#endif

namespace {

// Dimensions (w,h) of the largest axis-aligned rectangle that fits entirely
// inside a `w0 x h0` rectangle rotated by `angle` radians — the classic
// "rotatedRectWithMaxArea". Used to auto-crop the straighten border.
void inscribed_rect(double w0, double h0, double angle, double& wr, double& hr) {
    if (w0 <= 0 || h0 <= 0) { wr = w0; hr = h0; return; }
    const bool w_longer = w0 >= h0;
    const double sl = w_longer ? w0 : h0;  // long side
    const double ss = w_longer ? h0 : w0;  // short side
    const double sin_a = std::fabs(std::sin(angle));
    const double cos_a = std::fabs(std::cos(angle));
    if (ss <= 2.0 * sin_a * cos_a * sl || std::fabs(sin_a - cos_a) < 1e-10) {
        const double x = 0.5 * ss;
        if (w_longer) { wr = x / std::max(sin_a, 1e-9); hr = x / std::max(cos_a, 1e-9); }
        else          { wr = x / std::max(cos_a, 1e-9); hr = x / std::max(sin_a, 1e-9); }
    } else {
        const double cos2a = cos_a * cos_a - sin_a * sin_a;
        wr = (w0 * cos_a - h0 * sin_a) / cos2a;
        hr = (h0 * cos_a - w0 * sin_a) / cos2a;
    }
    wr = std::max(1.0, std::min(wr, w0));
    hr = std::max(1.0, std::min(hr, h0));
}

}  // namespace

bool map_region_through_geometry(const Region& in, int W, int H,
                                 const EditSpec& s, Region* out) {
    if (out == nullptr || W <= 0 || H <= 0) return false;
    // Work in pixels; the radius is rigid under flip/rot/straighten/crop.
    double px = in.x * W, py = in.y * H;
    const double pr = in.r * std::min(W, H);
    double cw = W, ch = H;

    // 1. Mirror (same order as apply_geometry).
    if (s.flipH) px = cw - px;
    if (s.flipV) py = ch - py;

    // 2. Quarter-turns clockwise: each turn maps (x,y) → (H−y, x), dims swap.
    for (int k = 0; k < ((s.rot90 % 4) + 4) % 4; ++k) {
        const double nx = ch - py, ny = px;
        px = nx; py = ny;
        std::swap(cw, ch);
    }

    // 3. Straighten: rotate about the canvas centre with the SAME convention as
    //    vips_rotate (y-down image space; positive angle appears clockwise),
    //    onto the enlarged bounding canvas, then the centred inscribed-rect crop.
    if (std::fabs(s.straighten) > 1e-6) {
        const double a = s.straighten * 3.14159265358979323846 / 180.0;
        const double ca = std::cos(a), sa = std::sin(a);
        const double rw = std::fabs(cw * ca) + std::fabs(ch * sa);
        const double rh = std::fabs(cw * sa) + std::fabs(ch * ca);
        const double vx = px - cw / 2, vy = py - ch / 2;
        px = ca * vx - sa * vy + rw / 2;
        py = sa * vx + ca * vy + rh / 2;
        double wr = cw, hr = ch;
        inscribed_rect(cw, ch, a, wr, hr);
        const double icw = std::min(rw, wr), ich = std::min(rh, hr);
        px -= (rw - icw) / 2;
        py -= (rh - ich) / 2;
        cw = icw; ch = ich;
    }

    // 4. Crop (normalized rect in the current space, mirroring apply_geometry's
    //    "cropW>0 and non-identity" gate).
    if (s.cropW > 0.0 &&
        (s.cropL != 0.0 || s.cropT != 0.0 || s.cropW != 1.0 || s.cropH != 1.0)) {
        px -= s.cropL * cw;
        py -= s.cropT * ch;
        cw *= s.cropW;
        ch *= s.cropH;
    }

    if (cw < 1 || ch < 1) return false;
    if (px < 0 || px > cw || py < 0 || py > ch) return false;  // cropped away
    out->x = static_cast<float>(px / cw);
    out->y = static_cast<float>(py / ch);
    out->r = static_cast<float>(pr / std::min(cw, ch));
    return true;
}

double geometry_zoom(const EditSpec& s) {
    double z = 1.0;
    if (s.cropW > 0.0) {
        const double m = std::min(s.cropW, s.cropH);
        z *= 1.0 / std::max(1e-3, m);
    } else {
        z *= 1.0;  // cropW<=0 means "no crop"
    }
    if (std::fabs(s.straighten) > 1e-6) {
        const double t = std::fabs(s.straighten) * 3.14159265358979323846 / 180.0;
        z *= (std::cos(t) + std::sin(t));  // inscribed-rect shrink upper bound
    }
    return z;
}

#ifdef PHOTO_HAVE_VIPS

VipsImage* apply_geometry(VipsImage* in, const EditSpec& s) {
    if (in == nullptr) return nullptr;
    // Own a ref to the running image; each successful op swaps it for its output.
    VipsImage* cur = in;
    g_object_ref(cur);
    if (!s.has_geometry()) return cur;  // identity: caller unrefs

    auto swap = [&](VipsImage* next) {
        g_object_unref(cur);
        cur = next;
    };

    // 1. Mirror.
    if (s.flipH) {
        VipsImage* o = nullptr;
        if (vips_flip(cur, &o, VIPS_DIRECTION_HORIZONTAL, nullptr) == 0) swap(o);
        else vips_error_clear();
    }
    if (s.flipV) {
        VipsImage* o = nullptr;
        if (vips_flip(cur, &o, VIPS_DIRECTION_VERTICAL, nullptr) == 0) swap(o);
        else vips_error_clear();
    }
    // 2. Quarter-turns (clockwise).
    if (s.rot90 != 0) {
        VipsAngle a = VIPS_ANGLE_D0;
        if (s.rot90 == 1) a = VIPS_ANGLE_D90;
        else if (s.rot90 == 2) a = VIPS_ANGLE_D180;
        else if (s.rot90 == 3) a = VIPS_ANGLE_D270;
        if (a != VIPS_ANGLE_D0) {
            VipsImage* o = nullptr;
            if (vips_rot(cur, &o, a, nullptr) == 0) swap(o);
            else vips_error_clear();
        }
    }
    // 3. Straighten: rotate by the angle, then crop the inscribed rect so no
    //    background border remains.
    if (std::fabs(s.straighten) > 1e-6) {
        const int W = vips_image_get_width(cur);
        const int H = vips_image_get_height(cur);
        VipsImage* rot = nullptr;
        if (vips_rotate(cur, &rot, s.straighten, nullptr) == 0) {
            double wr = W, hr = H;
            inscribed_rect(W, H, s.straighten * 3.14159265358979323846 / 180.0, wr, hr);
            const int rw = vips_image_get_width(rot);
            const int rh = vips_image_get_height(rot);
            int cw = std::min(rw, std::max(1, static_cast<int>(std::lround(wr))));
            int ch = std::min(rh, std::max(1, static_cast<int>(std::lround(hr))));
            const int left = std::max(0, (rw - cw) / 2);
            const int top = std::max(0, (rh - ch) / 2);
            cw = std::min(cw, rw - left);
            ch = std::min(ch, rh - top);
            VipsImage* cr = nullptr;
            if (vips_extract_area(rot, &cr, left, top, cw, ch, nullptr) == 0) {
                g_object_unref(rot);
                swap(cr);
            } else {
                vips_error_clear();
                swap(rot);  // keep the rotated (bordered) image rather than fail
            }
        } else {
            vips_error_clear();
        }
    }
    // 4. Crop — normalized rect in the current (post-rotate) space.
    if (s.cropW > 0.0 &&
        (s.cropL != 0.0 || s.cropT != 0.0 || s.cropW != 1.0 || s.cropH != 1.0)) {
        const int W = vips_image_get_width(cur);
        const int H = vips_image_get_height(cur);
        int left = std::clamp(static_cast<int>(std::lround(s.cropL * W)), 0, W - 1);
        int top = std::clamp(static_cast<int>(std::lround(s.cropT * H)), 0, H - 1);
        int cw = std::clamp(static_cast<int>(std::lround(s.cropW * W)), 1, W - left);
        int ch = std::clamp(static_cast<int>(std::lround(s.cropH * H)), 1, H - top);
        VipsImage* cr = nullptr;
        if (vips_extract_area(cur, &cr, left, top, cw, ch, nullptr) == 0) swap(cr);
        else vips_error_clear();
    }
    return cur;
}

#else  // !PHOTO_HAVE_VIPS — geometry needs libvips; passthrough.

VipsImage* apply_geometry(VipsImage* in, const EditSpec&) { return in; }

#endif

}  // namespace photo::edit
