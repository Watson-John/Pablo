// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "xmp/face_xmp.h"

#include <cctype>
#include <cstdio>
#include <sstream>

namespace photo::xmp {
namespace {

std::string xml_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '&':  out += "&amp;";  break;
            case '<':  out += "&lt;";   break;
            case '>':  out += "&gt;";   break;
            case '"':  out += "&quot;"; break;
            case '\'': out += "&apos;"; break;
            default:   out += c;        break;
        }
    }
    return out;
}

std::string xml_unescape(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        if (s[i] == '&') {
            if (s.compare(i, 5, "&amp;") == 0)  { out += '&';  i += 5; continue; }
            if (s.compare(i, 4, "&lt;") == 0)   { out += '<';  i += 4; continue; }
            if (s.compare(i, 4, "&gt;") == 0)   { out += '>';  i += 4; continue; }
            if (s.compare(i, 6, "&quot;") == 0) { out += '"';  i += 6; continue; }
            if (s.compare(i, 6, "&apos;") == 0) { out += '\''; i += 6; continue; }
        }
        out += s[i++];
    }
    return out;
}

// Format a double compactly with 6 decimals, trimming trailing zeros so the
// output is stable and human-legible.
std::string num(double v) {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.6f", v);
    std::string s(buf);
    const auto dot = s.find('.');
    if (dot != std::string::npos) {
        size_t last = s.find_last_not_of('0');
        if (last == dot) last = dot - 1;  // ".000000" -> drop the dot too
        s.erase(last + 1);
    }
    return s;
}

// Attribute value fetch: find `attr="..."` (or attr='...') in s[from, to).
// Tolerates whitespace around '=', but requires the quote to follow the '='
// directly (modulo whitespace). Occurrences of the attribute name that are not
// followed by `="` — e.g. the literal text "stArea:y" inside an XML-escaped
// region Name, which contains no raw quotes — are skipped, not misread as the
// attribute. (A lax version of this scanner once matched such text and then
// returned the next quoted value anywhere downstream, corrupting the rect.)
bool find_attr(const std::string& s, size_t from, size_t to,
               const std::string& attr, std::string& out) {
    size_t pos = from;
    while ((pos = s.find(attr, pos)) != std::string::npos && pos < to) {
        size_t i = pos + attr.size();
        while (i < to && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
        if (i < to && s[i] == '=') {
            ++i;
            while (i < to && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
            if (i < to && (s[i] == '"' || s[i] == '\'')) {
                const char quote = s[i];
                const size_t q2 = s.find(quote, i + 1);
                if (q2 == std::string::npos || q2 > to) return false;
                out = s.substr(i + 1, q2 - i - 1);
                return true;
            }
        }
        pos += attr.size();
    }
    return false;
}

double to_d(const std::string& s) {
    try { return std::stod(s); } catch (...) { return 0.0; }
}

}  // namespace

std::string build_face_regions_xmp(int img_w, int img_h,
                                   const std::vector<FaceRegion>& regions) {
    if (img_w <= 0 || img_h <= 0) return "";
    std::ostringstream o;
    o << "<?xpacket begin=\"\xEF\xBB\xBF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n"
      << "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"Pablo\">\n"
      << " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"
      << "  <rdf:Description rdf:about=\"\"\n"
      << "    xmlns:mwg-rs=\"http://www.metadataworkinggroup.com/schemas/regions/\"\n"
      << "    xmlns:stArea=\"http://ns.adobe.com/xmp/sType/Area#\"\n"
      << "    xmlns:stDim=\"http://ns.adobe.com/xap/1.0/sType/Dimensions#\">\n"
      << "   <mwg-rs:Regions rdf:parseType=\"Resource\">\n"
      << "    <mwg-rs:AppliedToDimensions stDim:w=\"" << img_w
      << "\" stDim:h=\"" << img_h << "\" stDim:unit=\"pixel\"/>\n"
      << "    <mwg-rs:RegionList>\n"
      << "     <rdf:Bag>\n";
    for (const auto& r : regions) {
        o << "      <rdf:li rdf:parseType=\"Resource\">\n"
          << "       <mwg-rs:Name>" << xml_escape(r.name) << "</mwg-rs:Name>\n"
          << "       <mwg-rs:Type>Face</mwg-rs:Type>\n"
          << "       <mwg-rs:Area stArea:x=\"" << num(r.cx)
          << "\" stArea:y=\"" << num(r.cy)
          << "\" stArea:w=\"" << num(r.w)
          << "\" stArea:h=\"" << num(r.h)
          << "\" stArea:unit=\"normalized\"/>\n"
          << "      </rdf:li>\n";
    }
    o << "     </rdf:Bag>\n"
      << "    </mwg-rs:RegionList>\n"
      << "   </mwg-rs:Regions>\n"
      << "  </rdf:Description>\n"
      << " </rdf:RDF>\n"
      << "</x:xmpmeta>\n"
      << "<?xpacket end=\"w\"?>\n";
    return o.str();
}

std::vector<FaceRegion> parse_face_regions(const std::string& xmp) {
    std::vector<FaceRegion> out;
    size_t pos = 0;
    // Each region is an <rdf:li> containing a Name element and an Area element.
    while (true) {
        const size_t li = xmp.find("<rdf:li", pos);
        if (li == std::string::npos) break;
        size_t li_end = xmp.find("</rdf:li>", li);
        if (li_end == std::string::npos) li_end = xmp.size();
        pos = li_end + 1;

        FaceRegion r;
        // Name (element text).
        const size_t n0 = xmp.find("<mwg-rs:Name>", li);
        if (n0 != std::string::npos && n0 < li_end) {
            const size_t s = n0 + std::string("<mwg-rs:Name>").size();
            const size_t e = xmp.find("</mwg-rs:Name>", s);
            if (e != std::string::npos && e < li_end)
                r.name = xml_unescape(xmp.substr(s, e - s));
        }
        // Area (attributes).
        const size_t a0 = xmp.find("stArea:x", li);
        if (a0 == std::string::npos || a0 > li_end) continue;
        std::string v;
        if (find_attr(xmp, li, li_end, "stArea:x", v)) r.cx = to_d(v);
        if (find_attr(xmp, li, li_end, "stArea:y", v)) r.cy = to_d(v);
        if (find_attr(xmp, li, li_end, "stArea:w", v)) r.w = to_d(v);
        if (find_attr(xmp, li, li_end, "stArea:h", v)) r.h = to_d(v);
        if (!r.name.empty()) out.push_back(std::move(r));
    }
    return out;
}

}  // namespace photo::xmp
