// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// face_pipeline_test.cpp — unit regression tests for the pure-C++ pieces of the
// face pipeline: agglomerative clustering (cluster.h), the per-person prototype
// index (prototype.h), and — when OpenCV is in the build — the 5-point ArcFace
// alignment warp (align.h). The clustering/prototype code is plain std::vector
// math (no OpenCV/ONNX); the align section is gated on PHOTO_HAVE_FACES because
// it needs cv::Mat. Complements the frozen eval/ harness with fast synthetic
// pins on the algorithm contracts the eval bake-off selected.

#include <gtest/gtest.h>

#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

#include "faces/cluster.h"
#include "faces/prototype.h"
#include "faces/types.h"

using photo::faces::assign_nearest;
using photo::faces::cluster_agglomerative;
using photo::faces::ClusterParams;
using photo::faces::Embedding;
using photo::faces::PrototypeIndex;

namespace {

// L2-normalize a vector so it matches the "embeddings are unit vectors"
// contract both cluster.cpp and prototype.cpp rely on (dot == cosine).
Embedding na(std::vector<float> v) {
    double s = 0.0;
    for (float x : v) s += static_cast<double>(x) * x;
    const float n = static_cast<float>(std::sqrt(s));
    for (float& x : v) x /= n;
    return v;
}

// Synthetic library: two tight groups on orthogonal axes plus one outlier.
// Within-group cosine distance ≈ 0.02 (well under the 0.45 cut); cross-group
// and outlier distances ≈ 0.9-1.0 (well over it).
const Embedding kA0 = na({1.0f, 0.0f, 0.0f, 0.0f});
const Embedding kA1 = na({1.0f, 0.1f, 0.0f, 0.0f});
const Embedding kA2 = na({1.0f, -0.1f, 0.0f, 0.0f});
const Embedding kB0 = na({0.0f, 0.0f, 1.0f, 0.0f});
const Embedding kB1 = na({0.0f, 0.0f, 1.0f, 0.1f});
const Embedding kB2 = na({0.1f, 0.0f, 1.0f, 0.0f});
const Embedding kOutlier = na({0.0f, 0.0f, 0.0f, 1.0f});

}  // namespace

// ── cluster.h: cluster_agglomerative ─────────────────────────────────────────

TEST(FaceCluster, TwoGroupsPlusOutlierAtDefaultCut) {
    // Interleave the groups so labels can't come out right by input order alone.
    const std::vector<Embedding> emb = {kA0, kB0, kA1, kB1, kA2, kB2, kOutlier};
    ClusterParams params;  // merge_distance 0.45, min_cluster_size 1
    const auto labels = cluster_agglomerative(emb, params);
    ASSERT_EQ(labels.size(), emb.size());

    // Group A members share a label; group B members share a different one;
    // the outlier is a singleton with a third label (singletons kept at min=1).
    EXPECT_EQ(labels[0], labels[2]);
    EXPECT_EQ(labels[0], labels[4]);
    EXPECT_EQ(labels[1], labels[3]);
    EXPECT_EQ(labels[1], labels[5]);
    EXPECT_NE(labels[0], labels[1]);
    EXPECT_NE(labels[6], labels[0]);
    EXPECT_NE(labels[6], labels[1]);

    // Labels are contiguous from 0 and -1 never appears at min_cluster_size 1.
    for (int64_t l : labels) {
        EXPECT_GE(l, 0);
        EXPECT_LE(l, 2);
    }
}

TEST(FaceCluster, EverythingMergesAtDistanceTwo) {
    // 2.0 is the cosine-distance ceiling, so no cut is ever reached and the
    // whole library collapses into a single cluster labeled 0.
    const std::vector<Embedding> emb = {kA0, kB0, kA1, kB1, kA2, kB2, kOutlier};
    ClusterParams params;
    params.merge_distance = 2.0f;
    const auto labels = cluster_agglomerative(emb, params);
    ASSERT_EQ(labels.size(), emb.size());
    for (int64_t l : labels) EXPECT_EQ(l, 0);
}

