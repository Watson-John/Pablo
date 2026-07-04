// exif.dart — FALLBACK-ONLY EXIF parser. The primary metadata source is the
// native catalog (libexif on import → Engine.assetMetadata, see
// library.catalogMetadataLookup); this pure-Dart parser serves engine-less
// contexts (pure-Dart tests, not-yet-imported files in scheme previews) and
// the separate make/model split the combined catalog "camera" string loses.
// Read a small, useful subset of EXIF from a JPEG file header.
// Pure Dart, no dependencies, no pixel decode. Reads only the APP1/"Exif"
// segment and walks the TIFF IFD tree for the handful of tags Pablo surfaces:
// capture date, camera make/model, exposure triple, focal length, and GPS.
//
// Everything is best-effort and defensive: any malformed offset, truncated
// segment, or unrecognized layout returns null (or leaves that field null)
// rather than throwing. Most Flickr30k images carry no EXIF at all, so the
// common path is "no APP1 marker → returns null".

import 'dart:io';
import 'dart:typed_data';

class ExifInfo {
  const ExifInfo({
    this.dateTimeOriginal,
    this.make,
    this.model,
    this.fNumber,
    this.exposureSeconds,
    this.iso,
    this.focalLength,
    this.gpsLat,
    this.gpsLon,
  });

  final DateTime? dateTimeOriginal;
  final String? make;
  final String? model;
  final double? fNumber;
  final double? exposureSeconds;
  final int? iso;
  final double? focalLength;
  final double? gpsLat;
  final double? gpsLon;

  bool get isEmpty =>
      dateTimeOriginal == null &&
      make == null &&
      model == null &&
      fNumber == null &&
      exposureSeconds == null &&
      iso == null &&
      focalLength == null &&
      gpsLat == null &&
      gpsLon == null;
}

/// Read EXIF from [path]. Returns null if the file is unreadable, isn't a JPEG,
/// or carries no usable EXIF. Reads at most [maxBytes] from the head of the
/// file (EXIF lives near the start, right after SOI).
ExifInfo? readExif(String path, {int maxBytes = 196608}) {
  try {
    final raf = File(path).openSync();
    Uint8List head;
    try {
      final len = raf.lengthSync();
      final toRead = len < maxBytes ? len : maxBytes;
      if (toRead < 4) return null;
      head = raf.readSync(toRead);
    } finally {
      raf.closeSync();
    }
    return _parseJpeg(head);
  } catch (_) {
    return null;
  }
}

ExifInfo? _parseJpeg(Uint8List b) {
  // SOI
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    var marker = b[i + 1];
    // Skip fill bytes.
    while (marker == 0xFF && i + 2 < b.length) {
      i++;
      marker = b[i + 1];
    }
    // Standalone markers without a length field.
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      i += 2;
      continue;
    }
    if (i + 4 > b.length) return null;
    final segLen = (b[i + 2] << 8) | b[i + 3];
    if (segLen < 2) return null;
    final payloadStart = i + 4;
    final payloadEnd = payloadStart + segLen - 2;
    if (payloadEnd > b.length) return null;

    if (marker == 0xE1 &&
        payloadEnd - payloadStart >= 6 &&
        b[payloadStart] == 0x45 && // 'E'
        b[payloadStart + 1] == 0x78 && // 'x'
        b[payloadStart + 2] == 0x69 && // 'i'
        b[payloadStart + 3] == 0x66 && // 'f'
        b[payloadStart + 4] == 0x00 &&
        b[payloadStart + 5] == 0x00) {
      return _parseTiff(b, payloadStart + 6, payloadEnd);
    }
    // SOS — image data starts; no EXIF beyond this point.
    if (marker == 0xDA) return null;
    i = payloadEnd;
  }
  return null;
}

