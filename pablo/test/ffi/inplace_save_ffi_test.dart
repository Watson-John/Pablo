// inplace_save_ffi_test.dart — the overwrite-with-backup save mode through the
// real dylib: import → set edit → saveInPlace (backup secured, pixels baked,
// spec cleared) → rescan (same id, backup not imported) → revertInPlace
// (byte-identical original restored, backup gone). The native pieces are
// unit-tested in edit_integration_test.cpp; this pins the Dart FFI wrappers +
// the event contract end to end.
//
// Gated like the other test/ffi files (PHOTO_CORE_LIB; skips without vips).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_native/photo_native.dart';

void main() {
  test('save-in-place cycle: backup, bake, rescan identity, revert', () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_inplace_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final srcPath = '${tmp.path}${sep}photo.jpg';
    fixture.copySync(srcPath);
    final originalBytes = File(srcPath).readAsBytesSync();

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

    // Subscribe-first completion map (broadcast-stream race).
    final completions = <int, int>{};
    final importsDone = <int>{};
    final sub = pump.stream.listen((e) {
      if (e.kind == PhotoEventKind.exportComplete) {
        completions[e.requestId] = e.status;
      }
      if (e.kind == PhotoEventKind.importComplete) importsDone.add(e.requestId);
    });
    addTearDown(sub.cancel);

    Future<void> waitFor(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue, reason: 'timed out');
    }

    final importReq = engine.importPath(tmp.path);
    await waitFor(() => importsDone.contains(importReq));
    final assets = engine.listAssets();
    expect(assets, hasLength(1));
    final assetId = assets.single.assetId;
    engine.setStarred(assetId, true);

    // Save in place with a hard desaturation.
    expect(engine.hasInplaceBackup(srcPath), isFalse);
    const spec = 'saturation=-100;';
    expect(engine.setAssetEdits(assetId, spec), greaterThan(0));
    final saveReq =
        engine.saveInPlace(assetId: assetId, srcPath: srcPath, spec: spec);
    if (saveReq == 0) {
      markTestSkipped('dylib built without libvips — in-place save rejected');
      return;
    }
    await waitFor(() => completions.containsKey(saveReq));
    expect(completions[saveReq], 0, reason: 'save-in-place failed');
    expect(engine.hasInplaceBackup(srcPath), isTrue);
    expect(File(srcPath).readAsBytesSync(), isNot(originalBytes),
        reason: 'file must carry the baked edit');
    expect(engine.assetEdits(assetId), isEmpty,
        reason: 'parametric spec must clear after the bake');

    // Rescan: identity + user state survive; the backup dir is not imported.
    final rescanReq = engine.rescan();
    await waitFor(() => importsDone.contains(rescanReq));
    final after = engine.listAssets();
    expect(after, hasLength(1), reason: '.pablo-originals leaked into import');
    expect(after.single.assetId, assetId);
    expect(after.single.starred, isTrue);

    // Revert: byte-identical original restored; backup removed.
    final revertReq = engine.revertInPlace(assetId: assetId, srcPath: srcPath);
    expect(revertReq, greaterThan(0));
    await waitFor(() => completions.containsKey(revertReq));
    expect(completions[revertReq], 0, reason: 'revert-in-place failed');
    expect(File(srcPath).readAsBytesSync(), originalBytes);
    expect(engine.hasInplaceBackup(srcPath), isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
