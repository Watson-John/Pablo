// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/face_service.h"

#include <algorithm>
#include <cstring>
#include <utility>

#include "faces/align.h"
#include "faces/cluster.h"
#include "faces/detector.h"
#include "faces/embed.h"
#include "faces/prototype.h"
#include "faces/store.h"
#include "util/log.h"

#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
#include "codec/codec.h"  // codec::decode_bgr — full-res decode (all formats)
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
// Legacy fallbacks for a store opened with NO resolved profile (read-back
// without model files): match the pre-registry AuraFace layout.
constexpr float kFallbackMergeDistance = 0.45f;
constexpr int   kFallbackEmbedDim = 512;

photo_face_t to_face_pod(const FaceRecord& r) {
    photo_face_t f{};
    f.face_id = static_cast<uint64_t>(r.id);
    f.asset_id = static_cast<uint64_t>(r.asset_id);
    f.cluster_id = r.cluster_id;
    f.person_id = r.person_id;
    f.box_x = r.box.x; f.box_y = r.box.y; f.box_w = r.box.w; f.box_h = r.box.h;
    f.det_score = r.det_score;
    f.quality = r.quality;
    f.confirmed = r.confirmed ? 1 : 0;
    f.ignored = r.ignored ? 1 : 0;
    f.manual = r.manual ? 1 : 0;
    return f;
}

void set_pod_name(photo_person_t& p, const std::string& s) {
    std::strncpy(p.name, s.c_str(), sizeof(p.name) - 1);
    p.name[sizeof(p.name) - 1] = '\0';
}
}  // namespace

FaceService::FaceService(EventRing* events, JobSystem* jobs,
                         std::filesystem::path models_dir,
                         std::filesystem::path catalog_path)
    : events_(events), jobs_(jobs),
      models_dir_(std::move(models_dir)), catalog_path_(std::move(catalog_path)) {}

FaceService::~FaceService() = default;

std::string FaceService::active_model_id() {
    if (!ensure_store() || !store_) return {};
    return profile_ ? profile_->model_id : kDefaultFaceModelId;
}

int64_t FaceService::stale_face_count() {
    if (!ensure_store() || !store_) return 0;
    std::lock_guard lk(store_mu_);
    return store_->count_stale();
}

int64_t FaceService::prune_stale_faces() {
    if (!ensure_store() || !store_) return 0;
    std::lock_guard lk(store_mu_);
    return store_->prune_stale_unconfirmed();
}

bool FaceService::available() {
#ifdef FACES_HAVE_ORT
    return true;
#else
    return false;
#endif
}

// ── FacePipeline: the swappable detect+embed stack ──────────────────────────
// Interface so a future stack (different detector, quantized embedder, a
// plugin) drops in behind the same two calls; OnnxFacePipeline is the ORT
// implementation driven entirely by a FaceModelProfile.
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
class FacePipeline {
public:
    virtual ~FacePipeline() = default;
    FacePipeline(const FacePipeline&) = delete;
    FacePipeline& operator=(const FacePipeline&) = delete;

    virtual const FaceModelProfile& profile() const = 0;
    virtual std::vector<DetectedFace> detect(const cv::Mat& bgr) = 0;
    // Embed one aligned 112x112 BGR crop (L2-normalized; applies profile tta).
    virtual Embedding embed(const cv::Mat& aligned_112) = 0;

protected:
    FacePipeline() = default;
};

namespace {
class OnnxFacePipeline final : public FacePipeline {
public:
    OnnxFacePipeline(const FaceModelProfile& p, const std::filesystem::path& dir)
        : profile_(p),
          detector_((dir / p.detector_file).string(), p.det_score_threshold,
                    p.det_nms_threshold),
          embedder_((dir / p.embedder_file).string(), p.embed_mean,
                    p.embed_scale) {}

