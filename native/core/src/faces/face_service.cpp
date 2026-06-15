// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/face_service.h"

#include <algorithm>
#include <utility>

#include "faces/align.h"
#include "faces/cluster.h"
#include "faces/detector.h"
#include "faces/embed.h"
#include "faces/prototype.h"
#include "faces/store.h"
#include "util/log.h"

#ifdef PHOTO_HAVE_FACES
#include <opencv2/imgcodecs.hpp>
#endif

namespace photo::faces {

namespace {
// Idle lane for the heavy face pipeline so it never starves interactive
// thumbnail decodes. Matches the JobSystem lane convention (higher = lower
// priority); face work runs behind scroll-driven thumb requests.
constexpr int kFaceLane = 32;
// Drop faces smaller than this (box short side, source px) or blurrier than the
// sharpness floor — the quality gate that kept blurry scans from poisoning
// clusters in eval/. Tuned alongside the detector bake-off.
constexpr float kMinFacePx = 48.0f;
constexpr float kMinSharpness = 8.0f;
constexpr float kMergeDistance = 0.45f;  // cluster.h ClusterParams default
constexpr int   kEmbedDim = 512;         // AuraFace
}  // namespace

FaceService::FaceService(EventRing* events, JobSystem* jobs,
                         std::filesystem::path models_dir,
                         std::filesystem::path catalog_path)
    : events_(events), jobs_(jobs),
      models_dir_(std::move(models_dir)), catalog_path_(std::move(catalog_path)) {}

FaceService::~FaceService() = default;

bool FaceService::available() {
#ifdef FACES_HAVE_ORT
    return true;
#else
    return false;
#endif
}

bool FaceService::ensure_models() {
    std::call_once(models_once_, [this] {
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
        try {
            const auto det = models_dir_ / "scrfd_10g.onnx";
            const auto emb = models_dir_ / "auraface.onnx";
            detector_ = std::make_unique<Detector>(det.string());
            embedder_ = std::make_unique<Embedder>(emb.string(), 127.5f, 127.5f);
            store_ = std::make_unique<FaceStore>(catalog_path_.string(), kEmbedDim);
            prototypes_ = std::make_unique<PrototypeIndex>();
            prototypes_->rebuild(store_->confirmed_by_person());
            models_ok_ = true;
            PHOTO_LOGF(PHOTO_LOG_INFO, "faces: models loaded (scrfd_10g + auraface)");
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_ERROR, "faces: model load failed: %s", e.what());
            models_ok_ = false;
        }
#else
        PHOTO_LOGF(PHOTO_LOG_WARN, "faces: built without ONNX Runtime/OpenCV");
        models_ok_ = false;
#endif
    });
    return models_ok_;
}

uint64_t FaceService::submit_scan(uint64_t asset_id, const char* path_utf8,
                                  uint32_t flags) {
    (void)flags;  // reserved (e.g. force-rescan); the pipeline runs on the idle lane.
    const uint64_t request_id = next_request_id_.fetch_add(1, std::memory_order_relaxed);
    std::string path = path_utf8 ? std::string(path_utf8) : std::string{};

    auto handle = jobs_->submit(kFaceLane,
        [this, request_id, asset_id, p = std::move(path)]() mutable {
            run_scan(request_id, asset_id, std::move(p));
            std::lock_guard lk(req_mu_);
            request_to_job_.erase(request_id);
        });
    {
        std::lock_guard lk(req_mu_);
        request_to_job_.emplace(request_id, handle.id);
    }
    return request_id;
}

uint64_t FaceService::rebuild_clusters(uint32_t /*flags*/) {
    const uint64_t request_id = next_request_id_.fetch_add(1, std::memory_order_relaxed);
    auto handle = jobs_->submit(kFaceLane + 1,  // lowest priority
        [this, request_id]() { run_rebuild(request_id); });
    {
        std::lock_guard lk(req_mu_);
        request_to_job_.emplace(request_id, handle.id);
    }
    return request_id;
}

uint64_t FaceService::approve(uint64_t /*cluster_id*/, uint64_t embedding_id) {
    // Confirm a face's membership: fold its embedding into the person prototype
    // and persist the person link. cluster_id maps to a person; for the scaffold
    // we treat the cluster_id as the person_id (1:1 until split/merge UI lands).
    const uint64_t request_id = next_request_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_->submit(kFaceLane, [this, request_id, embedding_id]() {
        if (!ensure_models() || !store_ || !prototypes_) return;
        if (auto f = store_->face_by_id(static_cast<int64_t>(embedding_id))) {
            const Embedding v = store_->vectors().row(f->vec_row);
            int64_t person = f->person_id;
            if (person < 0) person = store_->create_person();
            store_->set_person(f->id, person);
            prototypes_->add_confirmed(person, v);
        }
        emit_cluster_updated(request_id);
    });
    return request_id;
}

