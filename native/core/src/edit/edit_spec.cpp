// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "edit/edit_spec.h"

#include <array>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string_view>

namespace photo::edit {

namespace {

constexpr double kEps = 1e-6;

bool nearly_zero(double v) { return std::fabs(v) < kEps; }

// strtod the [begin,end) view (NUL-terminated copy via std::string is avoided on
// the hot path by using a small stack buffer; values are short).
double to_double(std::string_view v, double fallback) {
    if (v.empty()) return fallback;
    std::array<char, 64> buf{};
    const size_t n = v.size() < buf.size() - 1 ? v.size() : buf.size() - 1;
    std::memcpy(buf.data(), v.data(), n);
    buf[n] = '\0';
    char* endp = nullptr;
    const double d = std::strtod(buf.data(), &endp);
    // Reject empty parses, trailing garbage, and non-finite values (strtod
    // happily parses "inf"/"nan", which would poison the render math).
    if (endp == buf.data() || *endp != '\0' || !std::isfinite(d)) return fallback;
    return d;
}

int to_int(std::string_view v, int fallback) {
    return static_cast<int>(to_double(v, static_cast<double>(fallback)));
}

bool to_bool(std::string_view v) {
    return v == "1" || v == "true";
}

// Format a double compactly: integers print without a decimal point, others
// with up to 4 significant fractional digits and trailing zeros trimmed.
std::string fmt(double v) {
    if (nearly_zero(v - std::round(v)) && std::fabs(v) < 1e15) {
        char b[32];
        std::snprintf(b, sizeof(b), "%lld", static_cast<long long>(std::llround(v)));
        return b;
    }
    // Big enough for any finite double's "%.4f" form (~316 chars at 1e308) so a
    // large-but-finite value serializes faithfully rather than truncating.
    char b[512];
    std::snprintf(b, sizeof(b), "%.4f", v);
    std::string s(b);
    // Trim trailing zeros, then a dangling '.'.
    size_t last = s.find_last_not_of('0');
    if (last != std::string::npos) {
        if (s[last] == '.') --last;
        s.erase(last + 1);
    }
    return s;
}

void append_kv(std::string& out, const char* key, const std::string& val) {
    out += key;
    out += '=';
    out += val;
    out += ';';
}

// Percent-encode the grammar delimiters (and control chars) so arbitrary text
// can live inside a spec value. Reversed by unesc().
std::string esc(const std::string& s) {
    std::string o;
    o.reserve(s.size());
    for (unsigned char c : s) {
        if (c == '%' || c == ';' || c == '=' || c == ',' || c == '|' || c < 0x20) {
            char b[4];
            std::snprintf(b, sizeof(b), "%%%02X", c);
            o += b;
        } else {
            o += static_cast<char>(c);
        }
    }
    return o;
}

// Parse a `x,y,r|x,y,r` region list (shared by redeye + heal).
std::vector<Region> parse_regions(std::string_view v) {
    std::vector<Region> out;
    size_t p = 0;
    while (p <= v.size()) {
        size_t bar = v.find('|', p);
        if (bar == std::string_view::npos) bar = v.size();
        std::string_view it = v.substr(p, bar - p);
        p = bar + 1;
        if (it.empty()) continue;
        const size_t c1 = it.find(',');
        const size_t c2 = c1 == std::string_view::npos ? c1 : it.find(',', c1 + 1);
        if (c2 == std::string_view::npos) continue;
        Region r;
        r.x = static_cast<float>(to_double(it.substr(0, c1), 0.5));
        r.y = static_cast<float>(to_double(it.substr(c1 + 1, c2 - c1 - 1), 0.5));
        r.r = static_cast<float>(to_double(it.substr(c2 + 1), 0.04));
        out.push_back(r);
    }
    return out;
}

std::string serialize_regions(const std::vector<Region>& rs) {
    std::string out;
    for (size_t i = 0; i < rs.size(); ++i) {
        if (i) out += '|';
        out += fmt(rs[i].x) + "," + fmt(rs[i].y) + "," + fmt(rs[i].r);
    }
    return out;
}

std::string unesc(std::string_view s) {
    auto hex = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        return -1;
    };
    std::string o;
    o.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size()) {
            const int h = hex(s[i + 1]), l = hex(s[i + 2]);
            if (h >= 0 && l >= 0) {
                o += static_cast<char>(h * 16 + l);
                i += 2;
                continue;
            }
        }
        o += s[i];
    }
    return o;
}

}  // namespace

bool EditSpec::has_geometry() const {
    return rot90 != 0 || flipH || flipV || !nearly_zero(straighten) ||
           !nearly_zero(cropL) || !nearly_zero(cropT) ||
           !nearly_zero(cropW - 1.0) || !nearly_zero(cropH - 1.0) ||
           cropW <= 0.0;
}

