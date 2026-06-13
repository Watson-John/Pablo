// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "dedup/embed.h"

#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/imgproc.hpp>

#include "dedup/log.h"

#ifdef DEDUP_HAVE_ORT
#include <onnxruntime_cxx_api.h>
#ifdef _WIN32
#include <windows.h>
#endif
#if defined(__APPLE__)
// Dedicated CoreML factory: present in every macOS CoreML-enabled ORT build and
// works across versions. The generic AppendExecutionProvider("CoreML") string is
// only recognized on ORT >= 1.21, so we don't rely on it.
#include <coreml_provider_factory.h>
#endif
#endif

namespace dedup {

#ifdef DEDUP_HAVE_ORT
namespace {

// ImageNet normalization constants, RGB order (SSCD uses standard preprocessing).
constexpr float kMean[3] = {0.485f, 0.456f, 0.406f};
constexpr float kStd[3]  = {0.229f, 0.224f, 0.225f};

#ifdef _WIN32
std::wstring widen(const std::string& s) {
    if (s.empty()) return {};
    int n = ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    ::MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}
#endif

}  // namespace

struct Embedder::Impl {
    Ort::Env env{ORT_LOGGING_LEVEL_WARNING, "pablo-dedup"};
    Ort::SessionOptions opts;
    Ort::Session session{nullptr};
    Ort::AllocatorWithDefaultOptions alloc;
    Ort::MemoryInfo mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

    std::string input_name, output_name;
    std::vector<const char*> input_names, output_names;
    int in_w = 288, in_h = 288;
    int dim = 512;

    explicit Impl(const Config& cfg) {
        opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        if (cfg.intra_op_threads > 0) opts.SetIntraOpNumThreads(cfg.intra_op_threads);

        if (cfg.provider == "cuda") {
            try {
                OrtCUDAProviderOptions cuda{};  // device 0, defaults
                opts.AppendExecutionProvider_CUDA(cuda);
                LOG_INFO("embed: CUDA execution provider enabled");
            } catch (const std::exception& e) {
                LOG_WARN("embed: CUDA provider unavailable (" << e.what()
                          << "); falling back to CPU. Use the onnxruntime-gpu build.");
            }
        } else if (cfg.provider == "coreml") {
#if defined(__APPLE__)
            // Apple Neural Engine / GPU on macOS via the dedicated CoreML factory
            // (version-portable; degrades to CPU if the EP is unavailable).
            try {
                Ort::ThrowOnError(
                    OrtSessionOptionsAppendExecutionProvider_CoreML(opts, /*flags=*/0));
                LOG_INFO("embed: CoreML execution provider enabled");
            } catch (const std::exception& e) {
                LOG_WARN("embed: CoreML provider unavailable (" << e.what()
                          << "); falling back to CPU.");
            }
#else
            LOG_WARN("embed: provider=coreml is macOS-only; falling back to CPU");
#endif
        }

#ifdef _WIN32
        std::wstring model = widen(cfg.model_path);
        session = Ort::Session(env, model.c_str(), opts);
#else
        session = Ort::Session(env, cfg.model_path.c_str(), opts);
#endif
        if (session.GetInputCount() < 1 || session.GetOutputCount() < 1) {
            throw std::runtime_error("model has no input/output node");
        }

        auto in = session.GetInputNameAllocated(0, alloc);
        auto out = session.GetOutputNameAllocated(0, alloc);
        input_name = in.get();
        output_name = out.get();
        input_names = {input_name.c_str()};
        output_names = {output_name.c_str()};

        // Spatial dims: honour a fixed model shape, else the configured size.
        auto ishape = session.GetInputTypeInfo(0)
                          .GetTensorTypeAndShapeInfo().GetShape();
        if (ishape.size() == 4) {
            if (ishape[2] > 0) in_h = static_cast<int>(ishape[2]);
            if (ishape[3] > 0) in_w = static_cast<int>(ishape[3]);
        }
        if (in_h <= 0) in_h = cfg.input_size;
        if (in_w <= 0) in_w = cfg.input_size;

        // Embedding dim from the output's last axis (fallback 512).
        auto oshape = session.GetOutputTypeInfo(0)
                          .GetTensorTypeAndShapeInfo().GetShape();
        if (!oshape.empty() && oshape.back() > 0) {
            dim = static_cast<int>(oshape.back());
        }
        LOG_INFO("embed: loaded " << cfg.model_path << "  input=" << in_w << "x"
                                  << in_h << "  dim=" << dim
                                  << "  in='" << input_name << "' out='"
                                  << output_name << "'");
    }

