// photo_meta_reader.dart — build a [PhotoMeta] for the scheme engine from a real
// file: filesystem mtime + best-effort EXIF. The `dart:io`/EXIF coupling lives
// here so the engine (scheme_engine.dart) and planner stay testable in isolation.

import 'dart:io';

import '../utils/exif.dart';
import 'scheme_engine.dart';

/// Read [path]'s metadata into a [PhotoMeta]. Never throws — a missing stat or
/// unreadable EXIF just leaves the corresponding fields at their defaults.
PhotoMeta photoMetaForPath(String path) {
  DateTime mtime;
  try {
    mtime = File(path).statSync().modified;
  } catch (_) {
    mtime = DateTime(2024);
  }
  final exif = readExif(path);
  final parts = path.split(RegExp(r'[\\/]'))..removeWhere((e) => e.isEmpty);
  final base = parts.isEmpty ? path : parts.last;
  final dot = base.lastIndexOf('.');
  final name = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot).toLowerCase() : '.jpg';
  final parents = parts.length >= 2
      ? parts.sublist(0, parts.length - 1).reversed.toList()
      : <String>[];
  return PhotoMeta(
    fileMtime: mtime,
    captureDate: exif?.dateTimeOriginal,
    originalName: name,
    ext: ext,
    make: exif?.make,
    model: exif?.model,
    parentDirs: parents,
  );
}