bool EditSpec::curve_is_identity() const {
    if (curve.empty()) return true;
    for (const auto& [x, y] : curve)
        if (std::fabs(x - y) > 1e-3) return false;
    return true;
}

bool EditSpec::has_tone_ops() const {
    if (autoFix) return true;
    if (!curve_is_identity()) return true;
    const bool filter_default = filter.empty() || filter == "none";
    return !(filter_default && nearly_zero(exposure) && nearly_zero(contrast) &&
             nearly_zero(highlights) && nearly_zero(shadows) &&
             nearly_zero(whites) && nearly_zero(blacks) && nearly_zero(clarity) &&
             nearly_zero(dehaze) && nearly_zero(temperature) &&
             nearly_zero(tint) && nearly_zero(vibrance) &&
             nearly_zero(saturation) && nearly_zero(sharpness) &&
             nearly_zero(noise) && nearly_zero(vignette));
}

bool EditSpec::has_pixel_ops() const {
    return has_tone_ops() || !redeye.empty() || !heal.empty() || !texts.empty();
}

bool EditSpec::is_identity() const {
    return !has_geometry() && !has_pixel_ops();
}

EditSpec parse_edit_spec(const std::string& s) {
    EditSpec e;
    size_t i = 0;
    const size_t n = s.size();
    while (i < n) {
        size_t semi = s.find(';', i);
        if (semi == std::string::npos) semi = n;
        std::string_view tok(s.data() + i, semi - i);
        i = semi + 1;
        if (tok.empty()) continue;
        const size_t eq = tok.find('=');
        if (eq == std::string_view::npos) continue;
        const std::string_view k = tok.substr(0, eq);
        const std::string_view v = tok.substr(eq + 1);

        if (k == "rot") e.rot90 = ((to_int(v, 0) % 4) + 4) % 4;
        else if (k == "fliph") e.flipH = to_bool(v);
        else if (k == "flipv") e.flipV = to_bool(v);
        else if (k == "straighten") e.straighten = to_double(v, 0);
        else if (k == "crop") {
            // value is "l,t,w,h"
            double c[4] = {0, 0, 1, 1};
            size_t p = 0;
            for (int idx = 0; idx < 4 && p <= v.size(); ++idx) {
                size_t comma = v.find(',', p);
                if (comma == std::string_view::npos) comma = v.size();
                c[idx] = to_double(v.substr(p, comma - p), c[idx]);
                p = comma + 1;
            }
            e.cropL = c[0]; e.cropT = c[1]; e.cropW = c[2]; e.cropH = c[3];
        }
        else if (k == "exposure") e.exposure = to_double(v, 0);
        else if (k == "contrast") e.contrast = to_double(v, 0);
        else if (k == "highlights") e.highlights = to_double(v, 0);
        else if (k == "shadows") e.shadows = to_double(v, 0);
        else if (k == "whites") e.whites = to_double(v, 0);
        else if (k == "blacks") e.blacks = to_double(v, 0);
        else if (k == "clarity") e.clarity = to_double(v, 0);
        else if (k == "dehaze") e.dehaze = to_double(v, 0);
        else if (k == "temp") e.temperature = to_double(v, 0);
        else if (k == "tint") e.tint = to_double(v, 0);
        else if (k == "vibrance") e.vibrance = to_double(v, 0);
        else if (k == "saturation") e.saturation = to_double(v, 0);
        else if (k == "sharpness") e.sharpness = to_double(v, 0);
        else if (k == "noise") e.noise = to_double(v, 0);
        else if (k == "vignette") e.vignette = to_double(v, 0);
        else if (k == "autofix") e.autoFix = to_bool(v);
        else if (k == "curves") {
            e.curve.clear();
            size_t p = 0;
            while (p <= v.size()) {
                size_t bar = v.find('|', p);
                if (bar == std::string_view::npos) bar = v.size();
                std::string_view pt = v.substr(p, bar - p);
                const size_t comma = pt.find(',');
                if (comma != std::string_view::npos)
                    e.curve.emplace_back(
                        static_cast<float>(to_double(pt.substr(0, comma), 0)),
                        static_cast<float>(to_double(pt.substr(comma + 1), 0)));
                p = bar + 1;
            }
        }
        else if (k == "text") {
            e.texts.clear();
            size_t p = 0;
            while (p <= v.size()) {
                size_t bar = v.find('|', p);
                if (bar == std::string_view::npos) bar = v.size();
                std::string_view it = v.substr(p, bar - p);
                p = bar + 1;
                if (it.empty()) continue;
                const size_t c1 = it.find(',');
                const size_t c2 = c1 == std::string_view::npos ? c1 : it.find(',', c1 + 1);
                const size_t c3 = c2 == std::string_view::npos ? c2 : it.find(',', c2 + 1);
                const size_t c4 = c3 == std::string_view::npos ? c3 : it.find(',', c3 + 1);
                if (c4 == std::string_view::npos) continue;
                TextItem t;
                t.x = static_cast<float>(to_double(it.substr(0, c1), 0.5));
                t.y = static_cast<float>(to_double(it.substr(c1 + 1, c2 - c1 - 1), 0.5));
                t.size = static_cast<float>(to_double(it.substr(c2 + 1, c3 - c2 - 1), 0.06));
                t.color = static_cast<uint32_t>(std::strtoul(
                    std::string(it.substr(c3 + 1, c4 - c3 - 1)).c_str(), nullptr, 16));
                t.text = unesc(it.substr(c4 + 1));
                e.texts.push_back(std::move(t));
            }
        }
        else if (k == "redeye") e.redeye = parse_regions(v);
        else if (k == "heal") e.heal = parse_regions(v);
        else if (k == "filter") e.filter = std::string(v);
        // unknown keys ignored (forward-compat)
    }
    return e;
}

