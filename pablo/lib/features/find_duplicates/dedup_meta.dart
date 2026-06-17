// Ranking metadata for choosing the keeper in a duplicate group. Reads the real
// file when a photo has a filePath (dataset/import mode); falls back to the mock
// EXIF generator otherwise so the workflow ranks sensibly in the gradient mock.
//
// Date: real files use filesystem mtime as the capture-date proxy. True EXIF
// capture time arrives with the native backend (which parses it during decode).

import 'dart:io';

import '../../data/library.dart' show getPhotoExif;
import '../../data/models.dart';
import '../../utils/image_dims.dart';

class DedupMeta {
  /// File size in bytes (larger = higher quality, all else equal).
  static int bytes(Photo p) {
    try {
      return File(p.filePath).lengthSync();
    } catch (_) {/* fall through */}
    return _parseSize(getPhotoExif(p.id).fileSize);
  }

  /// Sortable capture-date key (epoch seconds for real files; YYYYMMDD for mock).
  static int dateKey(Photo p) {
    try {
      return File(p.filePath).lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {/* fall through */}
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})')
        .firstMatch(getPhotoExif(p.id).dateLabel ?? '');
    return m == null ? 0 : int.parse('${m[1]}${m[2]}${m[3]}');
  }

  /// Pixel count (width × height).
  static int resolution(Photo p) {
    final d = readImageDimensions(p.filePath);
    if (d != null) return d.width * d.height;
    final e = getPhotoExif(p.id);
    return e.width * e.height;
  }

  /// "5 MB" / "820 KB" / "1.2 GB" → bytes (mock EXIF fallback only).
  static int _parseSize(String s) {
    final m = RegExp(r'([\d.]+)\s*(KB|MB|GB|B)?').firstMatch(s.trim().toUpperCase());
    if (m == null) return 0;
    final v = double.tryParse(m.group(1)!) ?? 0;
    return switch (m.group(2)) {
      'GB' => (v * 1024 * 1024 * 1024).round(),
      'MB' => (v * 1024 * 1024).round(),
      'KB' => (v * 1024).round(),
      _ => v.round(),
    };
  }
}
