// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "thumb/thumb_service.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <utility>

#include "edit/edit_spec.h"
#include "edit/render.h"
#include "thumb/slot.h"
#include "thumb/thumb_cache.h"

#ifdef PHOTO_HAVE_VIPS
#include <vips/vips.h>
// Compiler-emitted marker (survives Flutter's CMake-output filtering) so CI
// can confirm which platforms actually compiled the real-decode path.
#pragma message("photo_native: real libvips decode ENABLED (PHOTO_HAVE_VIPS)")
#else
#pragma message("photo_native: libvips absent -> synthetic decode fallback")
#endif

namespace photo {

namespace {

// FNV-1a 64-bit hash of the path. Deterministic across runs so the same
// photo always renders the same M2 synthetic color — useful for visual
// inspection in the gallery.
uint64_t fnv1a_64(const char* s, size_t n) {
    constexpr uint64_t kPrime = 0x100000001b3ULL;
    uint64_t h = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < n; ++i) {
        h ^= static_cast<uint8_t>(s[i]);
        h *= kPrime;
    }
    return h;
}

struct Bgra { uint8_t b, g, r, a; };

// Map (path, stage) to a stable BGRA color. Stage modulates brightness so
// the placeholder / thumb / full transitions are visually obvious during
// M2 testing. Replaced by real decoding in M3.
Bgra synthetic_color(const std::string& path, uint32_t stage) {
    uint64_t h = fnv1a_64(path.data(), path.size());
    uint8_t r = static_cast<uint8_t>((h >>  0) & 0xff);
    uint8_t g = static_cast<uint8_t>((h >>  8) & 0xff);
    uint8_t b = static_cast<uint8_t>((h >> 16) & 0xff);

    float brightness = 1.0f;
    switch (stage) {
        case PHOTO_STAGE_PLACEHOLDER32: brightness = 0.45f; break;
        case PHOTO_STAGE_THUMB256:      brightness = 0.85f; break;
        case PHOTO_STAGE_FULL:          brightness = 1.00f; break;
    }

    auto scale = [brightness](uint8_t v) {
        float f = static_cast<float>(v) * brightness + 24.0f;  // +24 floor
        if (f > 255.0f) f = 255.0f;
        return static_cast<uint8_t>(f);
    };
    return Bgra{scale(b), scale(g), scale(r), 255};
}

#ifdef PHOTO_HAVE_VIPS
// Initialize libvips exactly once per process.
bool ensure_vips() {
    static std::once_flag once;
    static bool ok = false;
    std::call_once(once, [] { ok = (VIPS_INIT("pablo") == 0); });
    return ok;
}

// Decode `path` shrink-on-load to fit a `max_dim` box. This is the single
// expensive operation (file read + JPEG/PNG/… decode). Returns the loaded
// VipsImage (caller owns the ref) or nullptr on failure.
VipsImage* decode_base(const std::string& path, int max_dim) {
    if (!ensure_vips()) return nullptr;
    VipsImage* base = nullptr;
    if (vips_thumbnail(path.c_str(), &base, max_dim, nullptr) != 0) {
        vips_error_clear();
        return nullptr;
    }
    return base;
}

// Derive a premultiplied-BGRA frame at a `dim` box from an already-decoded
// base image. Cheap in-memory resize — no file re-read. Returns nullptr on
// failure.
FramePtr frame_from_base(VipsImage* base, int dim) {
    VipsImage* sized = nullptr;
    if (vips_thumbnail_image(base, &sized, dim, nullptr) != 0) {
        vips_error_clear();
        return nullptr;
    }
    // Normalize to 8-bit sRGB, then ensure a straight-alpha channel.
    VipsImage* srgb = nullptr;
    if (vips_colourspace(sized, &srgb, VIPS_INTERPRETATION_sRGB, nullptr) != 0) {
        g_object_unref(sized);
        vips_error_clear();
        return nullptr;
    }
    g_object_unref(sized);
    VipsImage* rgba = srgb;
    if (vips_image_get_bands(srgb) < 4) {
        VipsImage* with_a = nullptr;
        if (vips_addalpha(srgb, &with_a, nullptr) != 0) {
            g_object_unref(srgb);
            vips_error_clear();
            return nullptr;
        }
        g_object_unref(srgb);
        rgba = with_a;
    }
    const int w = vips_image_get_width(rgba);
    const int h = vips_image_get_height(rgba);
    size_t n = 0;
    auto* mem = static_cast<uint8_t*>(vips_image_write_to_memory(rgba, &n));
    g_object_unref(rgba);
    if (mem == nullptr || w <= 0 || h <= 0) {
        if (mem != nullptr) g_free(mem);
        return nullptr;
    }

    auto fb = std::make_shared<FrameBuffer>();
    fb->width  = static_cast<uint32_t>(w);
    fb->height = static_cast<uint32_t>(h);
    fb->stride = fb->width * 4;
    fb->bgra.resize(static_cast<size_t>(fb->stride) * fb->height);

    const size_t px = static_cast<size_t>(w) * static_cast<size_t>(h);
    uint8_t* d = fb->bgra.data();
    for (size_t i = 0; i < px; ++i) {
        const uint8_t R = mem[i * 4 + 0];
        const uint8_t G = mem[i * 4 + 1];
        const uint8_t B = mem[i * 4 + 2];
        const uint8_t A = mem[i * 4 + 3];
        // Source is straight alpha; the texture path expects premultiplied.
        d[i * 4 + 0] = static_cast<uint8_t>((B * A + 127) / 255);
        d[i * 4 + 1] = static_cast<uint8_t>((G * A + 127) / 255);
        d[i * 4 + 2] = static_cast<uint8_t>((R * A + 127) / 255);
        d[i * 4 + 3] = A;
    }
    g_free(mem);
    return fb;
}

// Box dimension to decode for a given stage (progressive sharpening).
int stage_target_dim(uint32_t stage, uint32_t target_w, uint32_t target_h) {
    switch (stage) {
        case PHOTO_STAGE_PLACEHOLDER32: return 64;
        // 512px (long edge) so the gallery stays sharp up to the 400px zoom max
        // (and decent on HiDPI). Decoded once, downscaled for smaller zooms.
        case PHOTO_STAGE_THUMB256:      return 512;
        case PHOTO_STAGE_FULL: {
            uint32_t m = std::max(target_w, target_h);
            if (m < 256) m = 256;
            if (m > 2048) m = 2048;
            return static_cast<int>(m);
        }
        default: return 256;
    }
}

// Decode at full source resolution (downscale-only huge target → never upscales,
// returns the source-resolution image). Caller owns the ref.
VipsImage* decode_full(const std::string& path) {
    if (!ensure_vips()) return nullptr;
    VipsImage* img = nullptr;
    if (vips_thumbnail(path.c_str(), &img, 1 << 20, "size", VIPS_SIZE_DOWN,
                       nullptr) != 0) {
        vips_error_clear();
        return nullptr;
    }
    return img;
}

// Build a straight 3-band sRGB VipsImage from a premultiplied-BGRA FrameBuffer.
// Frames are opaque (A=255) so premultiplied == straight; just swap B/R, drop A.
VipsImage* frame_to_rgb_vips(const FrameBuffer& fb) {
    const int w = static_cast<int>(fb.width), h = static_cast<int>(fb.height);
    const int stride = static_cast<int>(fb.stride);
    if (w <= 0 || h <= 0) return nullptr;
    std::vector<uint8_t> rgb(static_cast<size_t>(w) * h * 3);
    for (int y = 0; y < h; ++y) {
        const uint8_t* row = fb.bgra.data() + static_cast<size_t>(y) * stride;
        uint8_t* o = rgb.data() + static_cast<size_t>(y) * w * 3;
        for (int x = 0; x < w; ++x) {
            const uint8_t* p = row + static_cast<size_t>(x) * 4;
            o[x * 3 + 0] = p[2];  // R
            o[x * 3 + 1] = p[1];  // G
            o[x * 3 + 2] = p[0];  // B
        }
    }
    return vips_image_new_from_memory_copy(rgb.data(), rgb.size(), w, h, 3,
                                           VIPS_FORMAT_UCHAR);
}

// Full-resolution edited render: decode → geometry → native-size frame → pixels
// → straight RGB VipsImage. Caller owns the ref. nullptr on failure.
VipsImage* render_full_image(const std::string& src, const edit::EditSpec& spec) {
    VipsImage* base = decode_full(src);
    if (base == nullptr) return nullptr;
    VipsImage* geo = nullptr;
    VipsImage* g = base;
    if (spec.has_geometry()) {
        geo = edit::apply_geometry(base, spec);
        if (geo != nullptr) g = geo;
    }
    const int W = vips_image_get_width(g), H = vips_image_get_height(g);
    FramePtr frame = frame_from_base(g, std::max(W, H));  // native size, no scale
    if (geo != nullptr) g_object_unref(geo);
    g_object_unref(base);
    if (frame == nullptr) return nullptr;
    if (spec.has_tone_ops())
        edit::apply_pixels(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.redeye.empty())
        edit::apply_redeye(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.heal.empty())
        edit::apply_heal(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.texts.empty())
        edit::apply_text(const_cast<FrameBuffer&>(*frame), spec);
    return frame_to_rgb_vips(*frame);
}

// Write a VipsImage to `dst`; jpg/jpeg honour `quality` via the filename option.
bool write_vips(VipsImage* img, const std::string& dst, int quality) {
    std::string lower = dst;
    for (char& c : lower) c = static_cast<char>(std::tolower((unsigned char)c));
    std::string target = dst;
    const bool is_jpg = lower.size() >= 4 &&
                        (lower.rfind(".jpg") == lower.size() - 4 ||
                         lower.rfind(".jpeg") == lower.size() - 5);
    if (quality > 0 && is_jpg)
        target = dst + "[Q=" + std::to_string(quality) + "]";
    if (vips_image_write_to_file(img, target.c_str(), nullptr) != 0) {
        vips_error_clear();
        return false;
    }
    return true;
}
#endif  // PHOTO_HAVE_VIPS

}  // namespace

