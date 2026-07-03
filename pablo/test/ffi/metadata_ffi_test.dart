// metadata_ffi_test.dart — parity between the TWO EXIF sources: the native
// catalog (libexif on import → Engine.assetMetadata, the primary path for
// Library.exifFor) and the pure-Dart fallback parser (utils/exif.dart). If
// libexif and the Dart parser disagree on a field, the info panel silently
// changes depending on whether an asset is imported — this test pins the
// shared fields against the committed fixture (exif_full.jpg, whose ground
// truth lives in exif_full.golden.json).
//
// Gated like the other test/ffi files: skips when libphoto_core isn't
// loadable (PHOTO_CORE_LIB=<abs dylib path>) or was built without libexif.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/exif.dart';
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
  test('catalog metadata matches the Dart fallback parser on the fixture',
      () async {
    final sep = Platform.pathSeparator;
    final fixture = File(
        '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped('fixture missing (${fixture.path})');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_meta_');
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

    final req = engine.importPath(tmp.path);
    await _waitFor(pump.stream,
        (e) => e.kind == PhotoEventKind.importComplete && e.requestId == req);
    final assets = engine.listAssets();
    expect(assets, hasLength(1));

    final meta = engine.assetMetadata(assets.single.assetId);
    if (meta == null || meta.camera.isEmpty) {
      markTestSkipped('dylib built without libexif — no metadata row');
      return;
    }
    final dart = readExif(srcPath);
    expect(dart, isNotNull, reason: 'Dart parser failed on the fixture');

    // Ground truth from exif_full.golden.json: Make "TestMake", Model
    // "PabloCam 100", ISO 400, f/2.8, 1/250s, 50mm, GPS 37.7749/-122.4194,
    // DateTimeOriginal 2021:07:15 12:30:45.
    expect(meta.camera, 'TestMake PabloCam 100');
    expect(dart!.make, 'TestMake');
    expect(dart.model, 'PabloCam 100');

    expect(meta.iso, 400);
    expect(dart.iso, 400);

    // Native strings are libexif display-formatted; assert the numeric core
    // so formatting tweaks don't break parity semantics.
    expect(meta.aperture, contains('2.8'));
    expect(dart.fNumber, closeTo(2.8, 0.001));
    expect(meta.focal, contains('50'));
    expect(dart.focalLength, closeTo(50, 0.001));

    // Capture date: same instant from both parsers.
    expect(meta.captureDate, isNotNull);
    expect(dart.dateTimeOriginal, isNotNull);
    expect(meta.captureDate, dart.dateTimeOriginal);
    expect(meta.captureDate!.year, 2021);
    expect(meta.captureDate!.month, 7);
    expect(meta.captureDate!.day, 15);

    // GPS: west longitude must come out negative on BOTH sides (sign handling
    // is the classic divergence bug).
    expect(meta.hasGps, isTrue);
    expect(meta.gpsLat!, closeTo(37.7749, 0.0005));
    expect(meta.gpsLon!, closeTo(-122.4194, 0.0005));
    expect(dart.gpsLat!, closeTo(37.7749, 0.0005));
    expect(dart.gpsLon!, closeTo(-122.4194, 0.0005));

    // Orientation tag (6 = rotate 90 CW) reaches the catalog row.
    expect(meta.orientation, 6);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
