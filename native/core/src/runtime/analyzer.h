// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// analyzer.h — the plugin-ready per-asset analysis seam. An IImageAnalyzer is
// anything that looks at an asset's pixels and produces a small JSON payload
// (a meme detector, an aesthetic scorer, a duplicate fingerprint, …). The
// registry is owned by Engine; results persist in the catalog's generic
// `analysis` table (analyzer_id, asset_id) → (version, status, payload), so
// the C ABI never grows per-analyzer — photo_analyzer_run / photo_analysis_get
// are payload-opaque.
//
// NOT yet a stable third-party API (see docs/EXTENDING.md): registration is
// compile-time (engine init) only. Faces and semantic search predate this
// seam and keep their bespoke storage/eventing; they migrate if/when a real
// SDK lands. Header-only on purpose — no 4-place plugin registration.
//
// Versioning contract (mirrors the semantic embedder rule): a persisted row
// whose `version` differs from the analyzer's current version() is STALE and
// should be re-run by the caller; version bumps are how an analyzer upgrade
// invalidates old results.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "semantic/embedder.h"  // semantic::PixelView (borrowed RGB(A) view)

namespace photo::runtime {

struct AnalyzerResult {
    // photo_status_t semantics: 0 = OK; non-zero = failure (payload ignored).
    int32_t status = 0;
    // Small JSON document; the schema is the analyzer's own contract.
    std::string payload_json;
};

class IImageAnalyzer {
public:
    virtual ~IImageAnalyzer() = default;
    IImageAnalyzer(const IImageAnalyzer&) = delete;
    IImageAnalyzer& operator=(const IImageAnalyzer&) = delete;

    // Stable identity, e.g. "meme.detector". Persisted with every result row.
    virtual const std::string& id() const = 0;
    // Bumped ⇒ previously persisted rows for this analyzer become stale.
    virtual const std::string& version() const = 0;
    // False when a dependency (model file, optional lib) is missing; run()
    // is then never called and photo_analyzer_run reports UNSUPPORTED.
    virtual bool available() const = 0;

    // Analyze one asset's decoded pixels. Called OFF the catalog lock on the
    // idle lane; must be thread-safe against itself (one analyzer instance
    // may run for several assets concurrently).
    virtual AnalyzerResult analyze(int64_t asset_id,
                                   const semantic::PixelView& px) = 0;

protected:
    IImageAnalyzer() = default;
};

// Owned by Engine. Registration happens during engine construction ONLY —
// after that the set is immutable, so lookups need no locking.
class AnalyzerRegistry {
public:
    void register_analyzer(std::unique_ptr<IImageAnalyzer> a) {
        analyzers_.push_back(std::move(a));
    }

    IImageAnalyzer* find(const std::string& id) const {
        for (const auto& a : analyzers_)
            if (a->id() == id) return a.get();
        return nullptr;
    }

    // (id, version, available) triples for photo_analyzer_list.
    std::vector<std::pair<std::string, std::string>> list_ids_versions() const {
        std::vector<std::pair<std::string, std::string>> out;
        out.reserve(analyzers_.size());
        for (const auto& a : analyzers_) out.emplace_back(a->id(), a->version());
        return out;
    }

    bool empty() const { return analyzers_.empty(); }

private:
    std::vector<std::unique_ptr<IImageAnalyzer>> analyzers_;
};

}  // namespace photo::runtime