ThumbService::ThumbService(SlotStore* slots, EventRing* events, JobSystem* jobs)
    : slots_(slots), events_(events), jobs_(jobs) {}

ThumbService::~ThumbService() {
#ifdef PHOTO_HAVE_VIPS
    std::lock_guard<std::mutex> lk(preview_base_.mu);
    if (preview_base_.base) {
        g_object_unref(static_cast<VipsImage*>(preview_base_.base));
        preview_base_.base = nullptr;
    }
#endif
}

uint64_t ThumbService::submit(uint64_t asset_id,
                              uint64_t slot_id,
                              uint64_t generation,
                              const char* path_utf8,
                              uint32_t target_w,
                              uint32_t target_h,
                              uint32_t wanted_stages_mask,
                              uint32_t priority) {
    if (slot_id == 0)              return 0;
    if (wanted_stages_mask == 0)   return 0;
    if (slots_->get(slot_id) == nullptr) return 0;

    const uint64_t request_id =
        next_request_id_.fetch_add(1, std::memory_order_relaxed);
    std::string path = path_utf8 ? std::string(path_utf8) : std::string{};

    auto handle = jobs_->submit(
        static_cast<int>(priority),
        [this, request_id, asset_id, slot_id, generation, p = std::move(path),
         target_w, target_h, wanted_stages_mask]() mutable {
            run_synthetic(request_id, asset_id, slot_id, generation,
                          std::move(p), target_w, target_h,
                          wanted_stages_mask);
            // Drop our cancellation entry now that the job is running.
            std::lock_guard lk(req_mu_);
            request_to_job_.erase(request_id);
        });

    {
        std::lock_guard lk(req_mu_);
        request_to_job_.emplace(request_id, handle.id);
    }
    return request_id;
}