TEST(FaceCluster, EmptyInputYieldsEmptyLabels) {
    const auto labels = cluster_agglomerative({}, ClusterParams{});
    EXPECT_TRUE(labels.empty());
}

TEST(FaceCluster, SingleFaceIsItsOwnCluster) {
    const auto labels = cluster_agglomerative({kA0}, ClusterParams{});
    ASSERT_EQ(labels.size(), 1u);
    EXPECT_EQ(labels[0], 0);
}

TEST(FaceCluster, MinClusterSizeDropsSingletonsToMinusOne) {
    // With min_cluster_size 2 the outlier's singleton cluster is suppressed
    // (-1 = UI-hidden noise) while the real pair keeps a contiguous label.
    ClusterParams params;
    params.min_cluster_size = 2;
    const auto labels = cluster_agglomerative({kA0, kA1, kOutlier}, params);
    ASSERT_EQ(labels.size(), 3u);
    EXPECT_EQ(labels[0], 0);
    EXPECT_EQ(labels[1], 0);
    EXPECT_EQ(labels[2], -1);
}

// ── cluster.h: assign_nearest (online fast path) ─────────────────────────────

TEST(FaceCluster, AssignNearestPicksPrototypeWithinThreshold) {
    const std::vector<Embedding> protos = {kA0, kB0};
    // Near group A → prototype 0; orthogonal to both (distance 1.0) → no match.
    EXPECT_EQ(assign_nearest(na({1.0f, 0.05f, 0.0f, 0.0f}), protos, 0.45f), 0);
    EXPECT_EQ(assign_nearest(na({0.0f, 0.0f, 0.95f, 0.05f}), protos, 0.45f), 1);
    EXPECT_EQ(assign_nearest(kOutlier, protos, 0.45f), -1);
}

TEST(FaceCluster, AssignNearestThresholdIsInclusive) {
    // Orthogonal vector sits at cosine distance exactly 1.0; the comparison is
    // d <= merge_distance, so the boundary counts as a match.
    const std::vector<Embedding> protos = {kA0};
    EXPECT_EQ(assign_nearest(kOutlier, protos, 1.0f), 0);
    EXPECT_EQ(assign_nearest(kOutlier, protos, 0.999f), -1);
}

TEST(FaceCluster, AssignNearestEmptyPrototypesReturnsMinusOne) {
    EXPECT_EQ(assign_nearest(kA0, {}, 0.45f), -1);
}

// ── prototype.h: PrototypeIndex ──────────────────────────────────────────────

TEST(FacePrototype, RebuildThenNearestFindsTheRightPerson) {
    std::unordered_map<int64_t, std::vector<Embedding>> confirmed;
    confirmed[10] = {kA0, kA1, kA2};   // person 10 lives on the x axis
    confirmed[20] = {kB0, kB1};        // person 20 lives on the z axis

    PrototypeIndex idx;
    idx.rebuild(confirmed);

    const auto ma = idx.nearest(na({1.0f, 0.05f, 0.0f, 0.0f}));
    EXPECT_EQ(ma.person_id, 10);
    EXPECT_GT(ma.similarity, 0.95f);

    const auto mb = idx.nearest(na({0.0f, 0.0f, 1.0f, -0.05f}));
    EXPECT_EQ(mb.person_id, 20);
    EXPECT_GT(mb.similarity, 0.95f);
}

TEST(FacePrototype, PrototypeIsTheNormalizedMean) {
    // A single confirmed vector IS the prototype, so querying with it must
    // return cosine similarity ≈ 1 (the mean is re-normalized).
    std::unordered_map<int64_t, std::vector<Embedding>> confirmed;
    confirmed[5] = {kA1};
    PrototypeIndex idx;
    idx.rebuild(confirmed);
    const auto m = idx.nearest(kA1);
    EXPECT_EQ(m.person_id, 5);
    EXPECT_NEAR(m.similarity, 1.0f, 1e-4f);
}

