// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// face_store_test.cpp — the face persistence store: ignore, manual rectangles,
// and their effect on the people/cluster read-back. Needs only SQLite (no
// OpenCV/ONNX), so it runs in the lean faces-OFF build.

#include <gtest/gtest.h>

#ifdef FACES_HAVE_SQLITE

#include <filesystem>
#include <vector>

#include "faces/store.h"

namespace fs = std::filesystem;
using photo::faces::FaceRecord;
using photo::faces::FaceStore;

namespace {
constexpr int kDim = 512;

std::string fresh_db(const char* tag) {
    auto dir = fs::temp_directory_path() / ("photo_facestore_test_" + std::string(tag));
    fs::remove_all(dir);
    fs::create_directories(dir);
    return (dir / "pablo.db").string();
}

// Insert a detector-style face with a throwaway embedding; returns its id.
int64_t add_detected(FaceStore& s, int64_t asset, float quality = 0.5f) {
    std::vector<float> vec(kDim, 0.01f);
    FaceRecord r;
    r.asset_id = asset;
    r.box = {10, 10, 100, 100};
    r.det_score = 0.9f;
    r.quality = quality;
    s.insert_face(r, vec.data());
    return r.id;
}
}  // namespace

TEST(FaceStore, ManualRectStoredWithoutEmbedding) {
    FaceStore s(fresh_db("manual"), kDim);
    FaceRecord r;
    r.asset_id = 77;
    r.box = {5, 6, 50, 60};
    const int64_t id = s.insert_manual_face(r);
    ASSERT_GT(id, 0);

    auto got = s.face_by_id(id);
    ASSERT_TRUE(got.has_value());
    EXPECT_TRUE(got->manual);
    EXPECT_FALSE(got->ignored);
    EXPECT_EQ(got->vec_row, -1);       // no embedding
    EXPECT_FLOAT_EQ(got->box.w, 50);
    EXPECT_FLOAT_EQ(got->box.h, 60);

    // Manual faces are listed for their asset.
    auto faces = s.faces_for_asset(77);
    ASSERT_EQ(faces.size(), 1u);
    EXPECT_TRUE(faces[0].manual);

    // A manual face has no embedding, so it never enters a re-cluster set.
    EXPECT_TRUE(s.all_faces().empty());
}

TEST(FaceStore, IgnoreDetachesFromPeopleButKeepsAssetRow) {
    FaceStore s(fresh_db("ignore"), kDim);
    const int64_t a = add_detected(s, 1, 0.8f);
    const int64_t b = add_detected(s, 1, 0.6f);

    // Both faces belong to person 100, one confirmed.
    const int64_t person = s.create_person();
    s.rename_person(person, "Marie Curie");
    for (int64_t id : {a, b}) {
        s.set_person(id, person);
        s.set_cluster(id, person);
    }
    s.set_confirmed(a, true);

    EXPECT_EQ(s.faces_for_person(person, /*only_suggestions=*/false).size(), 2u);
    EXPECT_EQ(s.faces_for_cluster(person).size(), 2u);
    EXPECT_EQ(s.all_faces().size(), 2u);

    // Ignore face b — it leaves people, clusters, and the re-cluster set…
    s.set_ignored(b, true);
    EXPECT_EQ(s.faces_for_person(person, false).size(), 1u);
    EXPECT_EQ(s.faces_for_cluster(person).size(), 1u);
    EXPECT_EQ(s.all_faces().size(), 1u);
    EXPECT_EQ(s.cover_face_for_person(person), a);

    // …but is still present on its asset, flagged ignored + detached.
    auto faces = s.faces_for_asset(1);
    ASSERT_EQ(faces.size(), 2u);
    for (const auto& f : faces) {
        if (f.id == b) {
            EXPECT_TRUE(f.ignored);
            EXPECT_EQ(f.person_id, -1);
            EXPECT_EQ(f.cluster_id, -1);
            EXPECT_FALSE(f.confirmed);
        }
    }

    // Un-ignore restores the row (unassigned; a re-cluster would re-place it).
    s.set_ignored(b, false);
    auto again = s.face_by_id(b);
    ASSERT_TRUE(again.has_value());
    EXPECT_FALSE(again->ignored);
    EXPECT_EQ(s.all_faces().size(), 2u);
}

TEST(FaceStore, UnconfirmedClustersExcludeIgnored) {
    FaceStore s(fresh_db("clusters"), kDim);
    const int64_t a = add_detected(s, 1, 0.9f);
    const int64_t b = add_detected(s, 2, 0.7f);
    s.set_cluster(a, 500);
    s.set_cluster(b, 500);

    auto before = s.unconfirmed_clusters();
    ASSERT_EQ(before.size(), 1u);
    EXPECT_EQ(before[0].cluster_id, 500);
    EXPECT_EQ(before[0].count, 2);
    EXPECT_EQ(before[0].cover_face_id, a);  // highest quality

    s.set_ignored(a, true);
    auto after = s.unconfirmed_clusters();
    ASSERT_EQ(after.size(), 1u);
    EXPECT_EQ(after[0].count, 1);
    EXPECT_EQ(after[0].cover_face_id, b);   // a is gone
}

TEST(FaceStore, RemoveFaceHardDeletes) {
    FaceStore s(fresh_db("remove"), kDim);
    FaceRecord r;
    r.asset_id = 9;
    r.box = {0, 0, 30, 30};
    const int64_t id = s.insert_manual_face(r);
    ASSERT_TRUE(s.face_by_id(id).has_value());

    s.remove_face(id);
    EXPECT_FALSE(s.face_by_id(id).has_value());
    EXPECT_TRUE(s.faces_for_asset(9).empty());
}

TEST(FaceStore, SchemaMigratesOldDbAddingColumns) {
    // Open, close, reopen — the idempotent ALTER path must not throw and must
    // preserve rows across the re-open.
    const std::string db = fresh_db("migrate");
    int64_t id = 0;
    {
        FaceStore s(db, kDim);
        FaceRecord r;
        r.asset_id = 3;
        r.box = {1, 2, 3, 4};
        id = s.insert_manual_face(r);
    }
    {
        FaceStore s(db, kDim);  // reopen — add_column_if_missing is a no-op now
        auto got = s.face_by_id(id);
        ASSERT_TRUE(got.has_value());
        EXPECT_TRUE(got->manual);
    }
}

#endif  // FACES_HAVE_SQLITE
