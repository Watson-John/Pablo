// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// face_xmp.h — build (and parse back) an XMP packet carrying face regions in the
// Metadata Working Group "Regions" schema (mwg-rs), the interop format read by
// Lightroom, digiKam, and Picasa's own XMP export. Pure text: no libexif/pugixml
// dependency, so it compiles on every platform and is fully unit-testable.
//
// This is the WRITE half of DECISIONS D1's deferred metadata write-back. It is
// only ever invoked on an explicit user action (never on import), and writes a
// sidecar "<path>.xmp" — the original image bytes are never touched.

#pragma once

#include <string>
#include <vector>

namespace photo::xmp {

// A single face region. Coordinates are MWG-normalized: (cx, cy) is the region
// CENTRE and (w, h) its size, each a fraction 0..1 of the image dimension.
struct FaceRegion {
    std::string name;
    double cx = 0, cy = 0, w = 0, h = 0;
};

// Build a complete XMP sidecar document for an image of (img_w × img_h) pixels
// carrying `regions`. Region names are XML-escaped. Returns "" if img_w/img_h are
// non-positive.
std::string build_face_regions_xmp(int img_w, int img_h,
                                   const std::vector<FaceRegion>& regions);

// Parse face regions back out of an XMP document (round-trips build output and
// reads third-party mwg-rs sidecars). Returns the named regions found; tolerant
// of whitespace and attribute order. Never throws.
std::vector<FaceRegion> parse_face_regions(const std::string& xmp);

}  // namespace photo::xmp
