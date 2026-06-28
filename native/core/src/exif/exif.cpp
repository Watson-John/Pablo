// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "exif/exif.h"

#ifdef PHOTO_HAVE_EXIF
#include <libexif/exif-data.h>
#include <libexif/exif-entry.h>
#include <libexif/exif-tag.h>
#include <libexif/exif-utils.h>

#include <cctype>
#include <cstdio>
#endif

namespace photo::exif {

#ifdef PHOTO_HAVE_EXIF
namespace {

std::string trim(std::string s) {
    auto issp = [](unsigned char c) { return std::isspace(c) != 0; };
    while (!s.empty() && issp(s.front())) s.erase(s.begin());
    while (!s.empty() && issp(s.back())) s.pop_back();
    return s;
}

// libexif-formatted string for a tag (e.g. FNumber -> "f/2.8"), trimmed.
std::string get_str(ExifData* ed, ExifIfd ifd, ExifTag tag) {
    ExifEntry* e = exif_content_get_entry(ed->ifd[ifd], tag);
    if (!e) return {};
    char buf[256] = {0};
    exif_entry_get_value(e, buf, sizeof(buf));
    return trim(buf);
}

// Numeric SHORT/LONG value for a tag (orientation, dimensions, ISO).
long get_int(ExifData* ed, ExifIfd ifd, ExifTag tag) {
    ExifEntry* e = exif_content_get_entry(ed->ifd[ifd], tag);
    if (!e) return 0;
    const ExifByteOrder o = exif_data_get_byte_order(ed);
    if (e->format == EXIF_FORMAT_SHORT) return exif_get_short(e->data, o);
    if (e->format == EXIF_FORMAT_LONG) return static_cast<long>(exif_get_long(e->data, o));
    return 0;
}

// One GPS coordinate: 3 rationals (deg, min, sec) in the GPS IFD + an N/S/E/W
// ref. Returns false if absent/malformed.
bool get_gps(ExifData* ed, ExifTag coord_tag, ExifTag ref_tag, double& out) {
    ExifEntry* e = exif_content_get_entry(ed->ifd[EXIF_IFD_GPS], coord_tag);
    if (!e || e->components < 3 || !e->data) return false;
    const ExifByteOrder o = exif_data_get_byte_order(ed);
    auto frac = [&](unsigned off) {
        ExifRational r = exif_get_rational(e->data + off, o);
        return r.denominator ? static_cast<double>(r.numerator) / r.denominator : 0.0;
    };
    double val = frac(0) + frac(8) / 60.0 + frac(16) / 3600.0;
    ExifEntry* re = exif_content_get_entry(ed->ifd[EXIF_IFD_GPS], ref_tag);
    if (re) {
        char rb[8] = {0};
        exif_entry_get_value(re, rb, sizeof(rb));
        if (rb[0] == 'S' || rb[0] == 'W') val = -val;
    }
    out = val;
    return true;
}

// Days since 1970-01-01 for a proleptic-Gregorian date (Howard Hinnant's
// algorithm). Portable — avoids timegm, which glibc hides under -std=c++20.
int64_t days_from_civil(int64_t y, unsigned m, unsigned d) {
    y -= m <= 2;
    const int64_t era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + static_cast<int64_t>(doe) - 719468;
}

// "YYYY:MM:DD HH:MM:SS" -> unix seconds (naive, treated as UTC), 0 on parse fail.
int64_t parse_datetime(const std::string& s) {
    int y, mo, d, h, mi, se;
    if (std::sscanf(s.c_str(), "%d:%d:%d %d:%d:%d", &y, &mo, &d, &h, &mi, &se) != 6)
        return 0;
    if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) return 0;
    return days_from_civil(y, static_cast<unsigned>(mo), static_cast<unsigned>(d)) * 86400 +
           h * 3600 + mi * 60 + se;
}

// GPS tags are plain #defines in exif-tag.h (not part of the ExifTag enum).
constexpr ExifTag kGpsLatRef = static_cast<ExifTag>(EXIF_TAG_GPS_LATITUDE_REF);
constexpr ExifTag kGpsLat = static_cast<ExifTag>(EXIF_TAG_GPS_LATITUDE);
constexpr ExifTag kGpsLonRef = static_cast<ExifTag>(EXIF_TAG_GPS_LONGITUDE_REF);
constexpr ExifTag kGpsLon = static_cast<ExifTag>(EXIF_TAG_GPS_LONGITUDE);
constexpr ExifTag kLensModel = static_cast<ExifTag>(0xA434);

}  // namespace

AssetMetadata extract(const std::string& path) {
    AssetMetadata m;
    ExifData* ed = exif_data_new_from_file(path.c_str());
    if (!ed) return m;

    const std::string make = get_str(ed, EXIF_IFD_0, EXIF_TAG_MAKE);
    const std::string model = get_str(ed, EXIF_IFD_0, EXIF_TAG_MODEL);
    m.camera = trim(make + " " + model);
    m.lens = get_str(ed, EXIF_IFD_EXIF, kLensModel);
    m.aperture = get_str(ed, EXIF_IFD_EXIF, EXIF_TAG_FNUMBER);
    m.shutter = get_str(ed, EXIF_IFD_EXIF, EXIF_TAG_EXPOSURE_TIME);
    m.focal = get_str(ed, EXIF_IFD_EXIF, EXIF_TAG_FOCAL_LENGTH);
    m.iso = static_cast<int32_t>(get_int(ed, EXIF_IFD_EXIF, EXIF_TAG_ISO_SPEED_RATINGS));
    m.datetime_unix = parse_datetime(get_str(ed, EXIF_IFD_EXIF, EXIF_TAG_DATE_TIME_ORIGINAL));
    m.orientation = static_cast<int32_t>(get_int(ed, EXIF_IFD_0, EXIF_TAG_ORIENTATION));
    if (m.orientation < 1 || m.orientation > 8) m.orientation = 1;
    m.width = static_cast<int32_t>(get_int(ed, EXIF_IFD_EXIF, EXIF_TAG_PIXEL_X_DIMENSION));
    m.height = static_cast<int32_t>(get_int(ed, EXIF_IFD_EXIF, EXIF_TAG_PIXEL_Y_DIMENSION));

    double lat = 0, lon = 0;
    if (get_gps(ed, kGpsLat, kGpsLatRef, lat) &&
        get_gps(ed, kGpsLon, kGpsLonRef, lon)) {
        m.has_gps = true;
        m.gps_lat = lat;
        m.gps_lon = lon;
    }

    exif_data_unref(ed);
    return m;
}

#else  // !PHOTO_HAVE_EXIF — metadata read needs libexif.

AssetMetadata extract(const std::string&) { return {}; }

#endif  // PHOTO_HAVE_EXIF

}  // namespace photo::exif
