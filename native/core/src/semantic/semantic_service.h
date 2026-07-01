// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// semantic_service.h — per-asset embedding worker (Stage 9).
//
// Mirrors faces/face_service.cpp's role, but holds NO database connection: the
// engine owns the one catalog connection and persists the record this returns
// (single-writer, no second connection to reconcile). The service is pure CPU:
// decode → embed → dominant colour. It never throws; a decode/embed failure is
// reported as a Failed status + error string so one bad image can't wedge the
// run (a Stage-9 requirement).

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "catalog/catalog.h"  // Catalog::EmbeddingRecord
#include "semantic/embedder.h"

namespace photo::semantic {

class SemanticService {
public:
    // Decode `path` into a small tightly-packed RGBA buffer sized ≈`target` on
    // the long edge. Returns false if the image can't be read. Injectable so
    // tests exercise the pipeline without a real codec.
    using DecodeFn = std::function<bool(const std::string& path, int target,
                                        std::vector<uint8_t>& rgba, int& w, int& h)>;

    // If `decode` is empty, a built-in decoder (libvips/OpenCV, when compiled)
    // is used; where neither is available embed_asset returns Skipped.
    explicit SemanticService(std::unique_ptr<Embedder> embedder,
                             DecodeFn decode = {});

    int dim() const { return embedder_->dim(); }
    const std::string& model_id() const { return embedder_->model_id(); }
    const std::string& model_version() const { return embedder_->model_version(); }

    // Decode + embed one asset into a catalog record. Never throws.
    catalog::Catalog::EmbeddingRecord embed_asset(int64_t asset_id,
                                                  const std::string& path) const;

    // L2-normalized text-query embedding (for search).
    std::vector<float> embed_text(const std::string& query) const;

    // Reclaim lazily-loaded inference-session RAM (semantic::kRelease* mask).
    // Safe concurrently with embeds; the next call transparently reloads.
    void release_sessions(uint32_t mask) { embedder_->release_sessions(mask); }

    // Whether a decoder is available in this build (false ⇒ embed_asset Skips).
    static bool has_builtin_decoder();

private:
    std::unique_ptr<Embedder> embedder_;
    DecodeFn decode_;
    bool has_decoder_;  // false ⇒ no way to decode (embed_asset → Skipped)
};

}  // namespace photo::semantic
