// image_dims.dart — read an image's pixel dimensions from its file header
// WITHOUT decoding pixels. Pure Dart, no dependencies, no native call.
//
// Used at dataset-load time so the masonry layout can size each tile to the
// photo's true aspect ratio up front (avoids the relayout jitter you'd get if
// real dimensions only arrived after an async decode). Supports JPEG, PNG,
// GIF, and BMP — enough for the dataset path; unknown formats return null and
// the caller falls back to a hash-derived ratio.

import 'dart:io';
import 'dart:typed_data';

class ImageDims {
  const ImageDims(this.width, this.height);
  final int width;
  final int height;

  /// width / height. Guards against a zero height.
  double get aspect => height <= 0 ? 1.0 : width / height;
}

/// Reads [path]'s dimensions from its header. Returns null if the file is
/// missing, unreadable, or not a recognized format. Reads at most
/// [maxHeaderBytes] (image data past the header is never touched).
ImageDims? readImageDimensions(String path, {int maxHeaderBytes = 131072}) {
  try {
    final raf = File(path).openSync();
    try {
      final len = raf.lengthSync();
      final toRead = len < maxHeaderBytes ? len : maxHeaderBytes;
      if (toRead <= 0) return null;
      return _parse(raf.readSync(toRead));
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _le32(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

ImageDims? _mk(int w, int h) =>
    (w > 0 && h > 0) ? ImageDims(w, h) : null;

ImageDims? _parse(Uint8List b) {
  if (b.length < 4) return null;

  // PNG: 8-byte signature, then IHDR (length+type), width@16, height@20.
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    if (b.length < 24) return null;
    return _mk(_be32(b, 16), _be32(b, 20));
  }
  // GIF: "GIF", then logical screen width/height (little-endian u16) @6.
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    if (b.length < 10) return null;
    return _mk(b[6] | (b[7] << 8), b[8] | (b[9] << 8));
  }
  // BMP: "BM", BITMAPINFOHEADER width@18, height@22 (height may be negative
  // for top-down bitmaps).
  if (b[0] == 0x42 && b[1] == 0x4D) {
    if (b.length < 26) return null;
    final h = _le32(b, 22);
    return _mk(_le32(b, 18), h < 0 ? -h : h);
  }
  // JPEG: scan segment markers for the Start-Of-Frame.
  if (b[0] == 0xFF && b[1] == 0xD8) return _jpeg(b);

  return null;
}

ImageDims? _jpeg(Uint8List b) {
  final n = b.length;
  var i = 2; // past SOI (FF D8)
  while (i + 1 < n) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    // Skip any run of fill bytes (0xFF).
    var j = i + 1;
    while (j < n && b[j] == 0xFF) {
      j++;
    }
    if (j >= n) return null;
    final marker = b[j];
    final seg = j + 1; // first byte after the marker

    // Standalone markers (no length field): SOI, EOI, RSTn, TEM.
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      i = seg;
      continue;
    }
    if (seg + 1 >= n) return null;
    final len = (b[seg] << 8) | b[seg + 1]; // includes these 2 length bytes
    if (len < 2) return null;

    // SOF0..SOF15, excluding DHT(C4), JPG(C8), DAC(CC).
    final isSof = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final p = seg + 2; // payload: precision(1) height(2) width(2)
      if (p + 5 > n) return null;
      return _mk((b[p + 3] << 8) | b[p + 4], (b[p + 1] << 8) | b[p + 2]);
    }
    i = seg + len; // jump to the next marker
  }
  return null;
}
