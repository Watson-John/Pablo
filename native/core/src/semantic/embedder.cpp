// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "semantic/embedder.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <unordered_map>

namespace photo::semantic {
namespace {

// ── Shared concept space ─────────────────────────────────────────────────────
// Image and text both project onto these bins, so cosine(text, image) is a
// meaningful retrieval score for colour/tone-correlated concepts.
enum Concept {
    kRed = 0, kWarm, kYellow, kGreen, kCyan, kBlue, kPurple, kPink,
    kBright, kDark, kNeutral, kSkin, kSky, kFoliage, kWater, kSunset,
    kConceptCount,
};

void l2_normalize(std::vector<float>& v) {
    double s = 0.0;
    for (float x : v) s += static_cast<double>(x) * x;
    if (s <= 1e-12) return;  // all-zero stays zero (ranks last, never NaN)
    const float inv = static_cast<float>(1.0 / std::sqrt(s));
    for (float& x : v) x *= inv;
}

// Standard HSV hue in degrees [0,360) + saturation/value in [0,1].
void rgb_to_hsv(float r, float g, float b, float& h, float& s, float& v) {
    const float mx = std::max({r, g, b});
    const float mn = std::min({r, g, b});
    v = mx;
    const float d = mx - mn;
    s = mx > 1e-6f ? d / mx : 0.0f;
    if (d < 1e-6f) { h = 0.0f; return; }
    if (mx == r)      h = 60.0f * std::fmod((g - b) / d, 6.0f);
    else if (mx == g) h = 60.0f * ((b - r) / d + 2.0f);
    else              h = 60.0f * ((r - g) / d + 4.0f);
    if (h < 0.0f) h += 360.0f;
}

bool in_hue(float h, float lo, float hi) {
    if (lo <= hi) return h >= lo && h < hi;
    return h >= lo || h < hi;  // wrap-around (e.g. red 345..15)
}

class DeterministicEmbedder final : public Embedder {
public:
    DeterministicEmbedder()
        : model_id_("deterministic-color"), model_version_("1") {
        build_lexicon();
    }

    int dim() const override { return kConceptCount; }
    const std::string& model_id() const override { return model_id_; }
    const std::string& model_version() const override { return model_version_; }

    std::vector<float> embed_image(const PixelView& px) const override {
        std::vector<float> acc(kConceptCount, 0.0f);
        if (!px.pixels || px.width <= 0 || px.height <= 0) return acc;
        const int ch = px.channels >= 3 ? px.channels : 3;
        const int stride = px.stride > 0 ? px.stride : px.width * ch;
        // Subsample to ≲4096 pixels for O(1) cost regardless of resolution.
        const int step = std::max(1, static_cast<int>(std::sqrt(
                             static_cast<double>(px.width) * px.height / 4096.0)));
        long n = 0;
        for (int y = 0; y < px.height; y += step) {
            const bool top = y < px.height / 3;
            const uint8_t* row = px.pixels + static_cast<size_t>(y) * stride;
            for (int x = 0; x < px.width; x += step) {
                const uint8_t* p = row + static_cast<size_t>(x) * ch;
                const float r = p[0] / 255.0f, g = p[1] / 255.0f, b = p[2] / 255.0f;
                float h, s, v;
                rgb_to_hsv(r, g, b, h, s, v);
                accumulate(acc, h, s, v, top);
                ++n;
            }
        }
        if (n > 0)
            for (float& a : acc) a /= static_cast<float>(n);
        l2_normalize(acc);
        return acc;
    }

    std::vector<float> embed_text(const std::string& query) const override {
        std::vector<float> acc(kConceptCount, 0.0f);
        std::string word;
        int matched = 0, words = 0;
        auto flush = [&] {
            if (word.empty()) return;
            ++words;
            auto it = lexicon_.find(word);
            if (it != lexicon_.end()) {
                ++matched;
                for (const auto& [c, w] : it->second) acc[c] += w;
            }
            word.clear();
        };
        for (char ch : query) {
            if (std::isalnum(static_cast<unsigned char>(ch)))
                word.push_back(static_cast<char>(std::tolower(
                    static_cast<unsigned char>(ch))));
            else
                flush();
        }
        flush();
        // Unknown-only queries have no colour signal — nudge them toward neutral
        // so they retrieve tonally-average images (the honest fallback) rather
        // than an all-zero vector that matches nothing.
        if (matched == 0 && words > 0) acc[kNeutral] += 1.0f;
        l2_normalize(acc);
        return acc;
    }

private:
    // Soft per-pixel membership into concept bins.
    static void accumulate(std::vector<float>& a, float h, float s, float v,
                           bool top) {
        if (s > 0.25f && in_hue(h, 345, 15))  a[kRed]    += 1.0f;
        if (s > 0.20f && in_hue(h, 15, 45))   a[kWarm]   += 1.0f;
        if (s > 0.20f && in_hue(h, 45, 70))   a[kYellow] += 1.0f;
        if (s > 0.15f && in_hue(h, 70, 160))  a[kGreen]  += 1.0f;
        if (s > 0.20f && in_hue(h, 160, 195)) a[kCyan]   += 1.0f;
        if (s > 0.20f && in_hue(h, 195, 255)) a[kBlue]   += 1.0f;
        if (s > 0.20f && in_hue(h, 255, 320)) a[kPurple] += 1.0f;
        if (s > 0.20f && in_hue(h, 320, 345)) a[kPink]   += 1.0f;
        if (v > 0.80f && s < 0.20f)           a[kBright] += 1.0f;
        if (v < 0.15f)                        a[kDark]   += 1.0f;
        if (s < 0.12f && v >= 0.20f && v <= 0.80f) a[kNeutral] += 1.0f;
        if (in_hue(h, 10, 45) && s > 0.20f && s < 0.60f && v > 0.30f && v < 0.85f)
            a[kSkin] += 1.0f;
        if (top && in_hue(h, 180, 250) && s > 0.15f) a[kSky] += 1.0f;
        if (in_hue(h, 70, 160) && s > 0.15f)         a[kFoliage] += 1.0f;
        if (!top && in_hue(h, 170, 250) && s > 0.15f) a[kWater] += 1.0f;
        if (in_hue(h, 330, 50) && s > 0.25f && v > 0.30f && v < 0.85f)
            a[kSunset] += 1.0f;
    }

