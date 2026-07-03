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

#include <array>
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "faces/model_registry.h"
#include "photo_core.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"

namespace photo::faces {

class FacePipeline;
class FaceStore;
class PrototypeIndex;
struct FaceRecord;

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

    // photo_face_name_cluster: promote an unconfirmed cluster into a named
    // person. Finds an existing person with the same name (merge) or creates a
    // new one, then confirms every face in the cluster into it (folding their
    // embeddings into the prototype). Returns a request id; emits
    // PHOTO_EVT_CLUSTER_UPDATED on completion.
    uint64_t name_cluster(int64_t cluster_id, const std::string& name);

    // --- read-back (UI queries). Synchronous; thread-safe against workers.
    // Return POD rows ready for the C-ABI (photo_core.h types). Empty if the
    // store/models are unavailable. ---
    std::vector<photo_person_t> list_people();
    std::vector<photo_person_t> list_clusters();      // unconfirmed buckets
    std::vector<photo_face_t>   list_cluster_faces(int64_t cluster_id);
    std::vector<photo_face_t>   list_suggestions(uint64_t person_id);
    std::vector<photo_face_t>   list_for_asset(uint64_t asset_id);
    // Eye landmark pairs {leftX, leftY, rightX, rightY} in source-image pixels for
    // each detected face in the asset — feeds the red-eye auto-detect. Empty
    // without a store / models.
    std::vector<std::array<float, 4>> eye_landmarks_for_asset(uint64_t asset_id);
    bool name_person(uint64_t person_id, const std::string& name);

    // --- face editing (persistence only; NO models required) ---
    // Hide/restore a detection (Picasa ]ignoreface). Excluded from people.
    bool set_ignored(uint64_t face_id, bool ignored);
    // Add a hand-drawn face rectangle (source-image pixels). Returns face_id, 0 on fail.
    uint64_t add_manual_face(uint64_t asset_id, float x, float y, float w, float h);
    // Assign a face to a named person (create/merge), confirming it.
    bool assign_face(uint64_t face_id, const std::string& name);
    // Hard-delete a face row (manual-rect undo).
    bool remove_face(uint64_t face_id);

    // Named face regions of an asset, in source-image pixels, for XMP export.
    struct NamedRegion { std::string name; float x, y, w, h; };
    std::vector<NamedRegion> named_regions_for_asset(uint64_t asset_id);

    static bool available();  // FACES_HAVE_ORT

    // --- model registry (model_registry.h) ---
    // Active profile id ("scrfd10g+auraface"); resolved by filesystem probe.
    std::string active_model_id();
    // Embedded faces whose profile is no longer active (their vectors live in
    // another per-profile file, so they sit out of prototypes until rescanned).
    int64_t stale_face_count();
    // Delete unconfirmed stale rows so a fresh scan can repopulate them.
    // Confirmed rows keep their person link. Returns rows deleted.
    int64_t prune_stale_faces();

private:
    // Allocate a request id, submit `fn(request_id)` on `lane`, and uniformly
    // track the in-flight job in request_to_job_ (erasing on completion). Every
    // submit_*/approve/reject/rebuild/name_cluster routes through this so the
    // bookkeeping can't drift and a future cancel sees all of them.
    uint64_t submit_face_job(int lane, std::function<void(uint64_t request_id)> fn);

    // The single definition of "confirm a face into a person": link + mark
    // confirmed + fold the embedding into the prototype. REQUIRES store_mu_ held.
    void confirm_face_locked(const FaceRecord& f, int64_t person);

    void run_scan(uint64_t request_id, uint64_t asset_id, std::string path);
    void run_rebuild(uint64_t request_id);
    void emit_scan_progress(uint64_t request_id, uint64_t asset_id, int32_t status,
                            uint32_t n_faces);
    void emit_cluster_updated(uint64_t request_id);

    // Lazily open the FaceStore + prototype index (SQLite only — cheap, no ML).
    // A prerequisite for both read-back and ensure_models().
    bool ensure_store();
    // Lazily load the ONNX detector + embedder (expensive; may fail). Implies
    // ensure_store().
    bool ensure_models();

    EventRing* events_;
    JobSystem* jobs_;
    std::filesystem::path models_dir_;
    std::filesystem::path catalog_path_;

    std::once_flag store_once_;
    bool store_ok_ = false;
    std::once_flag models_once_;
    bool models_ok_ = false;
    // Serializes all FaceStore access: UI read queries vs. worker writes.
    std::mutex store_mu_;
    // The active profile (nullptr = no model files found) + the pipeline
    // constructed from it. Model specifics live in the profile, not here.
    const FaceModelProfile* profile_ = nullptr;
    std::unique_ptr<FacePipeline> pipeline_;
    std::unique_ptr<FaceStore> store_;
    std::unique_ptr<PrototypeIndex> prototypes_;

    std::atomic<uint64_t> next_request_id_{1};
    std::mutex req_mu_;
    std::unordered_map<uint64_t, uint64_t> request_to_job_;
};

}  // namespace photo::faces