    const FaceModelProfile& profile() const override { return profile_; }
    std::vector<DetectedFace> detect(const cv::Mat& bgr) override {
        return detector_.detect(bgr);
    }
    Embedding embed(const cv::Mat& aligned_112) override {
        return embedder_.embed(aligned_112, profile_.tta);
    }

private:
    const FaceModelProfile& profile_;
    Detector detector_;
    Embedder embedder_;
};
}  // namespace
#else
class FacePipeline {
public:
    virtual ~FacePipeline() = default;
};
#endif

bool FaceService::ensure_store() {
    std::call_once(store_once_, [this] {
#ifdef FACES_HAVE_SQLITE
        try {
            // Resolve the active profile by model-file probe (model_registry.h).
            // No files → legacy layout so read-back of existing data still works.
            profile_ = resolve_face_profile(models_dir_);
            const int dim = profile_ ? profile_->embed_dim : kFallbackEmbedDim;
            const std::string suffix =
                profile_ ? vectors_suffix_for(*profile_) : ".faces.vec";
            store_ = std::make_unique<FaceStore>(catalog_path_.string(), dim, suffix);
            store_->set_active_model(
                profile_ ? profile_->model_id : kDefaultFaceModelId,
                profile_ ? profile_->model_version : "1");
            prototypes_ = std::make_unique<PrototypeIndex>();
            prototypes_->rebuild(store_->confirmed_by_person());
            store_ok_ = true;
        } catch (const std::exception& e) {
            PHOTO_LOGF(PHOTO_LOG_ERROR, "faces: store open failed: %s", e.what());
            store_ok_ = false;
        }
#else
        PHOTO_LOGF(PHOTO_LOG_WARN, "faces: built without SQLite persistence");
        store_ok_ = false;
#endif
    });
    return store_ok_;
}