std::string serialize_edit_spec(const EditSpec& e) {
    std::string out;
    // Geometry
    if (e.rot90 != 0) append_kv(out, "rot", fmt(e.rot90));
    if (e.flipH) append_kv(out, "fliph", "1");
    if (e.flipV) append_kv(out, "flipv", "1");
    if (!nearly_zero(e.straighten)) append_kv(out, "straighten", fmt(e.straighten));
    if (e.has_geometry() &&
        (!nearly_zero(e.cropL) || !nearly_zero(e.cropT) ||
         !nearly_zero(e.cropW - 1.0) || !nearly_zero(e.cropH - 1.0))) {
        append_kv(out, "crop",
                  fmt(e.cropL) + "," + fmt(e.cropT) + "," +
                  fmt(e.cropW) + "," + fmt(e.cropH));
    }
    // Tone
    if (!nearly_zero(e.exposure)) append_kv(out, "exposure", fmt(e.exposure));
    if (!nearly_zero(e.contrast)) append_kv(out, "contrast", fmt(e.contrast));
    if (!nearly_zero(e.highlights)) append_kv(out, "highlights", fmt(e.highlights));
    if (!nearly_zero(e.shadows)) append_kv(out, "shadows", fmt(e.shadows));
    if (!nearly_zero(e.whites)) append_kv(out, "whites", fmt(e.whites));
    if (!nearly_zero(e.blacks)) append_kv(out, "blacks", fmt(e.blacks));
    if (!nearly_zero(e.clarity)) append_kv(out, "clarity", fmt(e.clarity));
    if (!nearly_zero(e.dehaze)) append_kv(out, "dehaze", fmt(e.dehaze));
    // Colour
    if (!nearly_zero(e.temperature)) append_kv(out, "temp", fmt(e.temperature));
    if (!nearly_zero(e.tint)) append_kv(out, "tint", fmt(e.tint));
    if (!nearly_zero(e.vibrance)) append_kv(out, "vibrance", fmt(e.vibrance));
    if (!nearly_zero(e.saturation)) append_kv(out, "saturation", fmt(e.saturation));
    // Detail
    if (!nearly_zero(e.sharpness)) append_kv(out, "sharpness", fmt(e.sharpness));
    if (!nearly_zero(e.noise)) append_kv(out, "noise", fmt(e.noise));
    if (!nearly_zero(e.vignette)) append_kv(out, "vignette", fmt(e.vignette));
    if (e.autoFix) append_kv(out, "autofix", "1");
    // Curves
    if (!e.curve_is_identity()) {
        std::string val;
        for (size_t i = 0; i < e.curve.size(); ++i) {
            if (i) val += '|';
            val += fmt(e.curve[i].first) + "," + fmt(e.curve[i].second);
        }
        append_kv(out, "curves", val);
    }
    // Text overlays
    if (!e.texts.empty()) {
        std::string val;
        for (size_t i = 0; i < e.texts.size(); ++i) {
            if (i) val += '|';
            const TextItem& t = e.texts[i];
            char col[8];
            std::snprintf(col, sizeof(col), "%06X", t.color & 0xFFFFFFu);
            val += fmt(t.x) + "," + fmt(t.y) + "," + fmt(t.size) + "," + col +
                   "," + esc(t.text);
        }
        append_kv(out, "text", val);
    }
    // Retouch (post-geometry, normalized coords)
    if (!e.redeye.empty()) append_kv(out, "redeye", serialize_regions(e.redeye));
    if (!e.heal.empty()) append_kv(out, "heal", serialize_regions(e.heal));
    // Filter
    if (!e.filter.empty() && e.filter != "none") append_kv(out, "filter", e.filter);
    return out;
}

}  // namespace photo::edit
