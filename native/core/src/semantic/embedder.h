// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// embedder.h — the swappable semantic-embedding backend (Stage 9).
//
// An Embedder maps BOTH images and text queries into the SAME vector space, so
// a text query can rank images by cosine similarity (CLIP-style retrieval). Two
// backends implement it:
//
//   • DeterministicEmbedder (make_deterministic_embedder) — pure C++, no OpenCV/
//     ONNX/vips. A colour/brightness "concept" model: it covers colour- and
//     tone-correlated queries (red, blue, sky, snow, sunset, foliage, water, …)
//     and lets the whole indexing/search pipeline run + be tested offline. It is
//     the always-available default and fallback.
//
//   • OnnxEmbedder (make_onnx_embedder) — the real model (siglip2 / PE-Core),
//     compiled only with SEMANTIC_HAVE_ORT and only usable when the image+text
//     model files (and a tokenizer) are present. This is the drop-in that turns
//     on true text-semantics (tree→trees). Returns nullptr otherwise so callers
//     fall back to the deterministic backend.
//
// Swapping models is a first-class requirement: every embedding row records the
// producing (model_id, model_version) so a switch re-queues stale rows.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace photo::semantic {

// A borrowed view of decoded pixels: row-major RGB8 or RGBA8.
struct PixelView {
    const uint8_t* pixels = nullptr;  // `channels` bytes per pixel
    int width = 0;
    int height = 0;
    int channels = 4;  // 3 (RGB) or 4 (RGBA); alpha ignored
    int stride = 0;    // bytes per row; 0 ⇒ width*channels
};

// Bit mask for Embedder::release_sessions.
inline constexpr uint32_t kReleaseImageTower = 1u << 0;
inline constexpr uint32_t kReleaseTextTower = 1u << 1;

class Embedder {
public:
    virtual ~Embedder() = default;
    virtual int dim() const = 0;
    virtual const std::string& model_id() const = 0;
    virtual const std::string& model_version() const = 0;
    // L2-normalized image embedding; empty on failure.
    virtual std::vector<float> embed_image(const PixelView& px) const = 0;
    // L2-normalized text embedding for a (possibly multi-word) query.
    virtual std::vector<float> embed_text(const std::string& query) const = 0;
    // Drop lazily-loaded inference sessions to reclaim RAM (kRelease* mask).
    // The next embed_* call transparently reloads (~1 s). The UI calls this
    // when the indexing queue drains (image tower, ~500 MB) and after a search
    // idle timeout (text tower, ~300 MB). No-op for sessionless backends.
    virtual void release_sessions(uint32_t /*mask*/) {}
};

// The always-available default (colour/brightness concept model).
std::unique_ptr<Embedder> make_deterministic_embedder();

// The real model backend. nullptr unless built with SEMANTIC_HAVE_ORT and the
// model + tokenizer files exist under models_dir.
std::unique_ptr<Embedder> make_onnx_embedder(const std::string& models_dir);

}  // namespace photo::semantic
