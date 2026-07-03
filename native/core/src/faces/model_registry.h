// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// model_registry.h — the face-model profile table. Mirrors the semantic
// module's swappable-Embedder pattern: everything model-specific (file names,
// embedding dimension, preprocessing constants, thresholds) lives in a
// profile row, and the active profile is whichever row's model files exist in
// the models directory — so shipping a new/more-accurate face stack is a new
// table row + model files, not a code edit through FaceService.
//
// Header-only and pure-std on purpose: it resolves profiles by filesystem
// probe alone, so the lean (no-OpenCV/ORT) build can compile and unit-test
// resolution, and no new .cpp needs the 4-place plugin registration.
//
// Face rows persist the profile that embedded them (face.model_id/version);
// rows from a non-active profile are STALE: excluded from prototype rebuilds
// and counted by FaceStore::count_stale so the UI can offer a re-scan.
// Vectors are per-profile files (a dim change must never write into another
// profile's fixed-width matrix); the default profile keeps the legacy
// `.faces.vec` name so existing installs keep their data.

#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace photo::faces {

struct FaceModelProfile {
    // Stable identity, persisted per face row. Bump `model_version` when the
    // SAME files change semantics (retrain); change `model_id` for a
    // different stack.
    const char* model_id;
    const char* model_version;

    // Model files, resolved relative to the engine's models directory.
    const char* detector_file;
    const char* embedder_file;

    // Embedder contract.
    int embed_dim;
    float embed_mean;   // ArcFace convention: (px - mean) / scale, RGB order
    float embed_scale;
    bool tta;           // average with horizontal flip (+~2pts, see eval/)

    // Detector thresholds.
    float det_score_threshold;
    float det_nms_threshold;

    // Agglomerative/online-assign merge distance (1 - cosine similarity).
    float merge_distance;
};

/// The default profile's id — rows recorded before model_id existed ('' in
/// SQLite) are attributed to it, and it keeps the legacy vectors filename.
inline constexpr const char* kDefaultFaceModelId = "scrfd10g+auraface";

/// Priority-ordered profile table: the first row whose files exist wins.
/// AuraFace is the eval/ bake-off winner (D2); SFace is the small fallback.
inline const std::vector<FaceModelProfile>& face_model_profiles() {
    static const std::vector<FaceModelProfile> kProfiles = {
        {kDefaultFaceModelId, "1", "scrfd_10g.onnx", "auraface.onnx",
         /*dim=*/512, /*mean=*/127.5f, /*scale=*/127.5f, /*tta=*/true,
         /*score=*/0.5f, /*nms=*/0.45f, /*merge=*/0.45f},
        {"scrfd10g+sface", "1", "scrfd_10g.onnx", "sface.onnx",
         /*dim=*/128, /*mean=*/127.5f, /*scale=*/128.0f, /*tta=*/true,
         /*score=*/0.5f, /*nms=*/0.45f, /*merge=*/0.45f},
    };
    return kProfiles;
}

/// First profile whose model files are both present, else nullptr (no models
/// downloaded / faces disabled) — mirrors make_onnx_embedder's probe→fallback.
inline const FaceModelProfile* resolve_face_profile(
    const std::filesystem::path& models_dir) {
    std::error_code ec;
    for (const auto& p : face_model_profiles()) {
        if (std::filesystem::exists(models_dir / p.detector_file, ec) &&
            std::filesystem::exists(models_dir / p.embedder_file, ec))
            return &p;
    }
    return nullptr;
}

/// The vectors-file suffix for a profile (appended to the catalog path).
/// Default profile keeps the pre-registry name so existing data survives.
inline std::string vectors_suffix_for(const FaceModelProfile& p) {
    if (std::string(p.model_id) == kDefaultFaceModelId) return ".faces.vec";
    return std::string(".faces.") + p.model_id + ".vec";
}

}  // namespace photo::faces
