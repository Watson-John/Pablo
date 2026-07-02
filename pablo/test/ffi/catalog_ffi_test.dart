// catalog_ffi_test.dart — the cross-FFI end-to-end harness. Unlike the other
// Dart tests (which mock the native side), this drives the REAL libphoto_core
// dynamic library through the `Engine` FFI against a real on-disk catalog.db,
// exercising every Stage-2 surface — import, incremental rescan, albums, smart
// collections, hide (asset + folder), tags, compaction, path rebase, and
// persistence across a reopen — and asserting the catalog state through the
// same FFI reads.
//
// It is GATED on the dylib being loadable: `Engine.open` throws (or the bindings
// fail to resolve) when libphoto_core isn't on the loader path, in which case
// the test marks itself skipped rather than failing. Run it against the
// standalone build, e.g.:
//
//   DYLD_LIBRARY_PATH=build/macos-dev/native/core \
//     ~/flutter/bin/flutter test test/ffi/catalog_ffi_test.dart
//
// (LD_LIBRARY_PATH on Linux; PATH on Windows.) The `Engine` FFI class is pure
// dart:ffi with no Flutter dependency, so this runs as a plain VM test.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/move_service.dart';
import 'package:pablo/data/undo_stack.dart';
import 'package:pablo/utils/asset_id.dart';
import 'package:pablo/utils/image_dims.dart';
import 'package:photo_native/photo_native.dart';

