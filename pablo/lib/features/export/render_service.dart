// render_service.dart — "give me a shareable/printable file for this photo".
//
// An unedited JPEG can be shared/printed as-is (its original path). Anything
// else — an edited asset, or a non-JPEG we want as JPEG — is rendered to a
// flattened temp copy through the native export pipeline (the same
// exportAsset2 path Stage V1 added) and the temp path is returned. Used by
// Share (V2) and Print (V2); pure enough to unit-test with a fake engine.

import 'dart:async';
import 'dart:io';

import 'package:photo_native/photo_native.dart';

import '../../data/models.dart';
import '../../utils/asset_id.dart';

bool isJpeg(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.jpg') || p.endsWith('.jpeg');
}

/// When a file can be shared/printed AS-IS, return its path; otherwise null
/// (a render is needed). The as-is case is an unedited ([spec] empty),
/// full-size ([maxDim] 0) JPEG. Pure — the testable core of [renderTempCopy].
String? passthroughPath({
  required String filePath,
  required String spec,
  required int maxDim,
}) {
  if (spec.isEmpty && maxDim == 0 && isJpeg(filePath)) return filePath;
  return null;
}

/// The saved edit spec for [photo]'s asset, or '' when unedited.
typedef SpecLookup = String Function(int assetId);

/// Resolve a file suitable for sharing/printing [photo].
///
/// Returns the ORIGINAL path when the asset has no saved edit and is already a
/// JPEG (no work). Otherwise exports a flattened JPEG into [tempDir] (defaults
/// to the system temp) via [engine].exportAsset2, awaits its completion event
/// on [events], and returns the temp path. Returns null on failure/timeout or
/// when export is unsupported (no libvips).
///
/// [specLookup] defaults to engine.assetEdits; injectable for tests.
Future<String?> renderTempCopy({
  required Engine engine,
  required Stream<PhotoEvent> events,
  required Photo photo,
  int maxDim = 0,
  int quality = 95,
  Directory? tempDir,
  SpecLookup? specLookup,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final assetId = assetIdFor(photo.id);
  final spec = (specLookup ?? engine.assetEdits)(assetId);
  // Fast path: unedited JPEG at full size → hand back the original file.
  final passthrough =
      passthroughPath(filePath: photo.filePath, spec: spec, maxDim: maxDim);
  if (passthrough != null) return passthrough;

  final dir = tempDir ?? Directory.systemTemp;
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final stem = photo.filePath.split(Platform.pathSeparator).last;
  final dot = stem.lastIndexOf('.');
  final base = dot > 0 ? stem.substring(0, dot) : stem;
  final dst =
      '${dir.path}${Platform.pathSeparator}$base-$assetId.jpg';

  // Subscribe BEFORE submitting so a fast completion can't slip past us. The
  // request id isn't known until after submit, so record every export status
  // and resolve once our id is both known and seen (race-free).
  int? pendingReq;
  final statuses = <int, int>{};
  final done = Completer<bool>();
  void tryResolve() {
    final r = pendingReq;
    if (r != null && statuses.containsKey(r) && !done.isCompleted) {
      done.complete(statuses[r] == 0);
    }
  }

  final sub = events.listen((e) {
    if (e.kind != PhotoEventKind.exportComplete) return;
    statuses[e.requestId] = e.status;
    tryResolve();
  });

  final req = engine.exportAsset2(
    srcPath: photo.filePath,
    dstPath: dst,
    spec: spec,
    maxDim: maxDim,
    quality: quality,
  );
  if (req == 0) {
    await sub.cancel();
    return null; // export unsupported (no libvips)
  }
  pendingReq = req;
  tryResolve(); // in case the event already arrived during submit

  try {
    final ok = await done.future.timeout(timeout, onTimeout: () => false);
    return ok ? dst : null;
  } finally {
    await sub.cancel();
  }
}
