// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/detector.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include <opencv2/dnn.hpp>
#include <opencv2/imgproc.hpp>

#ifdef FACES_HAVE_ORT
#include <onnxruntime_cxx_api.h>
#ifdef _WIN32
#include <windows.h>
#endif
#endif

namespace photo::faces {

#ifdef FACES_HAVE_ORT
namespace {

// SCRFD-10G(bnkps) has 3 strides, 2 anchors per cell. Output tensors come in
// 3 groups (score: last-dim 1, bbox: 4, kps: 10); within a group the largest
// (most points) is stride 8, then 16, then 32.
constexpr int kStrides[3] = {8, 16, 32};
constexpr int kAnchors = 2;

#ifdef _WIN32
std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}
#endif

float iou(const Box& a, const Box& b) {
    const float x1 = std::max(a.x, b.x), y1 = std::max(a.y, b.y);
    const float x2 = std::min(a.x + a.w, b.x + b.w), y2 = std::min(a.y + a.h, b.y + b.h);
    const float iw = std::max(0.0f, x2 - x1), ih = std::max(0.0f, y2 - y1);
    const float inter = iw * ih;
    const float uni = a.w * a.h + b.w * b.h - inter;
    return uni > 0 ? inter / uni : 0.0f;
}

}  // namespace

struct Detector::Impl {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "pablo-faces"};
    Ort::SessionOptions opts;
    Ort::Session session{nullptr};
    Ort::AllocatorWithDefaultOptions alloc;
    Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::string input_name;
    std::vector<std::string> output_names_str;
    std::vector<const char*> input_names, output_names;
    float score_thr, nms_thr;
    int input_size = 640;  // square; SCRFD input is divisible by 32

    Impl(const std::string& model, float st, float nt) : score_thr(st), nms_thr(nt) {
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        // One core per inference. Each scan runs on a single job-system worker;
        // bounding ONNX to one intra-op thread means N concurrent scans occupy
        // exactly N cores, so the worker pool cleanly reserves the rest for
        // interactive thumbnail decodes (rather than one scan saturating every
        // core via ONNX's default all-cores threading).
        opts.SetIntraOpNumThreads(1);
        opts.SetInterOpNumThreads(1);
        opts.SetExecutionMode(ExecutionMode::ORT_SEQUENTIAL);
#ifdef _WIN32
        std::wstring w = widen(model);
        session = Ort::Session(env, w.c_str(), opts);
#else
        session = Ort::Session(env, model.c_str(), opts);
#endif
        input_name = session.GetInputNameAllocated(0, alloc).get();
        input_names = {input_name.c_str()};
        for (size_t i = 0; i < session.GetOutputCount(); ++i)
            output_names_str.push_back(session.GetOutputNameAllocated(i, alloc).get());
        for (auto& s : output_names_str) output_names.push_back(s.c_str());
    }

    std::vector<DetectedFace> detect(const cv::Mat& bgr) {
        const int sz = input_size;
        const float scale = static_cast<float>(sz) / std::max(bgr.cols, bgr.rows);
        const int rw = static_cast<int>(std::lround(bgr.cols * scale));
        const int rh = static_cast<int>(std::lround(bgr.rows * scale));
        cv::Mat resized;
        cv::resize(bgr, resized, cv::Size(rw, rh));
        cv::Mat canvas = cv::Mat::zeros(sz, sz, CV_8UC3);
        resized.copyTo(canvas(cv::Rect(0, 0, rw, rh)));
        cv::Mat blob = cv::dnn::blobFromImage(canvas, 1.0 / 128.0, cv::Size(sz, sz),
                                              cv::Scalar(127.5, 127.5, 127.5), true, false);

        const int64_t shape[4] = {1, 3, sz, sz};
        Ort::Value in = Ort::Value::CreateTensor<float>(
            mem, reinterpret_cast<float*>(blob.data), blob.total(), shape, 4);
        auto outs = session.Run(Ort::RunOptions{nullptr}, input_names.data(), &in, 1,
                                output_names.data(), output_names.size());

        // Group output tensors by last-dim: 1=score, 4=bbox, 10=kps; sort each
        // group by point count desc -> stride 8, 16, 32.
        std::vector<int> sc, bb, kp;
        for (int i = 0; i < static_cast<int>(outs.size()); ++i) {
            auto d = outs[i].GetTensorTypeAndShapeInfo().GetShape();
            const int64_t last = d.back();
            if (last == 1) sc.push_back(i);
            else if (last == 4) bb.push_back(i);
            else if (last == 10) kp.push_back(i);
        }
        // Sort each group by concrete element count desc (stride 8 has the most
        // anchors, then 16, then 32). ElementCount is always concrete post-Run,
        // unlike GetShape() whose anchor axis can be a symbolic -1.
        auto count = [&](int i) {
            return outs[i].GetTensorTypeAndShapeInfo().GetElementCount();
        };
        auto bypoints = [&](std::vector<int>& v) {
            std::sort(v.begin(), v.end(), [&](int a, int b) { return count(a) > count(b); });
        };
        bypoints(sc); bypoints(bb); bypoints(kp);
        if (sc.size() < 3 || bb.size() < 3 || kp.size() < 3) return {};

        std::vector<DetectedFace> cand;
        for (int s = 0; s < 3; ++s) {
            const int stride = kStrides[s];
            const float* scores = outs[sc[s]].GetTensorData<float>();
            const float* bbox = outs[bb[s]].GetTensorData<float>();
            const float* kps = outs[kp[s]].GetTensorData<float>();
            const int fw = sz / stride, fh = sz / stride;
            const int n = fw * fh * kAnchors;
            for (int i = 0; i < n; ++i) {
                if (scores[i] < score_thr) continue;
                const int cell = i / kAnchors;
                const float cx = static_cast<float>(cell % fw) * stride;
                const float cy = static_cast<float>(cell / fw) * stride;
                DetectedFace f;
                const float x1 = cx - bbox[i * 4 + 0] * stride;
                const float y1 = cy - bbox[i * 4 + 1] * stride;
                const float x2 = cx + bbox[i * 4 + 2] * stride;
                const float y2 = cy + bbox[i * 4 + 3] * stride;
                f.box = {x1 / scale, y1 / scale, (x2 - x1) / scale, (y2 - y1) / scale};
                for (int k = 0; k < 5; ++k) {
                    f.landmarks[k * 2] = (cx + kps[i * 10 + k * 2] * stride) / scale;
                    f.landmarks[k * 2 + 1] = (cy + kps[i * 10 + k * 2 + 1] * stride) / scale;
                }
                f.score = scores[i];
                cand.push_back(f);
            }
        }
        // Greedy NMS.
        std::sort(cand.begin(), cand.end(),
                  [](const DetectedFace& a, const DetectedFace& b) { return a.score > b.score; });
        std::vector<DetectedFace> keep;
        std::vector<char> removed(cand.size(), 0);
        for (size_t i = 0; i < cand.size(); ++i) {
            if (removed[i]) continue;
            keep.push_back(cand[i]);
            for (size_t j = i + 1; j < cand.size(); ++j)
                if (!removed[j] && iou(cand[i].box, cand[j].box) > nms_thr) removed[j] = 1;
        }
        return keep;
    }
};

Detector::Detector(const std::string& model_path, float st, float nms)
    : impl_(std::make_unique<Impl>(model_path, st, nms)) {}
Detector::~Detector() = default;
std::vector<DetectedFace> Detector::detect(const cv::Mat& bgr) { return impl_->detect(bgr); }
bool Detector::available() { return true; }

#else  // !FACES_HAVE_ORT

struct Detector::Impl {};
Detector::Detector(const std::string&, float, float) {
    throw std::runtime_error("face detection requires ONNX Runtime "
                             "(rebuild with FACES_HAVE_ORT)");
}
Detector::~Detector() = default;
std::vector<DetectedFace> Detector::detect(const cv::Mat&) { return {}; }
bool Detector::available() { return false; }

#endif  // FACES_HAVE_ORT

}  // namespace photo::faces
