// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// metadata.h — EXIF extraction (libexif). A pure function: given a file path,
// pull out the camera/exposure/datetime/GPS fields the catalog persists and the
// UI shows. No catalog or engine dependency. Returns an empty struct (never
// throws) for files without EXIF or when libexif is unavailable (per
// DECISIONS D1: read-only, catalog-only — nothing is written back to files).

#pragma once

#include <cstdint>
#include <string>

namespace photo::exif {

struct AssetMetadata {
    std::string camera;        // "Make Model"
    std::string lens;          // EXIF LensModel (0xA434), if present
    std::string aperture;      // libexif-formatted, e.g. "f/2.8"
    std::string shutter;       // e.g. "1/250 sec"
    std::string focal;         // e.g. "50.0 mm"
    int32_t     iso = 0;
    int64_t     datetime_unix = 0;  // DateTimeOriginal as unix seconds, 0 if absent
    int32_t     orientation = 1;    // EXIF orientation 1..8
    int32_t     width = 0;          // EXIF PixelXDimension, 0 if absent
    int32_t     height = 0;
    bool        has_gps = false;
    double      gps_lat = 0.0;
    double      gps_lon = 0.0;
};

// Extract EXIF from `path`. Empty struct on no-EXIF / unsupported / no libexif.
AssetMetadata extract(const std::string& path);

}  // namespace photo::exif
