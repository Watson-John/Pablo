// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// prototype.h — per-person prototype index. A person's prototype is the mean of
// the L2-normalized embeddings the user has confirmed for them (re-normalized).
// Drives suggest-and-confirm: a new face's nearest prototype within threshold
// becomes the suggestion the user accepts or rejects. In-memory, rebuilt from
// the store on load and updated incrementally on approve/reject.

#pragma once

#include <cstdint>
#include <unordered_map>
#include <vector>

#include "faces/types.h"

namespace photo::faces {

class PrototypeIndex {
public:
    // Rebuild every prototype from confirmed faces (person_id -> embeddings).
    void rebuild(const std::unordered_map<int64_t, std::vector<Embedding>>& confirmed);

    // Fold one newly-confirmed face into a person's prototype (running mean).
    void add_confirmed(int64_t person_id, const Embedding& embedding);

    // Remove a face's contribution when the user rejects it.
    void remove(int64_t person_id, const Embedding& embedding);

    // Nearest person to `embedding`; returns {person_id, cosine_similarity}.
    // person_id is -1 when the index is empty.
    struct Match { int64_t person_id = -1; float similarity = 0.0f; };
    Match nearest(const Embedding& embedding) const;

    // Parallel arrays for cluster.h's assign_nearest fast path.
    std::vector<Embedding> prototypes() const;
    std::vector<int64_t>   person_ids() const;

private:
    struct Entry { Embedding sum; Embedding mean; int32_t count = 0; };
    std::unordered_map<int64_t, Entry> by_person_;
};

}  // namespace photo::faces
