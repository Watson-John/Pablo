// organize_ffi_test.dart — the §5 Organize & metadata seam end-to-end through
// the REAL libphoto_core dylib (not a mock). catalog_ffi_test.dart already
// covers star + tags + smart collections; this focuses on the readback paths
// that one omits: numeric rating and caption round-tripped through the
// `organize()` getter, the assetTags grow-and-recall buffer past its initial
// capacity, null on unknown assets, and persistence of all three across a
// dispose + reopen.
//
// GATED on the dylib being loadable: if libphoto_core isn't on the loader path
// the test marks itself skipped rather than failing. Run it against a
// standalone build, e.g.:
//
//   DYLD_LIBRARY_PATH=build/macos-dev/native/core \
//     ~/flutter/bin/flutter test test/ffi/organize_ffi_test.dart
//
// (LD_LIBRARY_PATH on Linux; PATH on Windows.)

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  test('organize state round-trips + persists through the real FFI', () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_org_ffi_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final libDir = '${tmp.path}${sep}lib';
    Directory(libDir).createSync(recursive: true);
    File('$libDir${sep}a.jpg').writeAsBytesSync(List.filled(8, 1));
    File('$libDir${sep}b.jpg').writeAsBytesSync(List.filled(8, 2));

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

    // ── Import the two files ──
    final req = engine.importPath(libDir);
    expect(req, isNonZero);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == req);
    final assets = engine.listAssets();
    expect(assets.length, 2);
    final aId = assets.firstWhere((a) => a.path.endsWith('a.jpg')).assetId;
    final bId = assets.firstWhere((a) => a.path.endsWith('b.jpg')).assetId;

    // ── Star + rating + caption set, then read back via organize() ──
    expect(engine.setStarred(aId, true), 0);
    expect(engine.setRating(aId, 4), 0);
    expect(engine.setCaption(aId, 'golden hour — café'), 0);

    final org = engine.organize(aId);
    expect(org, isNotNull);
    expect(org!.starred, isTrue);
    expect(org.rating, 4);
    expect(org.caption, 'golden hour — café'); // UTF-8 survives the C boundary

    // b is untouched: default unstarred / rating 0 / empty caption.
    final orgB = engine.organize(bId);
    expect(orgB, isNotNull);
    expect(orgB!.starred, isFalse);
    expect(orgB.rating, 0);
    expect(orgB.caption, isEmpty);

    // ── organize() on an unknown asset id is null ──
    expect(engine.organize(999999), isNull);

    // ── re-rate / clear caption mutate in place ──
    expect(engine.setRating(aId, 2), 0);
    expect(engine.setCaption(aId, ''), 0);
    final org2 = engine.organize(aId);
    expect(org2!.rating, 2);
    expect(org2.caption, isEmpty);
    expect(org2.starred, isTrue); // unchanged

    // ── assetTags must grow past its initial buffer for many/long tags ──
    final manyTags = [for (var i = 0; i < 40; i++) 'tag-${i.toString().padLeft(3, '0')}'];
    for (final t in manyTags) {
      expect(engine.addTag(aId, t), 0);
    }
    final got = engine.assetTags(aId);
    expect(got.length, manyTags.length);
    expect(got, manyTags); // catalog returns them sorted; manyTags is already sorted
    expect(engine.removeTag(aId, manyTags.first), 0);
    expect(engine.assetTags(aId).contains(manyTags.first), isFalse);

    // ── Persistence: dispose + reopen, organize state survives ──
    pump.dispose();
    engine.dispose();
    final reopened = Engine.open(cfg('catalog.db'));
    expect(reopened, isNotNull);
    addTearDown(() => reopened!.dispose());

    final persisted = reopened!.organize(aId);
    expect(persisted, isNotNull);
    expect(persisted!.starred, isTrue);
    expect(persisted.rating, 2);
    expect(persisted.caption, isEmpty);
    expect(reopened.assetTags(aId).length, manyTags.length - 1);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
