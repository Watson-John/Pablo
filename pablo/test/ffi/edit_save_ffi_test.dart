// edit_save_ffi_test.dart — the edit-SAVE persistence path through the real
// dylib: exportAsset (flattened copy) and saveLayered (2-page TIFF), the two
// ways an edit currently reaches the filesystem. catalog_ffi_test covers
// exportAsset2 (resize/watermark batch); this file pins the plain save paths
// EditSession.save() actually calls, end to end: set edit → render → write →
// file exists, is the right format, and carries the edit.
//
// Gated like the other test/ffi files: skips (never fails) when libphoto_core
// isn't loadable or was built without libvips. Run with:
//
//   PHOTO_CORE_LIB=<abs path to libphoto_core.dylib> \
//     flutter test test/ffi/edit_save_ffi_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/image_dims.dart';
import 'package:photo_native/photo_native.dart';

Future<PhotoEvent> _waitFor(
  Stream<PhotoEvent> stream,
  bool Function(PhotoEvent) pred, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final c = Completer<PhotoEvent>();
  late StreamSubscription<PhotoEvent> sub;
  sub = stream.listen((e) {
    if (!c.isCompleted && pred(e)) c.complete(e);
  });
  return c.future.timeout(timeout).whenComplete(sub.cancel);
}

void main() {
  test('exportAsset + saveLayered write real files through the FFI', () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_editsave_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final srcPath = '${tmp.path}${sep}photo.jpg';
    fixture.copySync(srcPath);

    Engine? engine;
    try {
      engine = Engine.open(EngineConfig(
        catalogPath: '${tmp.path}${sep}catalog.db',
        cachePath: '${tmp.path}${sep}cache',
      ));
    } catch (e) {
      markTestSkipped('libphoto_core not loadable ($e)');
      return;
    }
    if (engine == null) {
      markTestSkipped('Engine.open returned null (no catalog support)');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    // Import so the edit has a real catalog asset to attach to (the save path
    // in the app always goes set-edit-then-write).
    final importReq = engine.importPath(tmp.path);
    await _waitFor(
        pump.stream,
        (e) =>
            e.kind == PhotoEventKind.importComplete &&
            e.requestId == importReq);
    final assets = engine.listAssets();
    expect(assets, hasLength(1));
    final assetId = assets.single.assetId;

    const spec = 'crop=0.5,0,0.5,1;saturation=-100;';
    final rev = engine.setAssetEdits(assetId, spec);
    expect(rev, greaterThan(0));
    expect(engine.assetEdits(assetId), spec);

    // Subscribe-first, then fire both writes; fast events must not be lost
    // (broadcast-stream race — same pattern as catalog_ffi_test).
    final completions = <int, int>{}; // requestId → status
    final sub = pump.stream.listen((e) {
      if (e.kind == PhotoEventKind.exportComplete) {
        completions[e.requestId] = e.status;
      }
    });
    addTearDown(sub.cancel);

    final flatOut = '${tmp.path}${sep}flat.jpg';
    final tiffOut = '${tmp.path}${sep}layered.pablo.tif';
    final flatReq =
        engine.exportAsset(srcPath: srcPath, dstPath: flatOut, spec: spec);
    final tiffReq =
        engine.saveLayered(srcPath: srcPath, dstPath: tiffOut, spec: spec);
    if (flatReq == 0 || tiffReq == 0) {
      markTestSkipped('dylib built without libvips — export rejected');
      return;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while ((!completions.containsKey(flatReq) ||
            !completions.containsKey(tiffReq)) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(completions[flatReq], 0, reason: 'flat export did not succeed');
    expect(completions[tiffReq], 0, reason: 'layered save did not succeed');

    // Flat copy: exists, decodable, and carries the crop (half the width).
    final srcDims = readImageDimensions(srcPath);
    final flatDims = readImageDimensions(flatOut);
    expect(srcDims, isNotNull);
    expect(flatDims, isNotNull);
    expect((flatDims!.width - srcDims!.width / 2).abs() <= 2, isTrue,
        reason: 'crop=0.5 width not honoured: '
            '${flatDims.width} vs src ${srcDims.width}');

    // Layered TIFF: exists, non-trivial, and actually a TIFF (magic bytes
    // II*\0 or MM\0*) — Dart can't read pages; the 2-page structure + original
    // preservation are pinned natively in edit_integration_test.cpp.
    final tiffBytes = File(tiffOut).readAsBytesSync();
    expect(tiffBytes.length, greaterThan(1024));
    final isTiff = (tiffBytes[0] == 0x49 &&
            tiffBytes[1] == 0x49 &&
            tiffBytes[2] == 0x2A) ||
        (tiffBytes[0] == 0x4D && tiffBytes[1] == 0x4D && tiffBytes[3] == 0x2A);
    expect(isTiff, isTrue, reason: 'layered output is not a TIFF');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
