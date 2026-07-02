// ModelFetcher: fresh download + sha256 verify, corruption rejection (with
// the .part kept for resume), Range resume, restart when Range is ignored,
// and skip-when-present — all against a local HttpServer fixture.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/model_fetcher.dart';

void main() {
  late HttpServer server;
  late Directory tmp;
  late Map<String, List<int>> assets;
  late List<String> hits; // every asset request served
  late List<String?> rangeHeaders; // the Range header of each hit (or null)
  var serveRanges = true;

  final payload =
      List<int>.generate(96 * 1024 + 17, (i) => (i * 31 + 7) & 0xff);

  ModelSpec spec({String? sha}) => ModelSpec(
        assetName: 'model.bin',
        destName: 'model.onnx',
        sha256: sha ?? sha256.convert(payload).toString(),
        bytes: payload.length,
      );

  ModelFetcher fetcher(List<ModelSpec> specs) => ModelFetcher(
        baseUrl: 'http://${server.address.address}:${server.port}',
        specs: specs,
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('model_fetcher_test');
    assets = {};
    hits = [];
    rangeHeaders = [];
    serveRanges = true;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      final data = assets[name];
      final resp = req.response;
      if (data == null) {
        resp.statusCode = HttpStatus.notFound;
        await resp.close();
        return;
      }
      hits.add(name);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      rangeHeaders.add(range);
      if (range != null && serveRanges) {
        final start =
            int.parse(range.substring('bytes='.length, range.length - 1));
        if (start >= data.length) {
          resp.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        } else {
          resp.statusCode = HttpStatus.partialContent;
          resp.contentLength = data.length - start;
          resp.add(data.sublist(start));
        }
      } else {
        resp.contentLength = data.length;
        resp.add(data);
      }
      await resp.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  test('fresh download verifies sha256 and renames the .part into place',
      () async {
    assets['model.bin'] = payload;
    final events = <(String, int, int)>[];
    await fetcher([spec()])
        .ensureModels(tmp, onProgress: (f, r, t) => events.add((f, r, t)));
    expect(File('${tmp.path}/model.onnx').readAsBytesSync(), payload);
    expect(File('${tmp.path}/model.onnx.part').existsSync(), isFalse);
    expect(events, isNotEmpty);
    expect(events.last.$1, 'model.onnx');
    expect(events.last.$2, payload.length);
    expect(events.last.$3, payload.length);
  });

  test('sha256 mismatch throws and keeps the .part for a later resume',
      () async {
    assets['model.bin'] = payload;
    final bad = spec(sha: 'deadbeef' * 8);
    await expectLater(
      fetcher([bad]).ensureModels(tmp),
      throwsA(isA<ModelFetchException>()
          .having((e) => e.message, 'message', contains('mismatch'))),
    );
    expect(File('${tmp.path}/model.onnx').existsSync(), isFalse);
    expect(File('${tmp.path}/model.onnx.part').existsSync(), isTrue);
  });

  test('resumes an existing .part with a Range request and still verifies',
      () async {
    assets['model.bin'] = payload;
    File('${tmp.path}/model.onnx.part')
        .writeAsBytesSync(payload.sublist(0, 4096));
    final events = <(String, int, int)>[];
    await fetcher([spec()])
        .ensureModels(tmp, onProgress: (f, r, t) => events.add((f, r, t)));
    expect(rangeHeaders, contains('bytes=4096-'));
    expect(File('${tmp.path}/model.onnx').readAsBytesSync(), payload);
    // Progress counts the resumed prefix.
    expect(events.first.$2, greaterThanOrEqualTo(4096));
    expect(events.last.$3, payload.length);
  });

  test('restarts from scratch when the server ignores Range', () async {
    serveRanges = false;
    assets['model.bin'] = payload;
    // A stale prefix that does NOT match the payload — appending would
    // corrupt; a 200 response must truncate and rewrite.
    File('${tmp.path}/model.onnx.part')
        .writeAsBytesSync(List<int>.filled(2048, 0xab));
    await fetcher([spec()]).ensureModels(tmp);
    expect(File('${tmp.path}/model.onnx').readAsBytesSync(), payload);
  });

  test('a corrupt completed .part self-heals on the next attempt', () async {
    assets['model.bin'] = payload;
    // Wrong prefix → the resumed download completes but fails verification.
    File('${tmp.path}/model.onnx.part')
        .writeAsBytesSync(List<int>.filled(4096, 0xcd));
    final f = fetcher([spec()]);
    await expectLater(f.ensureModels(tmp), throwsA(isA<ModelFetchException>()));
    // Retry: Range now points past EOF → 416 → clean restart → verified.
    await f.ensureModels(tmp);
    expect(File('${tmp.path}/model.onnx').readAsBytesSync(), payload);
  });

  test('skips files already present with a matching sha256', () async {
    assets['model.bin'] = payload;
    File('${tmp.path}/model.onnx').writeAsBytesSync(payload);
    await fetcher([spec()]).ensureModels(tmp);
    expect(hits, isEmpty);
  });

  test('a PENDING sha256 skips any non-empty existing file', () async {
    assets['model.bin'] = payload;
    File('${tmp.path}/model.onnx').writeAsBytesSync(const [1, 2, 3]);
    final pending = ModelSpec(
      assetName: 'model.bin',
      destName: 'model.onnx',
      sha256: 'PENDING',
      bytes: 10,
    );
    await fetcher([pending]).ensureModels(tmp);
    expect(hits, isEmpty);
    expect(File('${tmp.path}/model.onnx').lengthSync(), 3);
  });

  test('missing() reports absent files and empties after a download', () async {
    assets['model.bin'] = payload;
    final f = fetcher([spec()]);
    expect((await f.missing(tmp)).map((s) => s.destName), ['model.onnx']);
    await f.ensureModels(tmp);
    expect(await f.missing(tmp), isEmpty);
  });

  test('a missing release asset surfaces a clear HTTP error', () async {
    await expectLater(
      fetcher([spec()]).ensureModels(tmp),
      throwsA(isA<ModelFetchException>()
          .having((e) => e.message, 'message', contains('404'))),
    );
  });
}