void ThumbService::cancel(uint64_t request_id) {
    if (request_id == 0) return;
    uint64_t job_id = 0;
    {
        std::lock_guard lk(req_mu_);
        auto it = request_to_job_.find(request_id);
        if (it == request_to_job_.end()) return;
        job_id = it->second;
        request_to_job_.erase(it);
    }
    jobs_->cancel(job_id);
}

void ThumbService::publish_stage_for_path(Slot& slot,
                                          uint32_t stage,
                                          const std::string& path) {
    Bgra c = synthetic_color(path, stage);
    slot.publish_solid_color(c.b, c.g, c.r, c.a);
}

void ThumbService::emit_stage_ready(uint64_t request_id,
                                    uint64_t asset_id,
                                    uint64_t slot_id,
                                    uint64_t generation,
                                    uint32_t stage,
                                    uint32_t width,
                                    uint32_t height) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_STAGE_READY;
    e.stage = stage;
    e.status = PHOTO_STATUS_OK;
    e.width = width;
    e.height = height;
    e.request_id = request_id;
    e.asset_id = asset_id;
    e.slot_id = slot_id;
    e.generation = generation;
    events_->push(e);
}

void ThumbService::emit_stage_failed(uint64_t request_id,
                                     uint64_t asset_id,
                                     uint64_t slot_id,
                                     uint64_t generation,
                                     uint32_t stage,
                                     int32_t status) {
    photo_event_t e{};
    e.kind = PHOTO_EVT_STAGE_FAILED;
    e.stage = stage;
    e.status = status;
    e.request_id = request_id;
    e.asset_id = asset_id;
    e.slot_id = slot_id;
    e.generation = generation;
    events_->push(e);
}

