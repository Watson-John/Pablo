// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// render.h — apply an EditSpec to decoded pixels.
//
// apply_pixels() is the colour/tone/filter/detail/vignette pass: pure C++ over a
// FrameBuffer's BGRA bytes, so it compiles and is unit-tested on every target
// (no libvips / OpenCV). It runs on STRAIGHT (un-premultiplied) channel values
// and re-premultiplies on write — the texture path expects premultiplied alpha
// (thumb_service.cpp). Geometry (rot90 / flip / straighten / crop) changes the
// frame's dimensions and is applied earlier on the libvips image; it lands with
// apply_geometry() in Stage B and is intentionally not handled here.
//
// The 12 filter presets are ported verbatim from
// pablo/lib/features/editor/filter_matrices.dart so the native save matches what
// the Dart preview path would compute.

#pragma once

#include <array>
#include <vector>

#include "edit/edit_spec.h"  // EditSpec, Region

// VipsImage is forward-declared so this header needn't include <vips/vips.h>;
// apply_geometry's body is libvips-gated (a no-op identity passthrough without
// it), but the declaration is always visible.
struct _VipsImage;
typedef struct _VipsImage VipsImage;

namespace photo {
struct FrameBuffer;
}

namespace photo::edit {

// Apply the non-geometry parameters of `spec` to `fb` in place. No-op for an
// identity spec or an empty frame. Alpha is preserved.
void apply_pixels(FrameBuffer& fb, const EditSpec& spec);

// Correct red-eye inside each `spec.redeye` brush dab. For each dab it measures a
// tone-invariant redness (rg-chromaticity), derives an adaptive cutoff from the
// surrounding skin ring, then grows and recolors ONLY the connected red pupil
// blob under the brush centre — so warm/dark skin in the disc is left alone
// (a plain per-pixel threshold greys it). Recolor preserves luminance, keeps the
// specular catch-light, and feathers the edge. Pure C++ over the BGRA buffer —
// builds on every target, no model. No-op when there are no red-eye regions or
// when a dab finds no red. Runs after apply_pixels.
void apply_redeye(FrameBuffer& fb, const EditSpec& spec);

// Red-eye AUTO-DETECT: given decoded BGR pixels (3 bytes/px) and eye-landmark
// pairs (each {leftX, leftY, rightX, rightY} in pixel coords, e.g. from SCRFD),
// return a red-eye brush Region (normalized centre + short-edge-fraction radius)
// for every eye that actually contains a red pupil — non-red eyes are skipped, so
// the returned list drives a one-click "fix all red-eyes". Pure C++ (no face
// model, no OpenCV) so it is unit-tested without the faces build; the caller
// supplies the pixels + landmarks. The regions feed the same apply_redeye pass.
std::vector<Region> auto_redeye_regions(
    const uint8_t* bgr, int width, int height, int stride,
    const std::vector<std::array<float, 4>>& eyes);

// Map a Region expressed in ORIGINAL-image normalized coordinates (as
// auto_redeye_regions emits: face landmarks live in source space) through the
// spec's geometry chain — flip → rot90 → straighten(+inscribed auto-crop) →
// crop — into the POST-GEOMETRY space that the retouch render passes operate
// in. Returns false when the point lands outside the final frame (e.g. the eye
// was cropped away); such dabs must be dropped, never misplaced. W/H are the
// original pixel dimensions. Pure C++ (mirrors apply_geometry's math without
// libvips) so it is unit-tested everywhere and pinned against the real
// apply_geometry render in the vips-enabled tests.
bool map_region_through_geometry(const Region& in, int W, int H,
                                 const EditSpec& spec, Region* out);

// Spot-heal each `spec.heal` circle by cloning a nearby donor patch with mean-
// matched, feathered compositing (classical, dependency-free). The donor offset
// and seam correction are computed per region. This is the CPU fallback; the
// structured hook `heal_region_onnx` (render.cpp) is where a bundled MI-GAN ONNX
// inpainter plugs in on targets that link onnxruntime. Runs after apply_redeye.
void apply_heal(FrameBuffer& fb, const EditSpec& spec);

// Composite the spec's text overlays onto `fb`, rendered LAST (on top of the
// tone/colour pass). Uses libvips' Pango text rasterizer; a no-op without
// libvips or when there are no text items. Text size + position are normalized
// to the frame, so they scale correctly across thumbnail / full-res renders.
void apply_text(FrameBuffer& fb, const EditSpec& spec);

// Apply the geometry of `spec` (flip → rot90 → straighten+auto-crop → crop) to
// a decoded libvips image. ALWAYS returns a NEW owned reference the caller must
// g_object_unref (an identity spec returns `in` with an added ref). Without
// libvips this is a no-op passthrough (adds a ref to `in`). The straighten step
// rotates by the angle and crops to the largest inscribed axis-aligned
// rectangle so no background border remains.
VipsImage* apply_geometry(VipsImage* in, const EditSpec& spec);

// Decode-resolution inflation factor for `spec`'s geometry: a crop or straighten
// shrinks the visible region, so the source must be decoded larger for the
// result to stay sharp at the target box. 1.0 when there is no geometry. Pure
// C++ (no libvips), so it is unit-testable everywhere.
double geometry_zoom(const EditSpec& spec);

}  // namespace photo::edit
