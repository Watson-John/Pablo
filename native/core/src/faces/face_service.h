// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// face_service.h — the face subsystem (M6 detect/embed, M7 cluster), mirroring
// ThumbService: requests enqueue onto the JobSystem; workers run the pipeline
// (decode -> SCRFD detect -> 5-pt align -> AuraFace embed -> store -> assign);
// progress + results emit via the EventRing (PHOTO_EVT_SCAN_PROGRESS,
// PHOTO_EVT_CLUSTER_UPDATED). Owned by Engine, reached via engine.faces().
//
// Built only when FACES_HAVE_ORT; without it submit()s emit a failed status.

#pragma once

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"

namespace photo::faces {

class Detector;
class Embedder;
class FaceStore;
class PrototypeIndex;

class FaceService {
public:
    FaceService(EventRing* events, JobSystem* jobs, std::filesystem::path models_dir,
                std::filesystem::path catalog_path);
    ~FaceService();

    FaceService(const FaceService&) = delete;
    FaceService& operator=(const FaceService&) = delete;

    // photo_face_scan: detect+align+embed faces in an asset, persist, and assign
    // to the nearest existing person prototype (online). Returns a request id.
    uint64_t submit_scan(uint64_t asset_id, const char* path_utf8, uint32_t flags);

    // photo_face_approve / photo_face_reject: confirm or reject a face's
    // membership in a cluster; updates the person prototype.
    uint64_t approve(uint64_t cluster_id, uint64_t embedding_id);
    uint64_t reject(uint64_t cluster_id, uint64_t embedding_id);

    // photo_cluster_rebuild: full agglomerative re-cluster (idle lane).
    uint64_t rebuild_clusters(uint32_t flags);

    // --- read-back (UI queries). Synchronous; thread-safe against workers.
    // Return POD rows ready for the C-ABI (photo_core.h types). Empty if the
    // store/models are unavailable. ---
    std::vector<photo_person_t> list_people();
    std::vector<photo_person_t> list_clusters();      // unconfirmed buckets
    std::vector<photo_face_t>   list_cluster_faces(int64_t cluster_id);
    std::vector<photo_face_t>   list_suggestions(uint64_t person_id);
    std::vector<photo_face_t>   list_for_asset(uint64_t asset_id);
    bool name_person(uint64_t person_id, const std::string& name);

    static bool available();  // FACES_HAVE_ORT

private:
    void run_scan(uint64_t request_id, uint64_t asset_id, std::string path);
    void run_rebuild(uint64_t request_id);
    void emit_scan_progress(uint64_t request_id, uint64_t asset_id, int32_t status,
                            uint32_t n_faces);
    void emit_cluster_updated(uint64_t request_id);

    // Lazily constructed on first scan (model load is expensive + may fail).
    bool ensure_models();

    EventRing* events_;
    JobSystem* jobs_;
    std::filesystem::path models_dir_;
    std::filesystem::path catalog_path_;

    std::once_flag models_once_;
    bool models_ok_ = false;
    // Serializes all FaceStore access: UI read queries vs. worker writes.
    std::mutex store_mu_;
    std::unique_ptr<Detector> detector_;
    std::unique_ptr<Embedder> embedder_;
    std::unique_ptr<FaceStore> store_;
    std::unique_ptr<PrototypeIndex> prototypes_;

    std::atomic<uint64_t> next_request_id_{1};
    std::mutex req_mu_;
    std::unordered_map<uint64_t, uint64_t> request_to_job_;
};

}  // namespace photo::faces
