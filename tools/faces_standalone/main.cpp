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
// Usage (reproducible from the repo root after building):
//   faces_probe <models_dir> <test_db_dir> [faces_per_person] [num_people]
//   faces_probe fullres <models_dir> <faces.tsv> [maxImages]
// e.g. faces_probe native/models .testdata/full_db 15 8
// Models are the canonical vendored names (native/models/{scrfd_10g,auraface}.onnx).

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

#include <sys/types.h>  // ssize_t (getline)

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

float iou(const Box& a, const Box& b) {
    const float x1 = std::max(a.x, b.x), y1 = std::max(a.y, b.y);
    const float x2 = std::min(a.x + a.w, b.x + b.w), y2 = std::min(a.y + a.h, b.y + b.h);
    const float iw = std::max(0.0f, x2 - x1), ih = std::max(0.0f, y2 - y1);
    const float inter = iw * ih, uni = a.w * a.h + b.w * b.h - inter;
    return uni > 0 ? inter / uni : 0.0f;
}

struct GtFace { std::string person; Box box; };

// Parse a ground-truth TSV (image \t person \t x1 \t y1 \t x2 \t y2), grouping
// faces by image and preserving first-seen image order. Returns false on open.
bool parseGtTsv(const fs::path& tsv, std::vector<std::string>& order,
                std::map<std::string, std::vector<GtFace>>& byImage) {
    FILE* f = std::fopen(tsv.string().c_str(), "r");
    if (!f) return false;
    char* line = nullptr; size_t cap = 0; ssize_t len;
    while ((len = getline(&line, &cap, f)) != -1) {
        std::string s(line, len > 0 && line[len - 1] == '\n' ? len - 1 : len);
        std::vector<std::string> col; size_t p = 0;
        while (true) { size_t t = s.find('\t', p); col.push_back(s.substr(p, t - p));
                       if (t == std::string::npos) break; p = t + 1; }
        if (col.size() < 6) continue;
        const float x1 = std::atof(col[2].c_str()), y1 = std::atof(col[3].c_str());
        const float x2 = std::atof(col[4].c_str()), y2 = std::atof(col[5].c_str());
        if (byImage.find(col[0]) == byImage.end()) order.push_back(col[0]);
        byImage[col[0]].push_back({col[1], Box{x1, y1, x2 - x1, y2 - y1}});
    }
    std::free(line); std::fclose(f);
    return true;
}

// Snapshot mode: transcode the first `maxImages` source images referenced by
// `inTsv` to full-resolution JPEG (detection-lossless, ~15x smaller than the
// TIFFs, dimensions unchanged so the boxes stay valid) into `outDir`, and write
// a parallel `outTsv` pointing at the local copies. Run once with the drive
// mounted; afterwards full-res validation needs only the local snapshot.
int run_snapshot(const fs::path& inTsv, const fs::path& outDir, const fs::path& outTsv,
                 int maxImages, int quality) {
    std::vector<std::string> order;
    std::map<std::string, std::vector<GtFace>> byImage;
    if (!parseGtTsv(inTsv, order, byImage)) { std::printf("cannot open %s\n", inTsv.c_str()); return 2; }
    std::error_code ec; fs::create_directories(outDir, ec);
    FILE* out = std::fopen(outTsv.string().c_str(), "w");
    if (!out) { std::printf("cannot write %s\n", outTsv.c_str()); return 2; }
    std::printf("=== faces_probe : SNAPSHOT ===\n in=%s\n out=%s (q%d)\n maxImages=%d\n",
                inTsv.c_str(), outDir.c_str(), quality, maxImages);
    int idx = 0, written = 0; size_t bytes = 0;
    const std::vector<int> params = {cv::IMWRITE_JPEG_QUALITY, quality};
    for (const auto& img : order) {
        if (idx >= maxImages) break;
        ++idx;
        cv::Mat bgr = cv::imread(img, cv::IMREAD_COLOR);
        if (bgr.empty()) { std::printf("  [unreadable] %s\n", img.c_str()); continue; }
        char name[32]; std::snprintf(name, sizeof(name), "img_%05d.jpg", idx);
        const fs::path dst = outDir / name;
        if (!cv::imwrite(dst.string(), bgr, params)) {
            std::printf("  [imwrite failed] %s\n", dst.c_str()); continue;
        }
        for (const auto& gt : byImage[img])
            std::fprintf(out, "%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\n", dst.string().c_str(),
                         gt.person.c_str(), gt.box.x, gt.box.y,
                         gt.box.x + gt.box.w, gt.box.y + gt.box.h);
        bytes += size_t(fs::file_size(dst, ec));
        ++written;
        if (written % 25 == 0) { std::printf("  ...%d images, %.0f MB\n", written, bytes / 1e6);
                                 std::fflush(stdout); }
    }
    std::fclose(out);
    std::printf("snapshot: %d images, %.0f MB -> %s\n  tsv -> %s\n",
                written, bytes / 1e6, outDir.c_str(), outTsv.c_str());
    return written > 0 ? 0 : 1;
}