bool FaceService::ensure_models() {
    // The store is a prerequisite for the models (online-assign folds into it).
    if (!ensure_store()) return false;
    std::call_once(models_once_, [this] {
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
        try {
            if (!profile_) {
                PHOTO_LOGF(PHOTO_LOG_WARN,
                           "faces: no model profile resolved in %s",
                           models_dir_.string().c_str());
                models_ok_ = false;
                return;
            }
            pipeline_ = std::make_unique<OnnxFacePipeline>(*profile_, models_dir_);
            models_ok_ = true;
            PHOTO_LOGF(PHOTO_LOG_INFO, "faces: model profile loaded (%s v%s)",
                       profile_->model_id, profile_->model_version);
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

uint64_t FaceService::submit_face_job(int lane, std::function<void(uint64_t)> fn) {
    const uint64_t request_id = next_request_id_.fetch_add(1, std::memory_order_relaxed);
    auto handle = jobs_->submit(lane, [this, request_id, fn = std::move(fn)]() mutable {
        fn(request_id);
        std::lock_guard lk(req_mu_);
        request_to_job_.erase(request_id);
    });
    {
        std::lock_guard lk(req_mu_);
        request_to_job_.emplace(request_id, handle.id);
    }
    return request_id;
}

void FaceService::confirm_face_locked(const FaceRecord& f, int64_t person) {
    store_->set_person(f.id, person);
    store_->set_cluster(f.id, person);
    store_->set_confirmed(f.id, true);
    // Fold into the prototype only for an ACTIVE-profile vector: a stale row's
    // vec_row indexes another profile's file (wrong matrix, maybe wrong dim);
    // manual rects (vec_row<0) have no vector at all.
    if (f.vec_row >= 0 && store_->matches_active(f.model_id))
        prototypes_->add_confirmed(person, store_->vectors().row(f.vec_row));
}

uint64_t FaceService::submit_scan(uint64_t asset_id, const char* path_utf8,
                                  uint32_t flags) {
    (void)flags;  // reserved (e.g. force-rescan); the pipeline runs on the idle lane.
    std::string path = path_utf8 ? std::string(path_utf8) : std::string{};
    return submit_face_job(kFaceLane,
        [this, asset_id, p = std::move(path)](uint64_t request_id) mutable {
            run_scan(request_id, asset_id, std::move(p));
        });
}

uint64_t FaceService::rebuild_clusters(uint32_t /*flags*/) {
    return submit_face_job(kFaceLane + 1,  // lowest priority
        [this](uint64_t request_id) { run_rebuild(request_id); });
}

uint64_t FaceService::approve(uint64_t /*cluster_id*/, uint64_t embedding_id) {
    // Confirm a face's membership: fold its embedding into the person prototype
    // and persist the person link. NOTE: cluster_id is currently IGNORED — the
    // face is confirmed into its own stored person_id (1:1 person<->cluster
    // scaffold), creating a person if it had none.
    return submit_face_job(kFaceLane, [this, embedding_id](uint64_t request_id) {
        if (ensure_models() && store_ && prototypes_) {
            std::lock_guard lk(store_mu_);
            if (auto f = store_->face_by_id(static_cast<int64_t>(embedding_id))) {
                int64_t person = f->person_id;
                if (person < 0) person = store_->create_person();
                confirm_face_locked(*f, person);
            }
        }
        emit_cluster_updated(request_id);
    });
}

uint64_t FaceService::reject(uint64_t /*cluster_id*/, uint64_t embedding_id) {
    // NOTE: cluster_id is currently IGNORED — reject clears the face's own
    // person link (mirrors approve's scaffold semantics).
    return submit_face_job(kFaceLane, [this, embedding_id](uint64_t request_id) {
        if (ensure_models() && store_ && prototypes_) {
            std::lock_guard lk(store_mu_);
            if (auto f = store_->face_by_id(static_cast<int64_t>(embedding_id))) {
                if (f->person_id >= 0 && f->confirmed) {
                    const Embedding v = store_->vectors().row(f->vec_row);
                    prototypes_->remove(f->person_id, v);
                }
                store_->set_person(f->id, -1);
                store_->set_confirmed(f->id, false);
            }
        }
        emit_cluster_updated(request_id);
    });
}

uint64_t FaceService::name_cluster(int64_t cluster_id, const std::string& name) {
    return submit_face_job(kFaceLane, [this, cluster_id, name](uint64_t request_id) {
        if (ensure_models() && store_ && prototypes_ && !name.empty()) {
            std::lock_guard lk(store_mu_);
            // Merge into an existing person of the same name, else create one.
            const int64_t person = store_->find_or_create_person(name);
            // Confirm every face in the cluster into that person.
            for (const auto& f : store_->faces_for_cluster(cluster_id)) {
                confirm_face_locked(f, person);
            }
        }
        emit_cluster_updated(request_id);
    });
}

void FaceService::run_scan(uint64_t request_id, uint64_t asset_id, std::string path) {
#if defined(PHOTO_HAVE_FACES) && defined(FACES_HAVE_ORT)
    if (!ensure_models() || !models_ok_) {
        emit_scan_progress(request_id, asset_id, PHOTO_STATUS_UNSUPPORTED, 0);
        return;
    }
    // Idempotent: a re-scan of an already-processed asset is a no-op.
    {
        std::lock_guard lk(store_mu_);
        if (store_->asset_scanned(static_cast<int64_t>(asset_id))) {
            emit_scan_progress(request_id, asset_id, PHOTO_STATUS_OK, 0);
            return;
        }
    }
    // Decode through the shared codec (libvips when available) so RAW/HEIC/JXL/
    // TIFF scan like JPEGs; falls back to cv::imread. Full resolution, so the
    // detected boxes stay in source-image pixels.
    cv::Mat bgr = codec::decode_bgr(path);
    if (bgr.empty()) {
        emit_scan_progress(request_id, asset_id, PHOTO_STATUS_IO_ERROR, 0);
        return;
    }

    std::vector<DetectedFace> faces = pipeline_->detect(bgr);
    uint32_t kept = 0;
    for (const auto& df : faces) {
        if (std::min(df.box.w, df.box.h) < kMinFacePx) continue;  // size gate
        cv::Mat aligned = align_arcface(bgr, df.landmarks);
        const float q = face_quality(aligned);
        if (q < kMinSharpness) continue;                          // blur gate

        Embedding vec = pipeline_->embed(aligned);  // slow; no lock

        FaceRecord rec;
        rec.asset_id = static_cast<int64_t>(asset_id);
        rec.box = df.box;
        rec.landmarks = df.landmarks;
        rec.det_score = df.score;
        rec.quality = q;
        {
            std::lock_guard lk(store_mu_);
            store_->insert_face(rec, vec.data());
            // Online assignment: nearest confirmed prototype within threshold.
            auto match = prototypes_->nearest(vec);
            const float merge = profile_ ? profile_->merge_distance
                                         : kFallbackMergeDistance;
            if (match.person_id >= 0 && (1.0f - match.similarity) <= merge) {
                store_->set_cluster(rec.id, match.person_id);
                store_->set_person(rec.id, match.person_id);  // suggestion (unconfirmed)
            }
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
    std::lock_guard lk(store_mu_);
    std::vector<FaceRecord> faces = store_->all_faces();
    if (faces.empty()) { emit_cluster_updated(request_id); return; }

    std::vector<Embedding> embs;
    embs.reserve(faces.size());
    for (const auto& f : faces) embs.push_back(store_->vectors().row(f.vec_row));

    ClusterParams params;
    params.merge_distance =
        profile_ ? profile_->merge_distance : kFallbackMergeDistance;
    std::vector<int64_t> labels = cluster_agglomerative(embs, params);
    // Preserve confirmed faces' person-cluster binding; only relabel unconfirmed.
    for (size_t i = 0; i < faces.size(); ++i)
        if (!faces[i].confirmed) store_->set_cluster(faces[i].id, labels[i]);
    emit_cluster_updated(request_id);
#else
    emit_cluster_updated(request_id);
#endif
}

// --------------------------------------------------------------- read-back

std::vector<photo_person_t> FaceService::list_people() {
    std::vector<photo_person_t> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& person : store_->all_people()) {
        const auto faces = store_->faces_for_person(person.id, /*only_suggestions=*/false);
        int32_t confirmed = 0;
        for (const auto& f : faces) if (f.confirmed) ++confirmed;
        photo_person_t p{};
        p.person_id = static_cast<uint64_t>(person.id);
        p.cluster_id = person.id;  // 1:1 person<->cluster until split/merge UI
        p.cover_face_id =
            static_cast<uint64_t>(std::max<int64_t>(0, store_->cover_face_for_person(person.id)));
        p.face_count = static_cast<int32_t>(faces.size());
        p.confirmed_count = confirmed;
        p.confirmed = confirmed > 0 ? 1 : 0;
        set_pod_name(p, person.name);
        out.push_back(p);
    }
    return out;
}

std::vector<photo_person_t> FaceService::list_clusters() {
    std::vector<photo_person_t> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& c : store_->unconfirmed_clusters()) {
        photo_person_t p{};
        p.person_id = 0;             // unnamed bucket
        p.cluster_id = c.cluster_id;
        p.cover_face_id = static_cast<uint64_t>(std::max<int64_t>(0, c.cover_face_id));
        p.face_count = c.count;
        out.push_back(p);            // name left empty
    }
    return out;
}

std::vector<photo_face_t> FaceService::list_cluster_faces(int64_t cluster_id) {
    std::vector<photo_face_t> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& r : store_->faces_for_cluster(cluster_id)) out.push_back(to_face_pod(r));
    return out;
}

std::vector<photo_face_t> FaceService::list_suggestions(uint64_t person_id) {
    std::vector<photo_face_t> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& r :
         store_->faces_for_person(static_cast<int64_t>(person_id), /*only_suggestions=*/true))
        out.push_back(to_face_pod(r));
    return out;
}

std::vector<photo_face_t> FaceService::list_for_asset(uint64_t asset_id) {
    std::vector<photo_face_t> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& r : store_->faces_for_asset(static_cast<int64_t>(asset_id)))
        out.push_back(to_face_pod(r));
    return out;
}

std::vector<std::array<float, 4>> FaceService::eye_landmarks_for_asset(
    uint64_t asset_id) {
    std::vector<std::array<float, 4>> out;
    if (!ensure_models() || !store_) return out;
    std::lock_guard lk(store_mu_);
    for (const auto& r : store_->faces_for_asset(static_cast<int64_t>(asset_id))) {
        // landmarks are [leftEyeX, leftEyeY, rightEyeX, rightEyeY, nose, mouth…].
        out.push_back({r.landmarks[0], r.landmarks[1], r.landmarks[2], r.landmarks[3]});
    }
    return out;
}

bool FaceService::name_person(uint64_t person_id, const std::string& name) {
    if (!ensure_store() || !store_) return false;
    std::lock_guard lk(store_mu_);
    store_->rename_person(static_cast<int64_t>(person_id), name);
    return true;
}

// ------------------------------------------------------ face editing (no ML)

bool FaceService::set_ignored(uint64_t face_id, bool ignored) {
    if (!ensure_store() || !store_) return false;
    std::lock_guard lk(store_mu_);
    const auto f = store_->face_by_id(static_cast<int64_t>(face_id));
    if (!f) return false;
    // If we're hiding a confirmed face, pull its embedding out of the person
    // prototype so recognition stops matching it (mirrors reject()).
    if (ignored && f->confirmed && f->person_id >= 0 && f->vec_row >= 0 && prototypes_) {
        prototypes_->remove(f->person_id, store_->vectors().row(f->vec_row));
    }
    store_->set_ignored(f->id, ignored);
    return true;
}

uint64_t FaceService::add_manual_face(uint64_t asset_id, float x, float y,
                                      float w, float h) {
    if (!ensure_store() || !store_) return 0;
    if (w <= 0 || h <= 0) return 0;
    std::lock_guard lk(store_mu_);
    FaceRecord rec;
    rec.asset_id = static_cast<int64_t>(asset_id);
    rec.box = {x, y, w, h};
    rec.det_score = 1.0f;   // user-asserted
    rec.quality = 1.0f;     // sort manual rects to the front of a person's faces
    const int64_t id = store_->insert_manual_face(rec);
    return id > 0 ? static_cast<uint64_t>(id) : 0;
}

bool FaceService::assign_face(uint64_t face_id, const std::string& name) {
    if (!ensure_store() || !store_ || !prototypes_ || name.empty()) return false;
    std::lock_guard lk(store_mu_);
    const auto f = store_->face_by_id(static_cast<int64_t>(face_id));
    if (!f) return false;
    const int64_t person = store_->find_or_create_person(name);
    store_->set_person(f->id, person);
    store_->set_cluster(f->id, person);
    store_->set_confirmed(f->id, true);
    // Fold a real embedding into the prototype; manual rects (vec_row<0) and
    // stale-profile rows (vector in another file) can't.
    if (f->vec_row >= 0 && store_->matches_active(f->model_id))
        prototypes_->add_confirmed(person, store_->vectors().row(f->vec_row));
    return true;
}

bool FaceService::remove_face(uint64_t face_id) {
    if (!ensure_store() || !store_) return false;
    std::lock_guard lk(store_mu_);
    const auto f = store_->face_by_id(static_cast<int64_t>(face_id));
    if (!f) return false;
    if (f->confirmed && f->person_id >= 0 && f->vec_row >= 0 && prototypes_)
        prototypes_->remove(f->person_id, store_->vectors().row(f->vec_row));
    store_->remove_face(f->id);
    return true;
}

std::vector<FaceService::NamedRegion>
FaceService::named_regions_for_asset(uint64_t asset_id) {
    std::vector<NamedRegion> out;
    if (!ensure_store() || !store_) return out;
    std::lock_guard lk(store_mu_);
    // Resolve person_id -> name once.
    std::unordered_map<int64_t, std::string> names;
    for (const auto& p : store_->all_people()) names[p.id] = p.name;
    for (const auto& f : store_->faces_for_asset(static_cast<int64_t>(asset_id))) {
        if (f.ignored || f.person_id < 0) continue;
        auto it = names.find(f.person_id);
        if (it == names.end() || it->second.empty()) continue;  // only NAMED faces
        out.push_back({it->second, f.box.x, f.box.y, f.box.w, f.box.h});
    }
    return out;
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