uint64_t FaceService::reject(uint64_t /*cluster_id*/, uint64_t embedding_id) {
    const uint64_t request_id = next_request_id_.fetch_add(1, std::memory_order_relaxed);
    jobs_->submit(kFaceLane, [this, request_id, embedding_id]() {
        if (!ensure_models() || !store_ || !prototypes_) return;
        if (auto f = store_->face_by_id(static_cast<int64_t>(embedding_id))) {
            if (f->person_id >= 0) {
                const Embedding v = store_->vectors().row(f->vec_row);
                prototypes_->remove(f->person_id, v);
                store_->set_person(f->id, -1);
            }
        }
        emit_cluster_updated(request_id);
    });
    return request_id;
}

void FaceService::run_scan(uint64_t request_id, uint64_t asset_id, std::string path) {
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
    if (!ensure_models() || !models_ok_) {
        emit_scan_progress(request_id, asset_id, PHOTO_STATUS_UNSUPPORTED, 0);
        return;
    }
    // Idempotent: a re-scan of an already-processed asset is a no-op.
    if (store_->asset_scanned(static_cast<int64_t>(asset_id))) {
        emit_scan_progress(request_id, asset_id, PHOTO_STATUS_OK, 0);
        return;
    }
    // TODO(M5): route decode through the shared thumb/codec pipeline (libvips +
    // LibRaw) instead of cv::imread, so RAW/HEIC and color management match the
    // rest of the app. cv::imread is the scaffold path.
    cv::Mat bgr = cv::imread(path, cv::IMREAD_COLOR);
    if (bgr.empty()) {
        emit_scan_progress(request_id, asset_id, PHOTO_STATUS_IO_ERROR, 0);
        return;
    }

    std::vector<DetectedFace> faces = detector_->detect(bgr);
    uint32_t kept = 0;
    for (const auto& df : faces) {
        if (std::min(df.box.w, df.box.h) < kMinFacePx) continue;  // size gate
        cv::Mat aligned = align_arcface(bgr, df.landmarks);
        const float q = face_quality(aligned);
        if (q < kMinSharpness) continue;                          // blur gate

        Embedding vec = embedder_->embed(aligned, /*tta=*/true);

        FaceRecord rec;
        rec.asset_id = static_cast<int64_t>(asset_id);
        rec.box = df.box;
        rec.landmarks = df.landmarks;
        rec.det_score = df.score;
        rec.quality = q;
        store_->insert_face(rec, vec.data());

        // Online assignment: nearest confirmed prototype within threshold.
        auto match = prototypes_->nearest(vec);
        if (match.person_id >= 0 && (1.0f - match.similarity) <= kMergeDistance) {
            store_->set_cluster(rec.id, match.person_id);
            store_->set_person(rec.id, match.person_id);  // suggestion (unconfirmed)
        }
        ++kept;
    }
    emit_scan_progress(request_id, asset_id, PHOTO_STATUS_OK, kept);
#else
    emit_scan_progress(request_id, asset_id, PHOTO_STATUS_UNSUPPORTED, 0);
#endif
}

void FaceService::run_rebuild(uint64_t request_id) {
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
    if (!ensure_models() || !models_ok_) { emit_cluster_updated(request_id); return; }
    std::vector<FaceRecord> faces = store_->all_faces();
    if (faces.empty()) { emit_cluster_updated(request_id); return; }

    std::vector<Embedding> embs;
    embs.reserve(faces.size());
    for (const auto& f : faces) embs.push_back(store_->vectors().row(f.vec_row));

    ClusterParams params;
    params.merge_distance = kMergeDistance;
    std::vector<int64_t> labels = cluster_agglomerative(embs, params);
    for (size_t i = 0; i < faces.size(); ++i)
        store_->set_cluster(faces[i].id, labels[i]);
    emit_cluster_updated(request_id);
#else
    emit_cluster_updated(request_id);
#endif
}

void FaceService::emit_scan_progress(uint64_t request_id, uint64_t asset_id,
                                     int32_t status, uint32_t n_faces) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_SCAN_PROGRESS;
    e.status = status;
    e.request_id = request_id;
    e.asset_id = asset_id;
    e.aux64 = n_faces;  // faces detected+kept in this asset
    events_->push(e);
}

void FaceService::emit_cluster_updated(uint64_t request_id) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_CLUSTER_UPDATED;
    e.status = PHOTO_STATUS_OK;
    e.request_id = request_id;
    events_->push(e);
}

}  // namespace photo::faces