TEST(FacePrototype, AddConfirmedFoldsIntoRunningMean) {
    std::unordered_map<int64_t, std::vector<Embedding>> confirmed;
    confirmed[10] = {kA0, kA1};
    confirmed[20] = {kB0};
    PrototypeIndex idx;
    idx.rebuild(confirmed);

    // Folding another on-axis vector keeps person 10 the nearest for x-axis
    // queries (and must not perturb person 20).
    idx.add_confirmed(10, kA2);
    EXPECT_EQ(idx.nearest(kA0).person_id, 10);
    EXPECT_EQ(idx.nearest(kB1).person_id, 20);

    // add_confirmed for an unseen person id opens a fresh prototype.
    idx.add_confirmed(30, kOutlier);
    const auto m = idx.nearest(kOutlier);
    EXPECT_EQ(m.person_id, 30);
    EXPECT_NEAR(m.similarity, 1.0f, 1e-4f);
}

TEST(FacePrototype, EmptyIndexReportsNoPerson) {
    PrototypeIndex idx;
    const auto m = idx.nearest(kA0);
    EXPECT_LT(m.person_id, 0);
    EXPECT_FLOAT_EQ(m.similarity, 0.0f);

    // Rebuilding from an empty map keeps it empty.
    idx.rebuild({});
    EXPECT_LT(idx.nearest(kA0).person_id, 0);
    EXPECT_TRUE(idx.prototypes().empty());
    EXPECT_TRUE(idx.person_ids().empty());
}

TEST(FacePrototype, RemoveLastFaceErasesThePerson) {
    PrototypeIndex idx;
    idx.add_confirmed(7, kA0);
    ASSERT_EQ(idx.nearest(kA0).person_id, 7);

    idx.remove(7, kA0);
    EXPECT_LT(idx.nearest(kA0).person_id, 0);

    // Removing from a person that doesn't exist is a harmless no-op.
    idx.remove(999, kA0);
}

TEST(FacePrototype, ParallelArraysStayConsistent) {
    // prototypes()/person_ids() feed assign_nearest as parallel arrays: the
    // vector at index i must be person_ids()[i]'s prototype.
    std::unordered_map<int64_t, std::vector<Embedding>> confirmed;
    confirmed[10] = {kA0, kA1};
    confirmed[20] = {kB0, kB1};
    confirmed[30] = {kOutlier};
    PrototypeIndex idx;
    idx.rebuild(confirmed);

    const auto protos = idx.prototypes();
    const auto ids = idx.person_ids();
    ASSERT_EQ(protos.size(), 3u);
    ASSERT_EQ(ids.size(), 3u);
    for (size_t i = 0; i < protos.size(); ++i) {
        EXPECT_EQ(idx.nearest(protos[i]).person_id, ids[i]);
    }
}

// ── align.h: 5-point ArcFace alignment (needs OpenCV → PHOTO_HAVE_FACES) ─────

#ifdef PHOTO_HAVE_FACES

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

#include "faces/align.h"

using photo::faces::align_arcface;
using photo::faces::face_quality;
using photo::faces::kArcFaceTemplate112;
using photo::faces::Landmarks5;

namespace {

// Landmarks5 (x0,y0,…,x4,y4) from the template points, optionally translated.
Landmarks5 landmarks_at(float dx, float dy) {
    Landmarks5 lm{};
    for (int i = 0; i < 5; ++i) {
        lm[i * 2] = kArcFaceTemplate112[i].x + dx;
        lm[i * 2 + 1] = kArcFaceTemplate112[i].y + dy;
    }
    return lm;
}

// Dark canvas with a green marker disc painted at each (translated) landmark,
// so we can verify where the warp puts the landmarks in the output crop.
cv::Mat marked_canvas(int w, int h, float dx, float dy) {
    cv::Mat img(h, w, CV_8UC3, cv::Scalar(20, 20, 20));
    for (const auto& p : kArcFaceTemplate112) {
        cv::circle(img, {cvRound(p.x + dx), cvRound(p.y + dy)}, 4,
                   cv::Scalar(0, 255, 0), cv::FILLED);
    }
    return img;
}

int green_at(const cv::Mat& bgr, const cv::Point2f& p) {
    return bgr.at<cv::Vec3b>(cvRound(p.y), cvRound(p.x))[1];
}

}  // namespace

