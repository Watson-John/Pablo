// dedup_similar_ffi_test.dart — photo_dedup_similar through the real dylib:
// import two byte-identical copies of a photo + one unrelated image, embed all
// three (the engine's semantic embedder — deterministic colour model in the
// standalone build, SigLIP2 when models are present; identical bytes give an
// identical vector either way), then ask for similar pairs at a near-exact
// threshold: exactly the copy-pair must come back.
//
// Gated like the other test/ffi files (PHOTO_CORE_LIB; skips when the dylib
// isn't loadable or the build can't decode → embeddings skip).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_native/photo_native.dart';

/// 1x1 blue PNG — a decodable "unrelated image" distractor.
final _tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/'
    'HwADBwIAMCbHYQAAAABJRU5ErkJggg==');

void main() {
  test('dedupSimilar pairs byte-identical copies, not the unrelated image',
      () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_dedup_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    fixture.copySync('${tmp.path}${sep}copy_one.jpg');
    fixture.copySync('${tmp.path}${sep}copy_two.jpg');
    File('${tmp.path}${sep}other.png').writeAsBytesSync(_tinyPng);

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

    // Import, then embed all three (subscribe-first completion map — fast
    // events on a broadcast stream must not be lost).
    final embedded = <int>{};
    final sub = pump.stream.listen((e) {
      if (e.kind == PhotoEventKind.embedProgress) embedded.add(e.assetId);
    });
    addTearDown(sub.cancel);

    final importDone = Completer<void>();
    final importSub = pump.stream.listen((e) {
      if (e.kind == PhotoEventKind.importComplete &&
          !importDone.isCompleted) {
        importDone.complete();
      }
    });
    addTearDown(importSub.cancel);
    engine.importPath(tmp.path);
    await importDone.future.timeout(const Duration(seconds: 20));

    final assets = engine.listAssets();
    expect(assets, hasLength(3));
    final byName = {
      for (final a in assets)
        a.path.split(Platform.pathSeparator).last: a.assetId,
    };

    for (final a in assets) {
      engine.embeddingScan(a.assetId);
    }
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (embedded.length < 3 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final counts = engine.embeddingCounts();
    if (counts.done < 2) {
      markTestSkipped('build cannot decode/embed (done=${counts.done}) — '
          'similarity needs embeddings');
      return;
    }

    // Near-exact threshold: byte-identical copies share a vector (cos ~1.0);
    // the unrelated image must not reach 0.999 against a real photo.
    final pairs = engine.dedupSimilar(assets.map((a) => a.assetId).toList(), 0.999);
    expect(pairs, hasLength(1), reason: 'exactly the copy-pair expected');
    final got = {pairs.single.a, pairs.single.b};
    expect(got, {byName['copy_one.jpg'], byName['copy_two.jpg']});
    expect(pairs.single.score, greaterThan(0.999));
  }, timeout: const Timeout(Duration(seconds: 90)));
}