/// Resolve once a [PhotoEvent] matching [pred] is drained by the pump.
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
  test('catalog round-trips through the real FFI', () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    // A small library of (extension-valid) files — the catalog keys off the
    // extension; content is irrelevant to these catalog-level assertions.
    final libDir = '${tmp.path}${sep}lib';
    Directory('$libDir${sep}sub').createSync(recursive: true);
    File('$libDir${sep}a.jpg').writeAsBytesSync(List.filled(8, 1));
    File('$libDir${sep}b.jpg').writeAsBytesSync(List.filled(8, 2));
    File('$libDir${sep}sub${sep}c.png').writeAsBytesSync(List.filled(8, 3));

    EngineConfig cfg(String dbName) => EngineConfig(
          catalogPath: '${tmp.path}$sep$dbName',
          cachePath: '${tmp.path}${sep}cache',
        );

    Engine? engine;
    try {
      engine = Engine.open(cfg('catalog.db'));
    } catch (e) {
      markTestSkipped('libphoto_core not loadable ($e)');
      return;
    }
    if (engine == null) {
      markTestSkipped('Engine.open returned null (no catalog support in lib)');
      return;
    }

    final pump = EventPump(engine)..start();

    // ── Import: all three files are new ──
    final importReq = engine.importPath(libDir);
    expect(importReq, isNonZero);
    final imported = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == importReq);
    expect(imported.importAdded, 3);
    expect(imported.importSkipped, 0);
    expect(engine.listAssets().length, 3);

    final assets = engine.listAssets();
    final aId = assets.firstWhere((a) => a.path.endsWith('a.jpg')).assetId;
    final bId = assets.firstWhere((a) => a.path.endsWith('b.jpg')).assetId;

    // ── Albums: create / add / cover / rename / remove ──
    final album = engine.createAlbum('Trip');
    expect(album, isNonZero);
    engine.addToAlbum(album, aId);
    engine.addToAlbum(album, bId);
    expect(engine.albumMembers(album), [aId, bId]);
    engine.setAlbumCover(album, bId);
    expect(engine.listAlbums().firstWhere((x) => x.id == album).coverAssetId, bId);
    engine.renameAlbum(album, 'Trip 2');
    expect(engine.listAlbums().firstWhere((x) => x.id == album).name, 'Trip 2');
    engine.removeFromAlbum(album, aId);
    expect(engine.albumMembers(album), [bId]);

    // ── Star + smart collections + tags ──
    engine.setStarred(aId, true);
    expect(engine.starredAssets(), contains(aId));
    expect(engine.recentAssets(10).length, greaterThanOrEqualTo(3));
    engine.addTag(aId, 'beach');
    expect(engine.assetTags(aId), ['beach']);

    // ── Stage 9: embedding index + text query + saved searches ──
    final counts0 = engine.embeddingCounts();
    expect(counts0.total, 3);
    expect(counts0.pending, 3); // nothing embedded yet (all assets pending)
    expect(engine.pendingEmbeddingIds().length, 3);

    // A text query embeds via the deterministic model (no ONNX needed).
    final qv = engine.embedText('blue sky');
    expect(qv, isNotEmpty);
    // Ranking over an empty done-set is a safe no-op.
    expect(engine.semanticSearch(qv), isEmpty);

    // Schedule one embed; the terminal EMBED_PROGRESS event fires whether or not
    // a decoder is compiled (done vs skipped) — either way the row is written.
    final embReq = engine.embeddingScan(aId);
    expect(embReq, isNonZero);
    final embDone = await _waitFor(
        pump.stream,
        (e) =>
            e.kind == PhotoEventKind.embedProgress && e.requestId == embReq);
    expect(embDone.assetId, aId);
    expect(engine.embeddingCounts().pending, lessThan(3)); // aId settled

    // Saved searches round-trip through the catalog.
    final ssId = engine.createSavedSearch('Blue skies', '{"text":"blue"}');
    expect(ssId, isNonZero);
    final saved = engine.listSavedSearches();
    expect(
        saved.any((s) =>
            s.name == 'Blue skies' && s.queryJson == '{"text":"blue"}'),
        isTrue);
    engine.deleteSavedSearch(ssId);
    expect(engine.listSavedSearches().any((s) => s.id == ssId), isFalse);
    // A durable one to verify persistence across reopen.
    engine.createSavedSearch('persist', '{}');

    // ── Hide a single asset → excluded from listAssets, surfaced by hiddenAssets ──
    engine.setHidden(bId, true);
    expect(engine.listAssets().length, 2);
    expect(engine.hiddenAssets().any((p) => p.endsWith('b.jpg')), isTrue);
    expect(engine.starredAssets(), contains(aId)); // a still starred + visible

    // ── Hide a whole folder → its photo drops out too ──
    engine.setFolderHidden('$libDir${sep}sub', true);
    expect(engine.hiddenFolders(), contains('$libDir${sep}sub'));
    expect(engine.listAssets().length, 1); // only a.jpg visible

    // ── Incremental rescan: nothing changed on disk → everything skipped ──
    final rescanReq = engine.rescan();
    final rescanned = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == rescanReq);
    expect(rescanned.importAdded, 0);
    expect(rescanned.importUpdated, 0);
    expect(rescanned.importSkipped, 3);

    // ── Compaction (idle lane → maintenance event) ──
    expect(engine.catalogStats(), isNotNull);
    final compactReq = engine.compactCatalog();
    final compacted = await _waitFor(pump.stream,
        (e) =>
            e.kind == PhotoEventKind.maintenanceComplete &&
            e.requestId == compactReq);
    expect(compacted.status, 0);
    expect(engine.catalogStats()!.freelistCount, 0);
    // The synchronous compaction path (used by the on-exit cleanup) also works.
    expect(engine.compactCatalogSync(), 0);

    // ── Relocate: rebase every path to a new root (ids preserved) ──
    final newDir = '${tmp.path}${sep}moved';
    Directory('$newDir${sep}sub').createSync(recursive: true);
    expect(engine.rebaseLibrary(libDir, newDir), 0); // 0 == PHOTO_STATUS_OK
    // Un-hide so listAssets reflects all three; the folder-hide rule moved with
    // the rebase, so it un-hides under the NEW prefix.
    engine.setFolderHidden('$newDir${sep}sub', false);
    engine.setHidden(bId, false);
    final moved = engine.listAssets();
    expect(moved.length, 3);
    expect(moved.every((a) => a.path.startsWith(newDir)), isTrue);
    // The album still resolves the same (rebase-preserved) asset id.
    expect(engine.albumMembers(album), [bId]);

    // ── Persistence: dispose + reopen the on-disk DB ──
    pump.dispose();
    engine.dispose();
    final reopened = Engine.open(cfg('catalog.db'));
    expect(reopened, isNotNull);
    addTearDown(() => reopened!.dispose());
    expect(reopened!.listAssets().length, 3);
    expect(reopened.listAlbums().any((x) => x.name == 'Trip 2'), isTrue);
    expect(reopened.starredAssets().length, 1);
    // Saved searches persist across the reopen (catalog v7).
    expect(reopened.listSavedSearches().any((s) => s.name == 'persist'), isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ── Stage V1: export-with-options through the real render pipeline ──
  // Uses the committed real JPEG fixture (the catalog test's 8-byte files are
  // not decodable, so they can't exercise export). Skips when the dylib has no
  // libvips (exportAsset2 returns 0) or isn't loadable at all.
  test('exportAsset2 resizes + batches through the real FFI', () async {
    final sep = Platform.pathSeparator;
    // Committed fixture, resolved relative to the pablo/ package (test CWD).
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('export fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_export_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final libDir = '${tmp.path}${sep}lib';
    final outDir = '${tmp.path}${sep}out';
    Directory(libDir).createSync(recursive: true);
    Directory(outDir).createSync(recursive: true);
    final srcPath = '$libDir${sep}photo.jpg';
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

    // Record every completion from ONE up-front subscription. The batch below
    // fires all its events before a sequential per-request listener could
    // subscribe (a broadcast stream drops events with no matching listener), so
    // collect into maps and poll instead.
    final exportStatus = <int, int>{};
    final importDone = <int>{};
    final sub = pump.stream.listen((e) {
      if (e.kind == PhotoEventKind.exportComplete) {
        exportStatus[e.requestId] = e.status;
      } else if (e.kind == PhotoEventKind.importComplete) {
        importDone.add(e.requestId);
      }
    });
    addTearDown(sub.cancel);

    Future<void> waitUntil(bool Function() cond,
        {Duration timeout = const Duration(seconds: 20)}) async {
      final deadline = DateTime.now().add(timeout);
      while (!cond() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    final importReq = engine.importPath(libDir);
    await waitUntil(() => importDone.contains(importReq));
    expect(importDone, contains(importReq));
    final assets = engine.listAssets();
    expect(assets, isNotEmpty);

    // Single export downscaled to an 8 px long edge (the fixture is 16x16, so
    // a small cap proves the resize path without needing a large fixture).
    const cap = 8;
    final outPath = '$outDir${sep}resized.jpg';
    final req = engine.exportAsset2(
        srcPath: srcPath, dstPath: outPath, maxDim: cap, quality: 80);
    if (req == 0) {
      markTestSkipped('export unsupported in this build (no libvips)');
      return;
    }
    await waitUntil(() => exportStatus.containsKey(req));
    expect(exportStatus[req], 0);
    expect(File(outPath).existsSync(), isTrue);

    // Read the output's dimensions from its JPEG header (pure Dart — no engine
    // frame pump, which flutter_test's binding doesn't drive) and assert the
    // long edge was bounded.
    final dims = readImageDimensions(outPath);
    expect(dims, isNotNull);
    expect(dims!.width, lessThanOrEqualTo(cap));
    expect(dims.height, lessThanOrEqualTo(cap));
    expect(dims.width == cap || dims.height == cap, isTrue); // long edge hit cap

    // Batch of 3 distinct destinations → 3 completion events.
    final reqs = <int>[];
    for (var i = 0; i < 3; i++) {
      reqs.add(engine.exportAsset2(
          srcPath: srcPath, dstPath: '$outDir${sep}b$i.jpg', quality: 85));
    }
    expect(reqs.every((r) => r != 0), isTrue);
    await waitUntil(() => reqs.every(exportStatus.containsKey));
    for (final r in reqs) {
      expect(exportStatus[r], 0);
    }
    for (var i = 0; i < 3; i++) {
      expect(File('$outDir${sep}b$i.jpg').existsSync(), isTrue);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Stage V3: video import surfaces isVideo + duration through the FFI ──
  test('importing a video exposes isVideo + durationMs', () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}data${sep}tiny.mp4');
    if (!fixture.existsSync()) {
      markTestSkipped('video fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_video_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final libDir = '${tmp.path}${sep}lib';
    Directory(libDir).createSync(recursive: true);
    fixture.copySync('$libDir${sep}clip.mp4');
    // A plain image alongside it so we can assert the flag discriminates.
    File('$libDir${sep}note.jpg').writeAsBytesSync(List.filled(8, 1));

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
      markTestSkipped('Engine.open returned null');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    final req = engine.importPath(libDir);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == req);

    final assets = engine.listAssets();
    final clip = assets.firstWhere((a) => a.path.endsWith('clip.mp4'));
    final note = assets.firstWhere((a) => a.path.endsWith('note.jpg'));
    expect(clip.isVideo, isTrue);
    expect(note.isVideo, isFalse);
    // Duration is filled when the dylib linked FFmpeg; 0 otherwise (still imports).
    if (clip.durationMs > 0) {
      expect(clip.durationMs, closeTo(2000, 300));
      expect(clip.width, 64);
      expect(clip.height, 48);
    }

    // §11 trim round-trips through the catalog FFI (catalog-only, no FFmpeg).
    expect(engine.videoSetTrim(clip.assetId, 500, 1500), isTrue);
    var t = engine.videoGetTrim(clip.assetId);
    expect(t.startMs, 500);
    expect(t.endMs, 1500);
    engine.videoSetTrim(clip.assetId, 0, 0); // clear
    t = engine.videoGetTrim(clip.assetId);
    expect(t.startMs, 0);
    expect(t.endMs, 0);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ── Stage V4: collage compositor through the FFI (needs libvips) ──
  test('createCollage composites and emits an export event', () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('collage fixture missing');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_collage_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final a = '${tmp.path}${sep}a.jpg';
    final b = '${tmp.path}${sep}b.jpg';
    fixture.copySync(a);
    fixture.copySync(b);

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
      markTestSkipped('Engine.open returned null');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    final out = '${tmp.path}${sep}collage.jpg';
    final req = engine.createCollage(
      cells: [
        CollageCell(x: 0.0, y: 0.0, w: 0.5, h: 1.0, src: a),
        CollageCell(x: 0.5, y: 0.0, w: 0.5, h: 1.0, src: b),
      ],
      dstPath: out,
      canvasW: 128,
      canvasH: 64,
    );
    if (req == 0) {
      markTestSkipped('collage unsupported (no libvips)');
      return;
    }
    final done = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.exportComplete && e.requestId == req);
    expect(done.status, 0);
    expect(File(out).existsSync(), isTrue);
    final dims = readImageDimensions(out);
    expect(dims, isNotNull);
    expect(dims!.width, 128);
    expect(dims.height, 64);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('relocateAssets keeps ids attached and rescan is churn-free', () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_reloc_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final libDir = '${tmp.path}${sep}lib';
    Directory('$libDir${sep}inbox').createSync(recursive: true);
    File('$libDir${sep}inbox${sep}one.jpg').writeAsBytesSync(List.filled(8, 1));
    File('$libDir${sep}inbox${sep}two.jpg').writeAsBytesSync(List.filled(8, 2));

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
      markTestSkipped('Engine.open returned null (no catalog support in lib)');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    final importReq = engine.importPath(libDir);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == importReq);
    final assets = engine.listAssets();
    expect(assets.length, 2);
    final oneId = assets.firstWhere((a) => a.path.endsWith('one.jpg')).assetId;
    final twoPath = assets.firstWhere((a) => a.path.endsWith('two.jpg')).path;
    engine.setStarred(oneId, true);

    // Move the file on disk (what MoveService will do), then relocate the row.
    final destDir = '$libDir${sep}sorted';
    Directory(destDir).createSync(recursive: true);
    final dest = '$destDir${sep}one.jpg';
    File('$libDir${sep}inbox${sep}one.jpg').renameSync(dest);

    // Mixed batch: one clean move, one collision (onto two.jpg's path).
    final outcome = engine.relocateAssets([
      (oneId, dest),
      (oneId, twoPath), // collides with a different asset — must be skipped
    ]);
    expect(outcome.applied, 1);
    expect(outcome.okByIndex, [true, false]);

    // The catalog row followed the file: same id, new path, star intact.
    final after = engine.listAssets();
    final moved = after.firstWhere((a) => a.assetId == oneId);
    expect(moved.path, dest);
    expect(engine.starredAssets(), contains(oneId));

    // Rescan sees nothing to do — no add/remove churn for the moved file.
    final rescanReq = engine.rescan();
    final rescanned = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == rescanReq);
    expect(rescanned.importAdded, 0);
    expect(rescanned.importRemoved, 0);
    expect(rescanned.importSkipped, 2);
    expect(engine.listAssets().length, 2);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('MoveService end-to-end: disk + catalog + id maps stay convergent',
      () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_movesvc_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final libDir = '${tmp.path}${sep}lib';
    Directory('$libDir${sep}inbox').createSync(recursive: true);
    final srcPath = '$libDir${sep}inbox${sep}a.jpg';
    File(srcPath).writeAsBytesSync(List.filled(8, 1));
    File('$srcPath.xmp').writeAsStringSync('<xmp/>');

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
      markTestSkipped('Engine.open returned null (no catalog support in lib)');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    final importReq = engine.importPath(libDir);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == importReq);
    final asset = engine.listAssets().single;
    engine.setStarred(asset.assetId, true);
    // The app hydrates this map after import (library_import.dart); mirror it.
    hydrateCatalogIds({asset.path: asset.assetId});

    final destDir = '$libDir${sep}sorted';
    final undo = UndoStack();
    final out =
        MoveService.moveInto([srcPath], destDir, engine: engine, undo: undo);
    expect(out.movedCount, 1);
    final newPath = '$destDir${sep}a.jpg';
    expect(File(newPath).existsSync(), isTrue);
    expect(File('$newPath.xmp').existsSync(), isTrue, reason: 'sidecar moved');

    // Catalog followed: same id at the new path; star intact; id map remapped.
    final row = engine.listAssets().single;
    expect(row.assetId, asset.assetId);
    expect(row.path, newPath);
    expect(engine.starredAssets(), contains(asset.assetId));
    expect(assetIdFor(newPath), asset.assetId);
    expect(pathForAssetId(asset.assetId), newPath);

    // Rescan is churn-free after the coordinated move.
    final rescanReq = engine.rescan();
    final rescanned = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == rescanReq);
    expect(rescanned.importAdded, 0);
    expect(rescanned.importRemoved, 0);

    // Undo restores everything, including the catalog row and the id map.
    MoveService.undoOp(undo.pop()!, engine: engine);
    expect(File(srcPath).existsSync(), isTrue);
    expect(File('$srcPath.xmp').existsSync(), isTrue);
    expect(engine.listAssets().single.path, srcPath);
    expect(engine.listAssets().single.assetId, asset.assetId);
    expect(pathForAssetId(asset.assetId), srcPath);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('folder rename via rebaseLibrary preserves ids for all descendants',
      () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_rename_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final libDir = '${tmp.path}${sep}lib';
    final oldFolder = '$libDir${sep}2024';
    Directory(oldFolder).createSync(recursive: true);
    File('$oldFolder${sep}a.jpg').writeAsBytesSync(List.filled(8, 1));
    File('$oldFolder${sep}b.jpg').writeAsBytesSync(List.filled(8, 2));

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
      markTestSkipped('Engine.open returned null (no catalog support in lib)');
      return;
    }
    addTearDown(engine.dispose);
    final pump = EventPump(engine)..start();
    addTearDown(pump.dispose);

    final importReq = engine.importPath(libDir);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == importReq);
    final before = {for (final a in engine.listAssets()) a.path: a.assetId};
    expect(before.length, 2);

    // Rename on disk, then rebase the catalog (what folder_ops.renameFolder does).
    final newFolder = '$libDir${sep}Trip 2024';
    Directory(oldFolder).renameSync(newFolder);
    expect(engine.rebaseLibrary(oldFolder, newFolder), 0);

    final after = {for (final a in engine.listAssets()) a.path: a.assetId};
    expect(after['$newFolder${sep}a.jpg'], before['$oldFolder${sep}a.jpg']);
    expect(after['$newFolder${sep}b.jpg'], before['$oldFolder${sep}b.jpg']);

    // Rescan is churn-free: the rebased rows match the moved files.
    final rescanReq = engine.rescan();
    final rescanned = await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == rescanReq);
    expect(rescanned.importAdded, 0);
    expect(rescanned.importRemoved, 0);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