ExifInfo? _parseTiff(Uint8List b, int base, int end) {
  if (base + 8 > end) return null;
  final bom = (b[base] << 8) | b[base + 1];
  final bool little;
  if (bom == 0x4949) {
    little = true; // 'II'
  } else if (bom == 0x4D4D) {
    little = false; // 'MM'
  } else {
    return null;
  }

  int u16(int o) =>
      little ? (b[o] | (b[o + 1] << 8)) : ((b[o] << 8) | b[o + 1]);
  int u32(int o) => little
      ? (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24))
      : ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]);

  final magic = u16(base + 2);
  if (magic != 42) return null;
  final ifd0 = base + u32(base + 4);
  if (ifd0 + 2 > end || ifd0 < base) return null;

  // Collected fields.
  String? make, model, dateStr;
  double? fNumber, exposure, focal, gpsLat, gpsLon;
  int? iso;
  String? gpsLatRef, gpsLonRef;
  int? exifIfdPtr, gpsIfdPtr;

  // Tag value readers. type: 2=ASCII, 3=SHORT, 4=LONG, 5=RATIONAL, 10=SRATIONAL.
  String? readAscii(int valOff, int count) {
    // The loop below already stops at the terminating NUL, so don't pre-trim
    // the count — some producers omit the NUL and pack the full slot.
    final cnt = count <= 0 ? 0 : count;
    if (valOff < base || valOff + cnt > end) return null;
    final bytes = <int>[];
    for (var k = 0; k < cnt; k++) {
      final c = b[valOff + k];
      if (c == 0) break;
      bytes.add(c);
    }
    return String.fromCharCodes(bytes).trim();
  }

  double? readRational(int o, {bool signed = false}) {
    if (o < base || o + 8 > end) return null;
    final num = signed ? _asSigned(u32(o)) : u32(o);
    final den = signed ? _asSigned(u32(o + 4)) : u32(o + 4);
    if (den == 0) return null;
    return num / den;
  }

  void walkIfd(int ifd,
      void Function(int tag, int type, int count, int entryOff) onTag) {
    if (ifd + 2 > end || ifd < base) return;
    final n = u16(ifd);
    var e = ifd + 2;
    for (var k = 0; k < n; k++) {
      if (e + 12 > end) break;
      final tag = u16(e);
      final type = u16(e + 2);
      final count = u32(e + 4);
      onTag(tag, type, count, e + 8);
      e += 12;
    }
  }

  // Resolve where a tag's value lives: inline (<=4 bytes) or at the offset.
  int valueOffset(int type, int count, int entryValOff) {
    final size = _typeSize(type) * count;
    if (size <= 4) return entryValOff;
    return base + u32(entryValOff);
  }

  walkIfd(ifd0, (tag, type, count, entryOff) {
    switch (tag) {
      case 0x010F: // Make
        make = readAscii(valueOffset(type, count, entryOff), count);
        break;
      case 0x0110: // Model
        model = readAscii(valueOffset(type, count, entryOff), count);
        break;
      case 0x8769: // Exif IFD pointer
        exifIfdPtr = base + u32(entryOff);
        break;
      case 0x8825: // GPS IFD pointer
        gpsIfdPtr = base + u32(entryOff);
        break;
    }
  });

  if (exifIfdPtr != null) {
    walkIfd(exifIfdPtr!, (tag, type, count, entryOff) {
      switch (tag) {
        case 0x9003: // DateTimeOriginal
        case 0x9004: // DateTimeDigitized (fallback)
          dateStr ??= readAscii(valueOffset(type, count, entryOff), count);
          break;
        case 0x829D: // FNumber
          fNumber = readRational(valueOffset(type, count, entryOff));
          break;
        case 0x829A: // ExposureTime
          exposure = readRational(valueOffset(type, count, entryOff));
          break;
        case 0x8827: // ISO — spec-permitted as SHORT or LONG.
          if (count >= 1) {
            final o = valueOffset(type, count, entryOff);
            int? v;
            if (type == 4) {
              if (o + 4 <= end) v = u32(o);
            } else {
              if (o + 2 <= end) v = u16(o);
            }
            if (v != null && v > 0) iso = v;
          }
          break;
        case 0x920A: // FocalLength
          focal = readRational(valueOffset(type, count, entryOff));
          break;
      }
    });
  }

  if (gpsIfdPtr != null) {
    walkIfd(gpsIfdPtr!, (tag, type, count, entryOff) {
      switch (tag) {
        case 0x0001: // GPSLatitudeRef
          gpsLatRef = readAscii(valueOffset(type, count, entryOff), count);
          break;
        case 0x0002: // GPSLatitude (3 rationals: d, m, s)
          gpsLat =
              _readGpsCoord(u32, base, end, valueOffset(type, count, entryOff));
          break;
        case 0x0003: // GPSLongitudeRef
          gpsLonRef = readAscii(valueOffset(type, count, entryOff), count);
          break;
        case 0x0004: // GPSLongitude
          gpsLon =
              _readGpsCoord(u32, base, end, valueOffset(type, count, entryOff));
          break;
      }
    });
    if (gpsLat != null && gpsLatRef == 'S') gpsLat = -gpsLat!;
    if (gpsLon != null && gpsLonRef == 'W') gpsLon = -gpsLon!;
  }

  final info = ExifInfo(
    dateTimeOriginal: _parseExifDate(dateStr),
    make: (make != null && make!.isEmpty) ? null : make,
    model: (model != null && model!.isEmpty) ? null : model,
    fNumber: fNumber,
    exposureSeconds: exposure,
    iso: iso,
    focalLength: focal,
    gpsLat: gpsLat,
    gpsLon: gpsLon,
  );
  return info.isEmpty ? null : info;
}

int _typeSize(int type) {
  switch (type) {
    case 1: // BYTE
    case 2: // ASCII
    case 6: // SBYTE
    case 7: // UNDEFINED
      return 1;
    case 3: // SHORT
    case 8: // SSHORT
      return 2;
    case 4: // LONG
    case 9: // SLONG
    case 11: // FLOAT
      return 4;
    case 5: // RATIONAL
    case 10: // SRATIONAL
    case 12: // DOUBLE
      return 8;
    default:
      return 1;
  }
}

int _asSigned(int u) => u >= 0x80000000 ? u - 0x100000000 : u;

double? _readGpsCoord(int Function(int) u32, int base, int end, int o) {
  // Three RATIONALs: degrees, minutes, seconds.
  if (o < base || o + 24 > end) return null;
  double rat(int off) {
    final den = u32(off + 4);
    if (den == 0) return 0;
    return u32(off) / den;
  }

  final d = rat(o);
  final m = rat(o + 8);
  final s = rat(o + 16);
  return d + m / 60.0 + s / 3600.0;
}

DateTime? _parseExifDate(String? s) {
  if (s == null || s.length < 19) return null;
  // Canonical EXIF: "YYYY:MM:DD HH:MM:SS".
  try {
    final y = int.parse(s.substring(0, 4));
    final mo = int.parse(s.substring(5, 7));
    final d = int.parse(s.substring(8, 10));
    final h = int.parse(s.substring(11, 13));
    final mi = int.parse(s.substring(14, 16));
    final se = int.parse(s.substring(17, 19));
    // Reject implausible components rather than let DateTime silently roll them
    // over (e.g. hour 25 → next day) and fabricate a wrong timestamp.
    if (y < 1800 ||
        y > 3000 ||
        mo < 1 ||
        mo > 12 ||
        d < 1 ||
        d > 31 ||
        h > 23 ||
        mi > 59 ||
        se > 60) {
      return null;
    }
    return DateTime(y, mo, d, h, mi, se);
  } catch (_) {
    return null;
  }
}