void ThumbService::preview(uint64_t slot_id, uint64_t generation,
                           const std::string& path, uint32_t target_w,
                           uint32_t target_h, const edit::EditSpec& spec) {
#ifdef PHOTO_HAVE_VIPS
    auto* slot = slots_->get(slot_id);
    if (slot == nullptr) return;
    if (slot->current_generation() != generation) return;  // stale: editor moved on

    const int dim = stage_target_dim(PHOTO_STAGE_FULL, target_w, target_h);
    // Inflate the decode box for a geometry crop/straighten so the cropped region
    // is still ~1:1 at the display box. Geometry itself is applied per-tick (it
    // changes as the user drags the crop), not cached — only the decoded base is.
    const int dim_needed = spec.has_geometry()
        ? std::min(4096, static_cast<int>(std::ceil(dim * edit::geometry_zoom(spec))))
        : dim;

    FramePtr frame;
    {
        // Serialize decode + derive on the single shared base (libvips ops on one
        // image aren't guaranteed concurrent-safe). Pure tone/colour ticks reuse
        // the cached base (no re-decode); a larger needed dim re-decodes.
        std::lock_guard<std::mutex> lk(preview_base_.mu);
        auto* base = static_cast<VipsImage*>(preview_base_.base);
        if (base == nullptr || preview_base_.path != path ||
            preview_base_.decode_dim < dim_needed) {
            if (base) g_object_unref(base);
            preview_base_.base = nullptr;
            VipsImage* decoded = decode_base(path, dim);
            if (decoded == nullptr) {
                emit_stage_failed(0, 0, slot_id, generation, PHOTO_STAGE_FULL,
                                  PHOTO_STATUS_DECODE_ERROR);
                return;
            }
            // Materialize into a RANDOM-ACCESS memory image. decode_base returns
            // a lazy vips_thumbnail pipeline (sequential source access); deriving
            // from it more than once — i.e. a second preview() reusing the cached
            // base, as happens when a photo is reopened in the editor — fails on
            // the second read and yields no frame (the "blank on reopen" bug).
            // A memory copy is re-derivable any number of times.
            VipsImage* memimg = vips_image_copy_memory(decoded);
            g_object_unref(decoded);
            if (memimg == nullptr) {
                vips_error_clear();
                emit_stage_failed(0, 0, slot_id, generation, PHOTO_STAGE_FULL,
                                  PHOTO_STATUS_DECODE_ERROR);
                return;
            }
            base = memimg;
            preview_base_.base = base;
            preview_base_.path = path;
            preview_base_.decode_dim = dim_needed;
        }
        // Apply geometry per-tick on the cached (pre-geometry) base, then derive.
        VipsImage* render_base = base;
        VipsImage* geo = nullptr;
        if (spec.has_geometry()) {
            geo = edit::apply_geometry(base, spec);  // new owned ref
            if (geo != nullptr) render_base = geo;
        }
        frame = frame_from_base(render_base, dim);
        if (geo != nullptr) g_object_unref(geo);
    }
    if (frame == nullptr) {
        emit_stage_failed(0, 0, slot_id, generation, PHOTO_STAGE_FULL,
                          PHOTO_STATUS_DECODE_ERROR);
        return;
    }
    if (spec.has_tone_ops())
        edit::apply_pixels(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.redeye.empty())
        edit::apply_redeye(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.heal.empty())
        edit::apply_heal(const_cast<FrameBuffer&>(*frame), spec);
    if (!spec.texts.empty())
        edit::apply_text(const_cast<FrameBuffer&>(*frame), spec);
    if (slot->current_generation() != generation) return;  // re-check before publish
    const uint32_t fw = frame->width;
    const uint32_t fh = frame->height;
    slot->publish_frame(std::move(frame));
    emit_stage_ready(0, 0, slot_id, generation, PHOTO_STAGE_FULL, fw, fh);
#else
    (void)slot_id; (void)generation; (void)path;
    (void)target_w; (void)target_h; (void)spec;
#endif
}

