// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// types.h — value types for the face subsystem (M6/M7). Dependency-free so
// every face header includes it cheaply. Models + algorithm chosen by the
// eval bake-off: SCRFD-10G detect -> 5-pt align -> AuraFace embed (512-d) ->
// agglomerative cluster. See native/models/MANIFEST.md and DECISIONS.md §D2.

#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace photo::faces {

// Axis-aligned face box in source-image pixels.
struct Box {
    float x = 0, y = 0, w = 0, h = 0;
};

// Five facial landmarks in ArcFace template order:
// [left eye, right eye, nose, left mouth, right mouth] — matches the 112x112
// alignment template (see align.h). Coordinates in source-image pixels.
using Landmarks5 = std::array<float, 10>;  // x0,y0,x1,y1,...,x4,y4

// One face the detector found in an image.
struct DetectedFace {
    Box box;
    Landmarks5 landmarks{};
    float score = 0.0f;        // detector confidence
};

// A 512-d (AuraFace) or 128-d (SFace) L2-normalized embedding.
using Embedding = std::vector<float>;

// A persisted face: detection result + its embedding + cluster/person link.
struct FaceRecord {
    int64_t id = 0;            // SQLite rowid
    int64_t asset_id = 0;
    Box box;
    Landmarks5 landmarks{};
    float det_score = 0.0f;
    float quality = 0.0f;      // sharpness * size gate (Picasa-style facequality)
    int64_t vec_row = -1;      // row in the flat embedding store (-1 = none)
    int64_t cluster_id = -1;   // -1 = unassigned / singleton
    int64_t person_id = -1;    // -1 = unconfirmed
    bool    confirmed = false; // false = online-assign suggestion, true = user-confirmed
    bool    ignored = false;   // user hid this detection (Picasa ]ignoreface) — excluded from people
    bool    manual = false;    // user drew this rectangle by hand (no detector/embedding)
    // Profile that embedded this face (model_registry.h). '' = legacy rows,
    // attributed to the default profile. Non-active rows are STALE: their
    // vec_row indexes a different per-profile vectors file, so they are
    // excluded from prototype folds/rebuilds until rescanned.
    std::string model_id;
};

// A person = a confirmed cluster, with a prototype template (mean of its best
// embeddings) used for online assignment of new faces.
struct Person {
    int64_t id = 0;
    std::string name;          // empty until the user names them
    int64_t prototype_row = -1;
    int32_t face_count = 0;
    int32_t confirmed_count = 0;
    bool confirmed = false;
};

}  // namespace photo::faces