TEST(FaceAlign, TemplateLandmarksYieldIdentityCrop) {
    // Landmarks exactly on the ArcFace template → the similarity transform is
    // the identity, so the crop is 112x112 and each marker stays put.
    const cv::Mat img = marked_canvas(160, 160, 0.0f, 0.0f);
    const cv::Mat out = align_arcface(img, landmarks_at(0.0f, 0.0f));

    ASSERT_EQ(out.cols, 112);
    ASSERT_EQ(out.rows, 112);
    ASSERT_EQ(out.type(), CV_8UC3);

    for (const auto& p : kArcFaceTemplate112) {
        EXPECT_GT(green_at(out, p), 200) << "landmark (" << p.x << "," << p.y
                                         << ") lost its marker";
    }
    // Off-landmark pixels stay background — the crop isn't trivially green.
    EXPECT_LT(green_at(out, {56.0f, 51.5f}), 100);  // between the eyes
    EXPECT_LT(green_at(out, {5.0f, 5.0f}), 100);
}

TEST(FaceAlign, TranslatedFaceLandsOnTemplate) {
    // Same face shifted by a sub-pixel translation elsewhere in a bigger image:
    // the warp must bring every landmark marker back to its template position.
    const float dx = 91.5f, dy = 60.25f;
    const cv::Mat img = marked_canvas(300, 300, dx, dy);
    const cv::Mat out = align_arcface(img, landmarks_at(dx, dy));

    ASSERT_EQ(out.cols, 112);
    ASSERT_EQ(out.rows, 112);
    for (const auto& p : kArcFaceTemplate112) {
        EXPECT_GT(green_at(out, p), 200) << "landmark (" << p.x << "," << p.y
                                         << ") did not land on the template";
    }
    EXPECT_LT(green_at(out, {56.0f, 51.5f}), 100);
}

TEST(FaceAlign, DegenerateLandmarksStillProduce112Crop) {
    // All five landmarks collapsed to one point can't define a similarity
    // transform; the fallback path must still hand the embedder a 112x112 Mat.
    cv::Mat img(64, 96, CV_8UC3, cv::Scalar(20, 20, 20));
    Landmarks5 lm{};
    for (int i = 0; i < 5; ++i) { lm[i * 2] = 48.0f; lm[i * 2 + 1] = 32.0f; }
    const cv::Mat out = align_arcface(img, lm);
    EXPECT_EQ(out.cols, 112);
    EXPECT_EQ(out.rows, 112);
}

TEST(FaceAlign, FaceQualityRanksSharpAboveFlat) {
    // Variance-of-Laplacian sharpness: a flat crop scores ~0, a checkerboard
    // scores far higher — the ordering the blurry-face gate depends on.
    const cv::Mat flat(112, 112, CV_8UC3, cv::Scalar(128, 128, 128));
    cv::Mat sharp(112, 112, CV_8UC3);
    for (int y = 0; y < sharp.rows; ++y)
        for (int x = 0; x < sharp.cols; ++x)
            sharp.at<cv::Vec3b>(y, x) =
                ((x + y) % 2 == 0) ? cv::Vec3b(255, 255, 255) : cv::Vec3b(0, 0, 0);

    const float q_flat = face_quality(flat);
    const float q_sharp = face_quality(sharp);
    EXPECT_NEAR(q_flat, 0.0f, 1e-3f);
    EXPECT_GT(q_sharp, q_flat + 100.0f);
}

#endif  // PHOTO_HAVE_FACES