// Part C: detection recall + in-context clustering against the full-res
// originals, driven by a TSV of ground-truth boxes (image \t person \t
// x1 \t y1 \t x2 \t y2, grouped by image).
int run_fullres(const fs::path& models, const fs::path& tsv, int maxImages) {
    const fs::path scrfd = models / "scrfd_10g.onnx";
    const fs::path aura = models / "auraface.onnx";
    std::printf("=== faces_probe : FULL-RES ===\n models=%s\n tsv=%s  maxImages=%d\n",
                models.c_str(), tsv.c_str(), maxImages);

    Detector det(scrfd.string(), 0.5f, 0.45f);
    Embedder emb(aura.string(), 127.5f, 127.5f);

    std::vector<std::string> order;
    std::map<std::string, std::vector<GtFace>> byImage;
    if (!parseGtTsv(tsv, order, byImage)) { std::printf("cannot open tsv\n"); return 2; }
    std::printf("ground truth: %zu faces across %zu images\n",
                [&] { size_t n = 0; for (auto& kv : byImage) n += kv.second.size(); return n; }(),
                order.size());

    int images = 0, readable = 0, gtTotal = 0, gtHit = 0, extra = 0;
    int hit30 = 0, hit50 = 0, hitCenter = 0;
    int bucket[6] = {0, 0, 0, 0, 0, 0};  // bestIoU in [0,.1),[.1,.2),...,[.5,1]
    std::vector<Embedding> embs; std::vector<std::string> labels;
    const auto t0 = std::chrono::steady_clock::now();
    for (const auto& img : order) {
        if (images >= maxImages) break;
        ++images;
        cv::Mat bgr = cv::imread(img, cv::IMREAD_COLOR);
        if (bgr.empty()) { std::printf("  [unreadable] %s\n", img.c_str()); continue; }
        ++readable;
        auto dets = det.detect(bgr);
        std::vector<char> used(dets.size(), 0);
        for (const auto& gt : byImage[img]) {
            ++gtTotal;
            // best IoU over ALL dets (diagnostic), plus center-containment (a
            // looser "face was found" test that ignores box-tightness convention).
            int arg = -1; float bestIoU = 0.0f; bool center = false;
            const float gcx = gt.box.x + gt.box.w * 0.5f, gcy = gt.box.y + gt.box.h * 0.5f;
            for (size_t i = 0; i < dets.size(); ++i) {
                float v = iou(gt.box, dets[i].box);
                if (v > bestIoU) { bestIoU = v; arg = int(i); }
                const float dcx = dets[i].box.x + dets[i].box.w * 0.5f;
                const float dcy = dets[i].box.y + dets[i].box.h * 0.5f;
                if (dcx >= gt.box.x && dcx <= gt.box.x + gt.box.w &&
                    dcy >= gt.box.y && dcy <= gt.box.y + gt.box.h) center = true;
                // also: GT center inside a det box (handles SCRFD-tighter case)
                if (gcx >= dets[i].box.x && gcx <= dets[i].box.x + dets[i].box.w &&
                    gcy >= dets[i].box.y && gcy <= dets[i].box.y + dets[i].box.h) center = true;
            }
            { int bi = int(bestIoU * 10); if (bi > 5) bi = 5; if (bi < 0) bi = 0; bucket[bi]++; }
            if (bestIoU >= 0.50f) ++hit50;
            if (bestIoU >= 0.30f) ++hit30;
            if (center) ++hitCenter;
            if (bestIoU >= 0.40f && arg >= 0 && !used[size_t(arg)]) {
                ++gtHit; used[size_t(arg)] = 1;
                cv::Mat al = align_arcface(bgr, dets[size_t(arg)].landmarks);
                embs.push_back(emb.embed(al, true));
                labels.push_back(gt.person);
            }
        }
        for (size_t i = 0; i < dets.size(); ++i) if (!used[i]) ++extra;
        if (images % 25 == 0) {
            std::printf("  ...%d images, recall@0.4 %d/%d (%.1f%%)\n", images, gtHit, gtTotal,
                        gtTotal ? 100.0 * gtHit / gtTotal : 0.0);
            std::fflush(stdout);
        }
    }
    const double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();

    std::printf("\nprocessed %d images (%d readable) in %.1fs\n", images, readable, secs);
    auto pct = [&](int h) { return gtTotal ? 100.0 * h / gtTotal : 0.0; };
    std::printf("DETECTION RECALL (vs Picasa boxes):\n");
    std::printf("  IoU>=0.50 : %d/%d = %.1f%%\n", hit50, gtTotal, pct(hit50));
    std::printf("  IoU>=0.40 : %d/%d = %.1f%%\n", gtHit, gtTotal, pct(gtHit));
    std::printf("  IoU>=0.30 : %d/%d = %.1f%%\n", hit30, gtTotal, pct(hit30));
    std::printf("  face-found (center-in-box, tightness-agnostic): %d/%d = %.1f%%\n",
                hitCenter, gtTotal, pct(hitCenter));
    std::printf("  bestIoU buckets [0,.1) .. [.5,1]: %d %d %d %d %d %d\n",
                bucket[0], bucket[1], bucket[2], bucket[3], bucket[4], bucket[5]);
    std::printf("  extra unmatched dets (likely real untagged faces): %d\n", extra);
    const double recall = pct(hitCenter);

    // Cluster the in-context faces and measure purity against ground truth.
    ClusterParams cp; cp.merge_distance = 0.45f;
    auto cl = cluster_agglomerative(embs, cp);
    std::map<int64_t, std::map<std::string, int>> votes;
    for (size_t i = 0; i < cl.size(); ++i) votes[cl[i]][labels[i]]++;
    int clusters = 0, pure = 0, correctlyGrouped = 0, total = int(embs.size());
    for (auto& [cid, v] : votes) {
        int top = 0, sum = 0; for (auto& [k, n] : v) { sum += n; top = std::max(top, n); }
        if (sum >= 2) { ++clusters; if (top == sum) ++pure; }
        correctlyGrouped += top;  // faces matching their cluster's majority
    }
    const double purity = total ? 100.0 * correctlyGrouped / total : 0.0;
    std::printf("CLUSTERING: %d multi-face clusters, %d 100%%-pure; weighted purity %.1f%% "
                "over %d embedded faces\n", clusters, pure, purity, total);

    const bool pass = recall >= 85.0 && purity >= 95.0;
    std::printf("\n=== FULL-RES %s (recall %.1f%%, purity %.1f%%) ===\n",
                pass ? "PASS" : "REVIEW", recall, purity);
    return pass ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::printf("usage:\n"
                    "  %s <models_dir> <test_db_dir> [per=8] [people=3]   # crops A+B\n"
                    "  %s fullres <models_dir> <faces.tsv> [maxImages=150] # full-res C\n",
                    argv[0], argv[0]);
        return 2;
    }
    if (std::string(argv[1]) == "fullres") {
        if (argc < 4) { std::printf("usage: %s fullres <models_dir> <faces.tsv> [maxImages]\n",
                                    argv[0]); return 2; }
        return run_fullres(argv[2], argv[3], argc > 4 ? std::atoi(argv[4]) : 150);
    }
    if (std::string(argv[1]) == "snapshot") {
        if (argc < 5) { std::printf("usage: %s snapshot <in.tsv> <out_dir> <out.tsv> "
                                    "[maxImages=120] [jpegQ=92]\n", argv[0]); return 2; }
        return run_snapshot(argv[2], argv[3], argv[4],
                            argc > 5 ? std::atoi(argv[5]) : 120,
                            argc > 6 ? std::atoi(argv[6]) : 92);
    }
    const fs::path models = argv[1];
    const fs::path db = argv[2];
    const int per = argc > 3 ? std::atoi(argv[3]) : 8;
    const int people = argc > 4 ? std::atoi(argv[4]) : 3;

    const fs::path scrfd = models / "scrfd_10g.onnx";
    const fs::path aura = models / "auraface.onnx";

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
