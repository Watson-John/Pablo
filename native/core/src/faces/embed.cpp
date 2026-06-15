// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "faces/embed.h"

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

#ifdef _WIN32
std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}
#endif

void l2_normalize(Embedding& v) {
    double s = 0.0;
    for (float x : v) s += static_cast<double>(x) * x;
    const float n = static_cast<float>(std::sqrt(s));
    if (n > 1e-12f)
        for (float& x : v) x /= n;
}

}  // namespace

struct Embedder::Impl {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "pablo-faces-embed"};
    Ort::SessionOptions opts;
    Ort::Session session{nullptr};
    Ort::AllocatorWithDefaultOptions alloc;
    Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    std::string input_name;
    std::string output_name;
    std::vector<const char*> input_names, output_names;
    float mean, scale;
    int dim = 0;

    Impl(const std::string& model, float m, float s) : mean(m), scale(s) {
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
#ifdef _WIN32
        std::wstring w = widen(model);
        session = Ort::Session(env, w.c_str(), opts);
#else
        session = Ort::Session(env, model.c_str(), opts);
#endif
        input_name = session.GetInputNameAllocated(0, alloc).get();
        output_name = session.GetOutputNameAllocated(0, alloc).get();
        input_names = {input_name.c_str()};
        output_names = {output_name.c_str()};
        auto shape = session.GetOutputTypeInfo(0).GetTensorTypeAndShapeInfo().GetShape();
        dim = shape.empty() ? 0 : static_cast<int>(shape.back());
    }

    Embedding run_once(const cv::Mat& bgr112) {
        // ArcFace preprocessing: RGB, (px - mean)/scale. blobFromImage applies
        // scalefactor*(img - meanScalar) with swapRB, so scalefactor=1/scale,
        // mean=(mean,mean,mean).
        cv::Mat blob = cv::dnn::blobFromImage(bgr112, 1.0 / scale, cv::Size(112, 112),
                                              cv::Scalar(mean, mean, mean), true, false);
        const int64_t shape[4] = {1, 3, 112, 112};
        Ort::Value in = Ort::Value::CreateTensor<float>(
            mem, reinterpret_cast<float*>(blob.data), blob.total(), shape, 4);
        auto outs = session.Run(Ort::RunOptions{nullptr}, input_names.data(), &in, 1,
                                output_names.data(), 1);
        const float* p = outs[0].GetTensorData<float>();
        const int d = dim > 0 ? dim
                              : static_cast<int>(
                                    outs[0].GetTensorTypeAndShapeInfo().GetElementCount());
        return Embedding(p, p + d);
    }

    Embedding embed(const cv::Mat& bgr112, bool tta) {
        Embedding e = run_once(bgr112);
        if (tta) {
            cv::Mat flipped;
            cv::flip(bgr112, flipped, 1);
            Embedding f = run_once(flipped);
            if (f.size() == e.size())
                for (size_t i = 0; i < e.size(); ++i) e[i] += f[i];
        }
        l2_normalize(e);
        return e;
    }
};

Embedder::Embedder(const std::string& model_path, float mean, float scale)
    : impl_(std::make_unique<Impl>(model_path, mean, scale)) {}
Embedder::~Embedder() = default;
Embedding Embedder::embed(const cv::Mat& a, bool tta) { return impl_->embed(a, tta); }
int Embedder::dim() const { return impl_->dim; }
bool Embedder::available() { return true; }

#else  // !FACES_HAVE_ORT

struct Embedder::Impl {};
Embedder::Embedder(const std::string&, float, float) {
    throw std::runtime_error("face embedding requires ONNX Runtime "
                             "(rebuild with FACES_HAVE_ORT)");
}
Embedder::~Embedder() = default;
Embedding Embedder::embed(const cv::Mat&, bool) { return {}; }
int Embedder::dim() const { return 0; }
bool Embedder::available() { return false; }

#endif  // FACES_HAVE_ORT

}  // namespace photo::faces
