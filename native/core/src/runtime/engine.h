// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// engine.h — composition root for the native core.
//
// Engine owns the slot store, the event ring, and (in later milestones) the
// scheduler / cache / catalog / ML runtime. M1 holds the slot+event subset
// only.

#pragma once

#include <filesystem>
#include <memory>
#include <string>

#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"
#include "runtime/slot_store.h"
#include "thumb/thumb_service.h"

#ifdef PHOTO_HAVE_FACES
#include "faces/face_service.h"
#endif

namespace photo {

class ThumbCache;

class Engine {
public:
    // Create from a (validated) configuration. May throw on fatal init.
    // Wrapped by photo_engine_create which returns nullptr on failure.
    static std::unique_ptr<Engine> create(const photo_config_t& cfg);

    ~Engine();

    Engine(const Engine&) = delete;
    Engine& operator=(const Engine&) = delete;

    SlotStore&    slots()        { return slots_; }
    EventRing&    events()       { return events_; }
    JobSystem&    jobs()         { return jobs_; }
    ThumbService& thumbs()       { return thumbs_; }
#ifdef PHOTO_HAVE_FACES
    faces::FaceService& faces()  { return faces_; }
#endif

    const std::filesystem::path& catalog_path() const { return catalog_path_; }
    const std::filesystem::path& cache_path()   const { return cache_path_; }
    const std::filesystem::path& models_path()  const { return models_path_; }

    uint64_t memory_budget_bytes() const { return memory_budget_; }
    uint64_t disk_budget_bytes()   const { return disk_budget_; }

private:
    Engine(std::filesystem::path catalog_path,
           std::filesystem::path cache_path,
           std::filesystem::path models_path,
           uint64_t memory_budget,
           uint64_t disk_budget,
           uint32_t decode_threads);

    // Owned thumbnail cache. Declared first so it is destroyed last — after
    // the job system's workers, which reference it through ThumbService.
    std::unique_ptr<ThumbCache> cache_;

    SlotStore                 slots_;
    // Sized for scroll bursts: dozens of visible tiles each emit several
    // stage-ready events, plus face-scan progress. A small ring overflowed and
    // dropped stage upgrades, leaving thumbnails stuck on the placeholder.
    EventRing                 events_{16384};
    JobSystem                 jobs_;
    ThumbService              thumbs_;
#ifdef PHOTO_HAVE_FACES
    faces::FaceService        faces_;
#endif

    std::filesystem::path     catalog_path_;
    std::filesystem::path     cache_path_;
    std::filesystem::path     models_path_;
    uint64_t                  memory_budget_;
    uint64_t                  disk_budget_;
};

}  // namespace photo