    std::vector<float> run(const std::vector<cv::Mat>& images) {
        const int B = static_cast<int>(images.size());
        const size_t plane = static_cast<size_t>(in_w) * in_h;
        std::vector<float> input(static_cast<size_t>(B) * 3 * plane);

        for (int b = 0; b < B; ++b) {
            cv::Mat src = images[b];
            if (src.cols != in_w || src.rows != in_h) {
                cv::resize(src, src, cv::Size(in_w, in_h), 0, 0, cv::INTER_AREA);
            }
            // src is BGR 8-bit. Pack NCHW float, RGB order, ImageNet-normalized.
            for (int y = 0; y < in_h; ++y) {
                const uint8_t* row = src.ptr<uint8_t>(y);
                for (int x = 0; x < in_w; ++x) {
                    const uint8_t Bc = row[x * 3 + 0];
                    const uint8_t Gc = row[x * 3 + 1];
                    const uint8_t Rc = row[x * 3 + 2];
                    const float rgb[3] = {Rc / 255.0f, Gc / 255.0f, Bc / 255.0f};
                    const size_t off = static_cast<size_t>(y) * in_w + x;
                    for (int c = 0; c < 3; ++c) {
                        input[(static_cast<size_t>(b) * 3 + c) * plane + off] =
                            (rgb[c] - kMean[c]) / kStd[c];
                    }
                }
            }
        }

        const int64_t shape[4] = {B, 3, in_h, in_w};
        Ort::Value tensor = Ort::Value::CreateTensor<float>(
            mem, input.data(), input.size(), shape, 4);

        auto outputs = session.Run(Ort::RunOptions{nullptr},
                                   input_names.data(), &tensor, 1,
                                   output_names.data(), 1);
        const float* out = outputs[0].GetTensorData<float>();

        // L2-normalize each row so cosine similarity == dot product downstream.
        std::vector<float> result(static_cast<size_t>(B) * dim);
        for (int b = 0; b < B; ++b) {
            const float* src = out + static_cast<size_t>(b) * dim;
            float* dst = result.data() + static_cast<size_t>(b) * dim;
            double sq = 0.0;
            for (int i = 0; i < dim; ++i) sq += static_cast<double>(src[i]) * src[i];
            const float inv = sq > 0.0 ? static_cast<float>(1.0 / std::sqrt(sq)) : 0.0f;
            for (int i = 0; i < dim; ++i) dst[i] = src[i] * inv;
        }
        return result;
    }
};

Embedder::Embedder(const Config& cfg) : impl_(std::make_unique<Impl>(cfg)) {}
Embedder::~Embedder() = default;
std::vector<float> Embedder::embed_batch(const std::vector<cv::Mat>& images) {
    if (images.empty()) return {};
    return impl_->run(images);
}
int Embedder::dim() const { return impl_->dim; }
bool Embedder::available() { return true; }

#else  // !DEDUP_HAVE_ORT

struct Embedder::Impl {};
Embedder::Embedder(const Config&) {
    throw std::runtime_error(
        "embedding requires ONNX Runtime: rebuild with -DONNXRUNTIME_ROOT=<dist> "
        "(see native/dedup/README.md)");
}
Embedder::~Embedder() = default;
std::vector<float> Embedder::embed_batch(const std::vector<cv::Mat>&) { return {}; }
int Embedder::dim() const { return 0; }
bool Embedder::available() { return false; }

#endif  // DEDUP_HAVE_ORT

}  // namespace dedup
