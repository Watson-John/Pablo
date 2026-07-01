// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// edit_spec.h — the parametric, non-destructive edit stack for one asset.
//
// An EditSpec is the *parameters* of an edit (exposure, crop, a filter id, …),
// never pixels. It serializes to a compact, dependency-free `key=value;` string
// (mirroring Picasa's own `filters=`/`crop=` grammar) so it can live in the
// SQLite catalog, be embedded in a layered TIFF's XMP, and cross the C ABI as a
// plain UTF-8 string. The native render path (edit/render.{h,cpp}) turns a spec
// + decoded pixels into an edited frame; the Dart editor mirrors this same
// grammar so preview == saved.
//
// Fixed application order (see render.cpp): geometry → tone → colour → filter →
// detail (sharpen / noise) → vignette. Only non-default fields are serialized.
// Pure C++: no libvips, no SQLite, no OpenCV — so it compiles and is unit-tested
// on every target.

#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace photo::edit {

// A circular region (normalized centre + radius as a fraction of the image's
// short edge) used by red-eye and heal brush strokes.
struct Region {
    float x = 0.5f;
    float y = 0.5f;
    float r = 0.04f;
};

// One text overlay: position + size are normalized to the image (size is a
// fraction of the image height); color is 0xRRGGBB; `text` is the UTF-8 string.
struct TextItem {
    float    x = 0.5f;
    float    y = 0.5f;
    float    size = 0.06f;     // fraction of image height
    uint32_t color = 0xFFFFFF; // 0xRRGGBB
    std::string text;
};

// Parameters of a non-destructive edit. All slider fields are 0 at their
// neutral default; geometry defaults to "no transform"; filter defaults to the
// "none" preset. Ranges mirror the Dart EditSlider: tone/colour/vignette are
// [-100, 100]; sharpness/noise are [0, 100]; straighten is degrees [-45, 45].
struct EditSpec {
    // ── Geometry (applied first; wired in Stage B) ──────────────────────────
    int    rot90      = 0;      // user quarter-turns clockwise, 0..3
    bool   flipH      = false;
    bool   flipV      = false;
    double straighten = 0.0;    // degrees, auto-cropped to remove borders
    // Normalized crop rect in the post-rotate space. The full frame (no crop)
    // is l=0,t=0,w=1,h=1; cropW <= 0 also means "no crop".
    double cropL = 0.0, cropT = 0.0, cropW = 1.0, cropH = 1.0;

    // ── Tone (Light) ────────────────────────────────────────────────────────
    double exposure   = 0.0;
    double contrast   = 0.0;
    double highlights = 0.0;
    double shadows    = 0.0;
    double whites     = 0.0;
    double blacks     = 0.0;
    double clarity    = 0.0;
    double dehaze     = 0.0;

    // ── Colour ────────────────────────────────────────────────────────────
    double temperature = 0.0;
    double tint        = 0.0;
    double vibrance    = 0.0;
    double saturation  = 0.0;

    // ── Detail ────────────────────────────────────────────────────────────
    double sharpness = 0.0;   // [0, 100]
    double noise     = 0.0;   // [0, 100] noise reduction
    double vignette  = 0.0;   // [-100, 100] (negative darkens edges)

    // ── One-click enhance ───────────────────────────────────────────────────
    bool   autoFix   = false; // auto-levels (per-channel contrast stretch)

    // ── Curves ──────────────────────────────────────────────────────────────
    // Master tone curve as sorted (x,y) control points in [0,1]; empty or a
    // straight 0,0→1,1 line is identity. Applied as a 256-entry LUT to R/G/B.
    std::vector<std::pair<float, float>> curve;

    // ── Retouch ─────────────────────────────────────────────────────────────
    std::vector<Region> redeye;  // red-eye correction circles
    std::vector<Region> heal;    // heal / spot-removal brush strokes

    // ── Text overlays (rendered last, on top) ───────────────────────────────
    std::vector<TextItem> texts;

    // ── Filter preset ───────────────────────────────────────────────────────
    std::string filter = "none";  // id from filter_matrices.dart

    // True when this spec is a no-op: geometry untouched, every slider 0, and
    // the filter is the "none"/empty preset. The render + cache paths route an
    // identity spec exactly like an unedited asset (content_rev 0, no pixel
    // pass), so a saved-then-reset edit never forks the thumbnail cache.
    bool is_identity() const;

    // True when any geometry transform (rot/flip/straighten/crop) is set.
    bool has_geometry() const;

    // True when any pixel-domain op (tone/colour/filter/curve/autofix OR
    // retouch OR text) is set — drives is_identity so a retouch-only spec is
    // not treated as identity.
    bool has_pixel_ops() const;

    // True only for the apply_pixels domain (tone/colour/detail/filter/curve/
    // autofix). Red-eye, heal and text are applied by their own passes, so the
    // render gates apply_pixels on this narrower flag.
    bool has_tone_ops() const;

    // True when the curve is empty or lies on the y=x diagonal (no-op).
    bool curve_is_identity() const;
};

// One entry of the Engine's in-memory edit map: the current content_rev and the
// parsed spec (null when the asset has no/identity edit). ThumbService receives
// these from an injected lookup so the render workers never parse a spec or touch
// SQLite on the hot path. Copyable; the shared_ptr keeps the spec alive for the
// duration of a render even if the map is swapped concurrently.
struct EditEntry {
    uint32_t content_rev = 0;
    std::shared_ptr<const EditSpec> spec;  // null = no edit
};

// Parse a `key=value;` spec string. Unknown keys are ignored (forward-compat);
// malformed numbers fall back to the field default. Total — never throws.
EditSpec parse_edit_spec(const std::string& s);

// Serialize to the compact `key=value;` form, emitting only non-default fields
// (so an identity spec serializes to ""). Stable key order.
std::string serialize_edit_spec(const EditSpec& spec);

}  // namespace photo::edit
