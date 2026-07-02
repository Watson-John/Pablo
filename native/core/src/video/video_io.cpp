// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "video/video_io.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <memory>

#ifdef PHOTO_HAVE_FFMPEG
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#pragma message("photo_native: FFmpeg video ENABLED (PHOTO_HAVE_FFMPEG)")
#else
#pragma message("photo_native: FFmpeg absent -> video probe/poster disabled")
#endif

namespace photo::video {

namespace {
std::string lower_ext(const std::string& path) {
    const auto slash = path.find_last_of("/\\");
    const auto dot = path.find_last_of('.');
    if (dot == std::string::npos || (slash != std::string::npos && dot < slash))
        return {};
    std::string ext = path.substr(dot);
    for (char& c : ext) c = static_cast<char>(std::tolower((unsigned char)c));
    return ext;
}
}  // namespace

bool is_video_path(const std::string& path) {
    const std::string ext = lower_ext(path);
    // Mirrors engine.cpp video_exts() and pablo/lib/data/library.dart _kVideoExts.
    return ext == ".mp4" || ext == ".mov" || ext == ".m4v" || ext == ".avi" ||
           ext == ".mkv" || ext == ".webm";
}

#ifdef PHOTO_HAVE_FFMPEG

namespace {

// RAII for the format context.
struct FmtCtx {
    AVFormatContext* p = nullptr;
    ~FmtCtx() { if (p) avformat_close_input(&p); }
};

// Open + analyze `path`, returning the best video stream index (or <0).
int open_video(const std::string& path, FmtCtx& fmt) {
    if (avformat_open_input(&fmt.p, path.c_str(), nullptr, nullptr) != 0)
        return -1;
    if (avformat_find_stream_info(fmt.p, nullptr) < 0) return -1;
    return av_find_best_stream(fmt.p, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
}

int64_t duration_ms_of(AVFormatContext* fmt, int stream) {
    if (fmt->duration > 0)
        return fmt->duration / (AV_TIME_BASE / 1000);
    // Fall back to the stream duration in its own time base.
    const AVStream* st = fmt->streams[stream];
    if (st->duration > 0 && st->time_base.den > 0) {
        return static_cast<int64_t>(
            static_cast<double>(st->duration) * av_q2d(st->time_base) * 1000.0);
    }
    return 0;
}

}  // namespace

ProbeResult probe(const std::string& path) {
    ProbeResult r;
    FmtCtx fmt;
    const int vs = open_video(path, fmt);
    if (vs < 0) return r;
    const AVCodecParameters* par = fmt.p->streams[vs]->codecpar;
    r.ok = true;
    r.width = par->width;
    r.height = par->height;
    r.duration_ms = duration_ms_of(fmt.p, vs);
    const char* name = avcodec_get_name(par->codec_id);
    if (name) r.codec = name;
    return r;
}

FramePtr poster_frame(const std::string& path, int max_dim) {
    FmtCtx fmt;
    const int vs = open_video(path, fmt);
    if (vs < 0) return nullptr;
    AVStream* st = fmt.p->streams[vs];

    const AVCodec* dec = avcodec_find_decoder(st->codecpar->codec_id);
    if (dec == nullptr) return nullptr;
    std::unique_ptr<AVCodecContext, void (*)(AVCodecContext*)> ctx(
        avcodec_alloc_context3(dec),
        [](AVCodecContext* c) { avcodec_free_context(&c); });
    if (!ctx) return nullptr;
    if (avcodec_parameters_to_context(ctx.get(), st->codecpar) < 0)
        return nullptr;
    if (avcodec_open2(ctx.get(), dec, nullptr) < 0) return nullptr;

    // Seek to ~10% so the poster isn't a black leader frame; snap to the
    // preceding keyframe. Best-effort — ignore failure and decode from the top.
    const int64_t dur_ms = duration_ms_of(fmt.p, vs);
    if (dur_ms > 0 && st->time_base.den > 0) {
        const double target_s = (dur_ms / 1000.0) * 0.10;
        const int64_t ts =
            static_cast<int64_t>(target_s / av_q2d(st->time_base));
        if (av_seek_frame(fmt.p, vs, ts, AVSEEK_FLAG_BACKWARD) >= 0)
            avcodec_flush_buffers(ctx.get());
    }

    std::unique_ptr<AVPacket, void (*)(AVPacket*)> pkt(
        av_packet_alloc(), [](AVPacket* p) { av_packet_free(&p); });
    std::unique_ptr<AVFrame, void (*)(AVFrame*)> frame(
        av_frame_alloc(), [](AVFrame* f) { av_frame_free(&f); });
    if (!pkt || !frame) return nullptr;

    AVFrame* got = nullptr;
    // Read packets from the video stream, feed the decoder, take the first frame.
    while (got == nullptr && av_read_frame(fmt.p, pkt.get()) >= 0) {
        if (pkt->stream_index == vs) {
            if (avcodec_send_packet(ctx.get(), pkt.get()) == 0) {
                if (avcodec_receive_frame(ctx.get(), frame.get()) == 0)
                    got = frame.get();
            }
        }
        av_packet_unref(pkt.get());
    }
    // Flush: some decoders hold the only frame until drained.
    if (got == nullptr) {
        avcodec_send_packet(ctx.get(), nullptr);
        if (avcodec_receive_frame(ctx.get(), frame.get()) == 0)
            got = frame.get();
    }
    if (got == nullptr || got->width <= 0 || got->height <= 0) return nullptr;

    // Downscale-only target bounded to max_dim on the long edge.
    const int sw = got->width, sh = got->height;
    double scale = 1.0;
    if (max_dim > 0 && std::max(sw, sh) > max_dim)
        scale = static_cast<double>(max_dim) / std::max(sw, sh);
    const int dw = std::max(1, static_cast<int>(std::lround(sw * scale)));
    const int dh = std::max(1, static_cast<int>(std::lround(sh * scale)));

    SwsContext* sws = sws_getContext(
        sw, sh, static_cast<AVPixelFormat>(got->format), dw, dh,
        AV_PIX_FMT_BGRA, SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (sws == nullptr) return nullptr;

    auto fb = std::make_shared<FrameBuffer>();
    fb->width = static_cast<uint32_t>(dw);
    fb->height = static_cast<uint32_t>(dh);
    fb->stride = static_cast<uint32_t>(dw) * 4;
    fb->bgra.resize(static_cast<size_t>(fb->stride) * dh);
    uint8_t* dst[4] = {fb->bgra.data(), nullptr, nullptr, nullptr};
    int dst_stride[4] = {static_cast<int>(fb->stride), 0, 0, 0};
    sws_scale(sws, got->data, got->linesize, 0, sh, dst, dst_stride);
    sws_freeContext(sws);

    // Video frames are opaque; BGRA from swscale already has A=255, so
    // premultiplied == straight. Force full alpha defensively.
    for (size_t i = 3; i < fb->bgra.size(); i += 4) fb->bgra[i] = 255;
    return fb;
}

bool remux_trim(const std::string& src, const std::string& dst,
                int64_t start_ms, int64_t end_ms) {
    if (src.empty() || dst.empty() || start_ms < 0) return false;
    if (end_ms > 0 && end_ms <= start_ms) return false;

    FmtCtx in;
    if (avformat_open_input(&in.p, src.c_str(), nullptr, nullptr) != 0)
        return false;
    if (avformat_find_stream_info(in.p, nullptr) < 0) return false;

    AVFormatContext* out = nullptr;
    if (avformat_alloc_output_context2(&out, nullptr, nullptr, dst.c_str()) <
            0 ||
        out == nullptr)
        return false;

    // Map every stream 1:1 with codec params copied (stream copy — no decode).
    const unsigned n = in.p->nb_streams;
    std::vector<int> out_index(n, -1);
    for (unsigned i = 0; i < n; ++i) {
        AVStream* is = in.p->streams[i];
        const AVMediaType t = is->codecpar->codec_type;
        if (t != AVMEDIA_TYPE_VIDEO && t != AVMEDIA_TYPE_AUDIO &&
            t != AVMEDIA_TYPE_SUBTITLE)
            continue;
        AVStream* os = avformat_new_stream(out, nullptr);
        if (os == nullptr) { avformat_free_context(out); return false; }
        if (avcodec_parameters_copy(os->codecpar, is->codecpar) < 0) {
            avformat_free_context(out);
            return false;
        }
        os->codecpar->codec_tag = 0;
        out_index[i] = os->index;
    }

    if (!(out->oformat->flags & AVFMT_NOFILE)) {
        if (avio_open(&out->pb, dst.c_str(), AVIO_FLAG_WRITE) < 0) {
            avformat_free_context(out);
            return false;
        }
    }
    if (avformat_write_header(out, nullptr) < 0) {
        if (out->pb) avio_closep(&out->pb);
        avformat_free_context(out);
        return false;
    }

    // Seek to the nearest keyframe at//before start (stream copy can only cut
    // on keyframes for the start point — the caller's UI notes the snap).
    const int64_t start_us = start_ms * 1000;
    const int64_t end_us = end_ms > 0 ? end_ms * 1000 : 0;
    av_seek_frame(in.p, -1, start_us, AVSEEK_FLAG_BACKWARD);

    std::unique_ptr<AVPacket, void (*)(AVPacket*)> pkt(
        av_packet_alloc(), [](AVPacket* p) { av_packet_free(&p); });
    if (!pkt) {
        if (out->pb) avio_closep(&out->pb);
        avformat_free_context(out);
        return false;
    }

    bool ok = true;
    while (av_read_frame(in.p, pkt.get()) >= 0) {
        const int si = pkt->stream_index;
        if (si < 0 || static_cast<unsigned>(si) >= n || out_index[si] < 0) {
            av_packet_unref(pkt.get());
            continue;
        }
        AVStream* is = in.p->streams[si];
        const int64_t pkt_us =
            av_rescale_q(pkt->pts != AV_NOPTS_VALUE ? pkt->pts : pkt->dts,
                         is->time_base, AVRational{1, 1000000});
        if (end_us > 0 && pkt_us >= end_us) {
            av_packet_unref(pkt.get());
            break;  // packets are read in ~dts order; past the end → done
        }
        AVStream* os = out->streams[out_index[si]];
        // Rebase timestamps so the clip starts at ~0.
        const int64_t shift = av_rescale_q(start_us, AVRational{1, 1000000},
                                           is->time_base);
        if (pkt->pts != AV_NOPTS_VALUE) pkt->pts -= shift;
        if (pkt->dts != AV_NOPTS_VALUE) pkt->dts -= shift;
        if (pkt->pts != AV_NOPTS_VALUE && pkt->pts < 0) { av_packet_unref(pkt.get()); continue; }
        av_packet_rescale_ts(pkt.get(), is->time_base, os->time_base);
        pkt->stream_index = out_index[si];
        pkt->pos = -1;
        if (av_interleaved_write_frame(out, pkt.get()) < 0) { ok = false; break; }
        av_packet_unref(pkt.get());
    }

    av_write_trailer(out);
    if (out->pb) avio_closep(&out->pb);
    avformat_free_context(out);
    return ok;
}

#else  // !PHOTO_HAVE_FFMPEG

ProbeResult probe(const std::string&) { return {}; }
FramePtr poster_frame(const std::string&, int) { return nullptr; }
bool remux_trim(const std::string&, const std::string&, int64_t, int64_t) {
    return false;
}

#endif  // PHOTO_HAVE_FFMPEG

}  // namespace photo::video