bool ThumbService::export_to_file(const std::string& src, const std::string& dst,
                                  const edit::EditSpec& spec, int quality) {
#ifdef PHOTO_HAVE_VIPS
    VipsImage* out = render_full_image(src, spec);
    if (out == nullptr) return false;
    const bool ok = write_vips(out, dst, quality);
    g_object_unref(out);
    return ok;
#else
    (void)src; (void)dst; (void)spec; (void)quality;
    return false;
#endif
}

bool ThumbService::save_layered_tiff(const std::string& src,
                                     const std::string& dst,
                                     const edit::EditSpec& spec) {
#ifdef PHOTO_HAVE_VIPS
    VipsImage* edited = render_full_image(src, spec);
    if (edited == nullptr) return false;
    VipsImage* orig = decode_full(src);
    if (orig == nullptr) { g_object_unref(edited); return false; }
    // Normalize the original to 3-band sRGB so it matches the edited render for
    // the multi-page stack.
    {
        VipsImage* srgb = nullptr;
        if (vips_colourspace(orig, &srgb, VIPS_INTERPRETATION_sRGB, nullptr) == 0) {
            g_object_unref(orig);
            orig = srgb;
        } else {
            vips_error_clear();
        }
        if (vips_image_get_bands(orig) > 3) {
            VipsImage* ex = nullptr;
            if (vips_extract_band(orig, &ex, 0, "n", 3, nullptr) == 0) {
                g_object_unref(orig);
                orig = ex;
            } else {
                vips_error_clear();
            }
        }
    }
    const int we = vips_image_get_width(edited), he = vips_image_get_height(edited);
    const int wo = vips_image_get_width(orig), ho = vips_image_get_height(orig);
    const int CW = std::max(we, wo), CH = std::max(he, ho);
    // Center both in a common canvas (TIFF pages must share dimensions).
    VipsImage* p0 = nullptr;
    VipsImage* p1 = nullptr;
    bool ok = vips_embed(edited, &p0, (CW - we) / 2, (CH - he) / 2, CW, CH,
                         "extend", VIPS_EXTEND_BLACK, nullptr) == 0 &&
              vips_embed(orig, &p1, (CW - wo) / 2, (CH - ho) / 2, CW, CH,
                         "extend", VIPS_EXTEND_BLACK, nullptr) == 0;
    g_object_unref(edited);
    g_object_unref(orig);
    if (!ok) {
        if (p0) g_object_unref(p0);
        if (p1) g_object_unref(p1);
        vips_error_clear();
        return false;
    }
    VipsImage* pages[2] = {p0, p1};
    VipsImage* joined = nullptr;
    ok = vips_arrayjoin(pages, &joined, 2, "across", 1, nullptr) == 0;
    g_object_unref(p0);
    g_object_unref(p1);
    if (!ok || joined == nullptr) { vips_error_clear(); return false; }
    // Record the spec + original size so a Pablo reader can re-open it
    // parametrically and recover the original layer (page 1).
    const std::string desc = "pablo-edit;orig=" + std::to_string(wo) + "x" +
                             std::to_string(ho) + ";" +
                             edit::serialize_edit_spec(spec);
    vips_image_set_string(joined, "image-description", desc.c_str());
    ok = vips_tiffsave(joined, dst.c_str(), "page_height", CH, nullptr) == 0;
    if (!ok) vips_error_clear();
    g_object_unref(joined);
    return ok;
#else
    (void)src; (void)dst; (void)spec;
    return false;
#endif
}

