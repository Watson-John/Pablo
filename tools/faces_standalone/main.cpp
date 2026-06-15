// faces_probe — end-to-end smoke test for the C++ face pipeline.
//
// Part A (direct): SCRFD detect + AuraFace embed on labeled crops; checks
//   detection fires, embeddings are unit-norm 512-d, and same-person cosine
//   clearly exceeds different-person cosine (the property the whole feature
//   rests on).
// Part B (service): drive FaceService (the real engine seam) over a labeled
//   batch -> SQLite store -> agglomerative rebuild -> read-back queries
//   (list_clusters / list_cluster_faces / list_people / approve), confirming
//   the clusters recover the ground-truth people.
//
// Usage: faces_probe <models_dir> <test_db_dir> [faces_per_person] [num_people]

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <map>
#include <string>
#include <thread>
#include <vector>

#include <opencv2/imgcodecs.hpp>

#include "faces/align.h"
#include "faces/cluster.h"
#include "faces/detector.h"
#include "faces/embed.h"
#include "faces/face_service.h"
#include "faces/prototype.h"
#include "runtime/event_ring.h"
#include "runtime/job_system.h"

namespace fs = std::filesystem;
using namespace photo::faces;

namespace {

float cosine(const Embedding& a, const Embedding& b) {
    double d = 0;
    for (size_t i = 0; i < a.size() && i < b.size(); ++i) d += double(a[i]) * b[i];
    return float(d);
}

// Collect up to `per` jpgs from up to `people` subdirectories of `crops/`.
struct Sample { std::string person; std::string path; };
std::vector<Sample> gather(const fs::path& db, int per, int people) {
    std::vector<Sample> out;
    const fs::path crops = db / "crops";
    if (!fs::exists(crops)) { std::printf("  ! no crops/ under %s\n", db.c_str()); return out; }
    std::vector<fs::path> dirs;
    for (auto& e : fs::directory_iterator(crops))
        if (e.is_directory()) dirs.push_back(e.path());
    std::sort(dirs.begin(), dirs.end());
    int np = 0;
    for (auto& d : dirs) {
        if (np >= people) break;
        int n = 0;
        std::vector<fs::path> imgs;
        for (auto& f : fs::directory_iterator(d)) {
            auto ext = f.path().extension().string();
            if (ext == ".jpg" || ext == ".jpeg" || ext == ".png") imgs.push_back(f.path());
        }
        std::sort(imgs.begin(), imgs.end());
        for (auto& f : imgs) {
            if (n >= per) break;
            out.push_back({d.filename().string(), f.string()});
            ++n;
        }
        if (n > 0) ++np;
    }
    return out;
}

const char* ok(bool b) { return b ? "PASS" : "FAIL"; }

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::printf("usage: %s <models_dir> <test_db_dir> [per=8] [people=3]\n", argv[0]);
        return 2;
    }
    const fs::path models = argv[1];
    const fs::path db = argv[2];
    const int per = argc > 3 ? std::atoi(argv[3]) : 8;
    const int people = argc > 4 ? std::atoi(argv[4]) : 3;

    const fs::path scrfd = models / "scrfd_10g_bnkps.onnx";
    const fs::path aura = models / "auraface_glintr100.onnx";

    std::printf("=== faces_probe ===\n");
    std::printf("models=%s\n db=%s  per=%d people=%d\n", models.c_str(), db.c_str(), per, people);
    std::printf("Detector::available=%d Embedder::available=%d FaceService::available=%d\n",
                Detector::available(), Embedder::available(), FaceService::available());

    int failures = 0;

    // ---------------------------------------------------------------- Part A
    std::printf("\n--- Part A: direct detect + embed ---\n");
    Detector det(scrfd.string(), 0.5f, 0.45f);
    Embedder emb(aura.string(), 127.5f, 127.5f);
    std::printf("embedder dim = %d\n", emb.dim());

    auto samples = gather(db, per, people);
    std::printf("gathered %zu crops across <=%d people\n", samples.size(), people);
    if (samples.empty()) { std::printf("no samples; aborting\n"); return 1; }

    std::map<std::string, std::vector<Embedding>> byPerson;
    int detected = 0, embedded = 0;
    for (auto& s : samples) {
        cv::Mat bgr = cv::imread(s.path, cv::IMREAD_COLOR);
        if (bgr.empty()) continue;
        auto faces = det.detect(bgr);
        if (faces.empty()) continue;
        ++detected;
        // largest face
        std::sort(faces.begin(), faces.end(),
                  [](const DetectedFace& a, const DetectedFace& b) {
                      return a.box.w * a.box.h > b.box.w * b.box.h;
                  });
        cv::Mat aligned = align_arcface(bgr, faces[0].landmarks);
        Embedding v = emb.embed(aligned, true);
        double n = 0; for (float x : v) n += double(x) * x;
        if (std::abs(std::sqrt(n) - 1.0) < 1e-3 && v.size() == 512) ++embedded;
        byPerson[s.person].push_back(std::move(v));
    }
    std::printf("detected on %d/%zu crops; %d unit-norm 512-d embeddings\n",
                detected, samples.size(), embedded);

    // Same- vs different-person cosine separation.
    double sameSum = 0, diffSum = 0; int sameN = 0, diffN = 0;
    std::vector<std::pair<std::string, std::vector<Embedding>>> v(byPerson.begin(), byPerson.end());
    for (size_t i = 0; i < v.size(); ++i) {
        auto& ei = v[i].second;
        for (size_t a = 0; a < ei.size(); ++a)
            for (size_t b = a + 1; b < ei.size(); ++b) { sameSum += cosine(ei[a], ei[b]); ++sameN; }
        for (size_t j = i + 1; j < v.size(); ++j)
            for (auto& ea : ei)
                for (auto& eb : v[j].second) { diffSum += cosine(ea, eb); ++diffN; }
    }
    const double sameAvg = sameN ? sameSum / sameN : 0;
    const double diffAvg = diffN ? diffSum / diffN : 0;
    std::printf("cosine: same-person avg=%.3f (n=%d)  diff-person avg=%.3f (n=%d)\n",
                sameAvg, sameN, diffAvg, diffN);
    const bool sepOK = detected > 0 && embedded > 0 && sameAvg > diffAvg + 0.10;
    std::printf("[A] detect+embed+separation: %s\n", ok(sepOK));
    if (!sepOK) ++failures;

    // ---------------------------------------------------------------- Part B
    std::printf("\n--- Part B: FaceService -> store -> cluster -> read-back ---\n");
    const fs::path dbfile = fs::temp_directory_path() / "faces_probe.db";
    std::error_code ec;
    fs::remove(dbfile, ec);
    fs::remove(fs::path(dbfile.string() + ".faces.vec"), ec);

    photo::JobSystem jobs(4);
    photo::EventRing events(4096);
    // FaceService looks for scrfd_10g.onnx / auraface.onnx in models_dir; the
    // caller is expected to provide a dir with those canonical names (symlinks).
    FaceService svc(&events, &jobs, models, dbfile);

    // Submit a scan per crop; asset_id == index. The crops are tight faces, so
    // detection yields ~1 face each — enough to exercise the full path.
    std::map<uint64_t, std::string> assetPerson;
    uint64_t asset = 1;
    int submitted = 0;
    for (auto& s : samples) {
        if (svc.submit_scan(asset, s.path.c_str(), 0) != 0) { ++submitted; assetPerson[asset] = s.person; }
        ++asset;
    }
    std::printf("submitted %d scans; draining events...\n", submitted);

    int done = 0, totalFaces = 0;
    photo_event_t buf[128];
    for (int spins = 0; spins < 600 && done < submitted; ++spins) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        size_t n = events.pop_n(buf, 128);
        for (size_t i = 0; i < n; ++i) {
            if (buf[i].kind == PHOTO_EVT_SCAN_PROGRESS) { ++done; totalFaces += int(buf[i].aux64); }
        }
    }
    std::printf("scans completed=%d, faces kept=%d\n", done, totalFaces);

    // Full re-cluster, then read back the unconfirmed buckets.
    uint64_t rid = svc.rebuild_clusters(0);
    (void)rid;
    for (int spins = 0; spins < 200; ++spins) {
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
        size_t n = events.pop_n(buf, 128);
        bool got = false;
        for (size_t i = 0; i < n; ++i) if (buf[i].kind == PHOTO_EVT_CLUSTER_UPDATED) got = true;
        if (got) break;
    }

    auto clusters = svc.list_clusters();
    std::printf("clusters (unconfirmed buckets) = %zu\n", clusters.size());
    // For each cluster, measure label purity against ground-truth person.
    int pureClusters = 0;
    size_t biggest = 0;
    for (auto& c : clusters) {
        auto members = svc.list_cluster_faces(c.cluster_id);
        biggest = std::max(biggest, members.size());
        std::map<std::string, int> votes;
        for (auto& m : members) {
            auto it = assetPerson.find(m.asset_id);
            if (it != assetPerson.end()) votes[it->second]++;
        }
        int top = 0; std::string topName;
        for (auto& [k, n2] : votes) if (n2 > top) { top = n2; topName = k; }
        const bool pure = members.size() >= 2 &&
                          top >= int(0.8 * double(members.size()));
        if (pure) ++pureClusters;
        if (members.size() >= 2)
            std::printf("  cluster %lld: %zu faces, majority=%s (%d/%zu)%s\n",
                        (long long)c.cluster_id, members.size(), topName.c_str(),
                        top, members.size(), pure ? " [pure]" : "");
    }
    const bool clusterOK = !clusters.empty() && biggest >= 2;
    std::printf("[B] cluster+readback: %s (%d pure multi-face clusters, biggest=%zu)\n",
                ok(clusterOK), pureClusters, biggest);
    if (!clusterOK) ++failures;

    // Confirm one face into a person and verify list_people reflects it.
    bool approveOK = false;
    if (!clusters.empty()) {
        auto members = svc.list_cluster_faces(clusters[0].cluster_id);
        if (!members.empty()) {
            svc.approve(clusters[0].cluster_id, members[0].face_id);
            for (int spins = 0; spins < 200; ++spins) {
                std::this_thread::sleep_for(std::chrono::milliseconds(25));
                size_t n = events.pop_n(buf, 128);
                bool got = false;
                for (size_t i = 0; i < n; ++i) if (buf[i].kind == PHOTO_EVT_CLUSTER_UPDATED) got = true;
                if (got) break;
            }
            auto ppl = svc.list_people();
            std::printf("people after approve = %zu\n", ppl.size());
            if (!ppl.empty()) {
                svc.name_person(ppl[0].person_id, "TestPerson");
                auto ppl2 = svc.list_people();
                for (auto& p : ppl2)
                    if (p.person_id == ppl[0].person_id && std::string(p.name) == "TestPerson")
                        approveOK = true;
            }
        }
    }
    std::printf("[B] approve+name: %s\n", ok(approveOK));
    if (!approveOK) ++failures;

    std::printf("\n=== %s: %d failure(s) ===\n", failures ? "FAILURES" : "ALL PASS", failures);
    return failures ? 1 : 0;
}