    void add(const char* word, std::initializer_list<std::pair<Concept, float>> ws) {
        lexicon_[word] = {ws.begin(), ws.end()};
    }

    void build_lexicon() {
        add("red", {{kRed, 1.0f}});
        add("orange", {{kWarm, 1.0f}, {kSunset, 0.3f}});
        add("yellow", {{kYellow, 1.0f}, {kWarm, 0.4f}});
        add("gold", {{kYellow, 0.8f}, {kSunset, 0.5f}});
        add("golden", {{kYellow, 0.8f}, {kSunset, 0.6f}});
        add("green", {{kGreen, 1.0f}, {kFoliage, 0.6f}});
        add("cyan", {{kCyan, 1.0f}});
        add("teal", {{kCyan, 1.0f}});
        add("blue", {{kBlue, 1.0f}, {kSky, 0.4f}});
        add("purple", {{kPurple, 1.0f}});
        add("violet", {{kPurple, 1.0f}});
        add("pink", {{kPink, 1.0f}});
        add("white", {{kBright, 1.0f}});
        add("bright", {{kBright, 1.0f}});
        add("snow", {{kBright, 1.0f}, {kNeutral, 0.3f}});
        add("snowy", {{kBright, 1.0f}, {kNeutral, 0.3f}});
        add("winter", {{kBright, 0.7f}, {kNeutral, 0.3f}});
        add("ice", {{kBright, 0.8f}, {kCyan, 0.3f}});
        add("cloud", {{kBright, 0.7f}, {kSky, 0.5f}});
        add("clouds", {{kBright, 0.7f}, {kSky, 0.5f}});
        add("black", {{kDark, 1.0f}});
        add("dark", {{kDark, 1.0f}});
        add("night", {{kDark, 1.0f}});
        add("gray", {{kNeutral, 1.0f}});
        add("grey", {{kNeutral, 1.0f}});
        add("neutral", {{kNeutral, 1.0f}});
        add("portrait", {{kSkin, 0.6f}});
        add("sky", {{kSky, 1.0f}, {kBlue, 0.6f}});
        add("tree", {{kFoliage, 1.0f}, {kGreen, 0.7f}});
        add("trees", {{kFoliage, 1.0f}, {kGreen, 0.7f}});
        add("forest", {{kFoliage, 1.0f}, {kGreen, 0.7f}});
        add("grass", {{kFoliage, 1.0f}, {kGreen, 0.8f}});
        add("plant", {{kFoliage, 1.0f}, {kGreen, 0.6f}});
        add("plants", {{kFoliage, 1.0f}, {kGreen, 0.6f}});
        add("leaf", {{kFoliage, 0.9f}, {kGreen, 0.6f}});
        add("leaves", {{kFoliage, 0.9f}, {kGreen, 0.6f}});
        add("garden", {{kFoliage, 0.8f}, {kGreen, 0.6f}});
        add("nature", {{kFoliage, 0.8f}, {kGreen, 0.6f}});
        add("field", {{kFoliage, 0.7f}, {kGreen, 0.6f}});
        add("meadow", {{kFoliage, 0.8f}, {kGreen, 0.6f}});
        add("sea", {{kWater, 1.0f}, {kBlue, 0.5f}});
        add("ocean", {{kWater, 1.0f}, {kBlue, 0.5f}});
        add("water", {{kWater, 1.0f}, {kBlue, 0.4f}});
        add("lake", {{kWater, 1.0f}, {kBlue, 0.5f}});
        add("river", {{kWater, 1.0f}, {kBlue, 0.4f}});
        add("beach", {{kWater, 0.7f}, {kWarm, 0.4f}, {kBright, 0.3f}});
        add("wave", {{kWater, 0.9f}, {kBlue, 0.4f}});
        add("waves", {{kWater, 0.9f}, {kBlue, 0.4f}});
        add("sunset", {{kSunset, 1.0f}, {kWarm, 0.6f}});
        add("sunrise", {{kSunset, 1.0f}, {kWarm, 0.6f}});
        add("dusk", {{kSunset, 0.9f}, {kWarm, 0.5f}});
        add("dawn", {{kSunset, 0.9f}, {kWarm, 0.5f}});
        add("wedding", {{kBright, 0.8f}, {kNeutral, 0.2f}});
    }

    std::string model_id_;
    std::string model_version_;
    std::unordered_map<std::string, std::vector<std::pair<Concept, float>>> lexicon_;
};

}  // namespace

std::unique_ptr<Embedder> make_deterministic_embedder() {
    return std::make_unique<DeterministicEmbedder>();
}

#ifndef SEMANTIC_HAVE_ORT
// Real-model backend not compiled in — callers fall back to deterministic.
// The ONNX implementation (image + text encoder + tokenizer) lands here, guarded
// by SEMANTIC_HAVE_ORT, when the model files are shipped. See
// docs/specs/09-search-and-discovery.md and native/models/MANIFEST.md.
std::unique_ptr<Embedder> make_onnx_embedder(const std::string&) {
    return nullptr;
}
#endif

}  // namespace photo::semantic