void ThumbService::run_synthetic(uint64_t request_id,
                                 uint64_t asset_id,
                                 uint64_t slot_id,
                                 uint64_t generation,
                                 std::string path,
                                 uint32_t target_w,
                                 uint32_t target_h,
                                 uint32_t wanted_stages_mask) {
#ifndef PHOTO_HAVE_VIPS
    (void)target_w;
    (void)target_h;
#endif

    auto* slot = slots_->get(slot_id);
    if (slot == nullptr) {
        emit_stage_failed(request_id, asset_id, slot_id, generation,
                          0, PHOTO_STATUS_NOT_FOUND);
        return;
    }
    // Drop stale generations silently — this is the normal consequence of
    // rapid scroll-rebinding, not an error.
    if (slot->current_generation() != generation) {
        return;
    }

    constexpr uint32_t kStages[] = {
        PHOTO_STAGE_PLACEHOLDER32,
        PHOTO_STAGE_THUMB256,
        PHOTO_STAGE_FULL,
    };
    constexpr uint32_t kStageBits[] = {
        PHOTO_STAGE_MASK_PLACEHOLDER32,
        PHOTO_STAGE_MASK_THUMB256,
        PHOTO_STAGE_MASK_FULL,
    };
#ifdef PHOTO_HAVE_VIPS
    // Per requested stage: target box, cache key, and serve-state.
    struct StageReq {
        uint32_t stage;
        int dim;
        uint64_t key;
        bool wanted;
        bool served;
    };
    const bool use_cache = (cache_ != nullptr && cache_->ok());

    // Capture the asset's edit ONCE (lock-free COW read) and use this same rev
    // for both the cache key and the apply, so a concurrent save can't split
    // them. Identity / no edit → rev 0 → byte-identical keys to an unedited
    // asset (no cache churn) and no pixel pass.
    const edit::EditEntry edit =
        edit_lookup_ ? edit_lookup_(asset_id) : edit::EditEntry{};
    const bool has_edit = edit.spec && !edit.spec->is_identity();
    const uint32_t key_rev = has_edit ? edit.content_rev : 0u;

    StageReq reqs[3];
    for (size_t i = 0; i < 3; ++i) {
        reqs[i].stage = kStages[i];
        reqs[i].wanted = (wanted_stages_mask & kStageBits[i]) != 0;
        reqs[i].served = false;
        reqs[i].dim = reqs[i].wanted
                          ? stage_target_dim(kStages[i], target_w, target_h)
                          : 0;
        reqs[i].key = (use_cache && reqs[i].wanted)
                          ? ThumbCache::key(asset_id, kStages[i], path, key_rev)
                          : 0;
    }

    // 1) Serve cache hits immediately (no decode); note the misses' max box.
    int max_miss_dim = 0;
    for (size_t i = 0; i < 3; ++i) {
        if (!reqs[i].wanted) continue;
        if (slot->current_generation() != generation) return;
        FramePtr cached = use_cache ? cache_->get(reqs[i].key) : nullptr;
        if (cached != nullptr) {
            const uint32_t fw = cached->width;
            const uint32_t fh = cached->height;
            slot->publish_frame(std::move(cached));
            emit_stage_ready(request_id, asset_id, slot_id, generation,
                             reqs[i].stage, fw, fh);
            reqs[i].served = true;
        } else {
            max_miss_dim = std::max(max_miss_dim, reqs[i].dim);
        }
    }
    if (max_miss_dim == 0) return;  // fully served from cache — no file decode

    // 2) Decode the source once — inflating the box for any geometry crop /
    //    straighten so the visible region stays sharp — apply geometry, then
    //    derive + cache the remaining stages from the geometry-applied base.
    const bool has_geom = has_edit && edit.spec->has_geometry();
    const bool tone_ops = has_edit && edit.spec->has_tone_ops();
    const bool redeye_ops = has_edit && !edit.spec->redeye.empty();
    const bool heal_ops = has_edit && !edit.spec->heal.empty();
    // MUST include has_edit: edit.spec is null for an unedited asset (the lookup
    // returns a default EditEntry), so an unguarded edit.spec->texts.empty()
    // would null-deref on every unedited thumbnail render.
    const bool text_ops = has_edit && !edit.spec->texts.empty();
    int decode_dim = max_miss_dim;
    if (has_geom) {
        const double z = edit::geometry_zoom(*edit.spec);
        decode_dim = std::min(4096,
                              static_cast<int>(std::ceil(max_miss_dim * z)));
    }
    VipsImage* base = decode_base(path, decode_dim);
    if (base == nullptr) {
        emit_stage_failed(request_id, asset_id, slot_id, generation,
                          0, PHOTO_STATUS_DECODE_ERROR);
        return;
    }
    VipsImage* geo = nullptr;
    VipsImage* render_base = base;
    if (has_geom) {
        geo = edit::apply_geometry(base, *edit.spec);  // new owned ref
        if (geo != nullptr) render_base = geo;
    }
    for (size_t i = 0; i < 3; ++i) {
        if (!reqs[i].wanted || reqs[i].served) continue;
        if (slot->current_generation() != generation) break;  // stale: stop
        FramePtr frame = frame_from_base(render_base, reqs[i].dim);
        if (frame == nullptr) {
            emit_stage_failed(request_id, asset_id, slot_id, generation,
                              reqs[i].stage, PHOTO_STATUS_DECODE_ERROR);
            continue;
        }
        // Apply the saved tone/colour edit before caching/publishing. The frame
        // was just created and is solely owned here, so the const_cast is safe
        // (the object is not actually const). The cache stores the EDITED frame
        // under the rev-keyed slot, so a later hit serves it without re-applying.
        if (tone_ops)
            edit::apply_pixels(const_cast<FrameBuffer&>(*frame), *edit.spec);
        if (redeye_ops)
            edit::apply_redeye(const_cast<FrameBuffer&>(*frame), *edit.spec);
        if (heal_ops)
            edit::apply_heal(const_cast<FrameBuffer&>(*frame), *edit.spec);
        if (text_ops)
            edit::apply_text(const_cast<FrameBuffer&>(*frame), *edit.spec);
        if (use_cache) cache_->put(reqs[i].key, *frame);
        const uint32_t fw = frame->width;
        const uint32_t fh = frame->height;
        slot->publish_frame(std::move(frame));
        emit_stage_ready(request_id, asset_id, slot_id, generation,
                         reqs[i].stage, fw, fh);
    }
    if (geo != nullptr) g_object_unref(geo);
    g_object_unref(base);
#else
    for (size_t i = 0; i < 3; ++i) {
        if ((wanted_stages_mask & kStageBits[i]) == 0) continue;
        if (slot->current_generation() != generation) return;
        // M2 fallback: synthetic solid color (platforms without libvips).
        publish_stage_for_path(*slot, kStages[i], path);
        emit_stage_ready(request_id, asset_id, slot_id, generation,
                         kStages[i], slot->initial_w(), slot->initial_h());
    }
#endif
}

}  // namespace photo
