// edit_spec_parity_ffi_test.dart — property-style spec round-trip through the
// REAL dylib. The Dart EditSpec grammar (lib/features/editor/edit_spec.dart)
// and the native one (native/core/src/edit/edit_spec.cpp) are hand-mirrored;
// this test pins the cross-language canonical-form invariant end to end:
//
//   Dart encode → photo_asset_set_edits (native parse + canonical re-serialize
//   into the catalog) → photo_asset_get_edits → Dart decode → Dart re-encode
//   must equal the original Dart encoding, for specs covering EVERY field
//   family (tone, colour, detail, filter, geometry, retouch, curves, text).
//
// It also pins that content_rev is strictly monotonic across a save sequence
// and that an identity spec clears the edit (rev → 0).
//
// Gated like the other test/ffi files: skips (never fails) when libphoto_core
// isn't loadable. Run with:
//
//   PHOTO_CORE_LIB=<abs path to libphoto_core.dylib> \
//     flutter test test/ffi/edit_spec_parity_ffi_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/edit_spec.dart';
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

typedef _Mod = void Function(EditSpec);

// One mutation per spec field family member (the edit_permute_test generator
// style, widened to cover the whole grammar). Values stay within 4 decimal
// places so the native float/%.4f canonical form reproduces them exactly.
final List<MapEntry<String, _Mod>> _mods = [
  // Tone (Light).
  MapEntry('exposure', (e) => e.exposure = 22),
  MapEntry('contrast', (e) => e.contrast = -18),
  MapEntry('highlights', (e) => e.highlights = -40),
  MapEntry('shadows', (e) => e.shadows = 35),
  MapEntry('whites', (e) => e.whites = 12),
  MapEntry('blacks', (e) => e.blacks = -8.5),
  MapEntry('clarity', (e) => e.clarity = 15),
  MapEntry('dehaze', (e) => e.dehaze = 10),
  MapEntry('autofix', (e) => e.autoFix = true),
  // Colour.
  MapEntry('temp', (e) => e.temperature = -25),
  MapEntry('tint', (e) => e.tint = 18),
  MapEntry('vibrance', (e) => e.vibrance = 30),
  MapEntry('saturation', (e) => e.saturation = 40),
  // Detail.
  MapEntry('sharpness', (e) => e.sharpness = 55),
  MapEntry('noise', (e) => e.noise = 20),
  MapEntry('vignette', (e) => e.vignette = -30),
  // Filter preset.
  MapEntry('filter', (e) => e.filter = 'vivid'),
  // Geometry.
  MapEntry('rot90', (e) => e.rot90 = 1),
  MapEntry('flipH', (e) => e.flipH = true),
  MapEntry('flipV', (e) => e.flipV = true),
  MapEntry('straighten', (e) => e.straighten = 7.5),
  MapEntry('crop', (e) {
    e.cropL = 0.1;
    e.cropT = 0.15;
    e.cropW = 0.75;
    e.cropH = 0.7;
  }),
  // Retouch dabs (normalized, float-safe coords).
  MapEntry('redeye', (e) => e.redeye = [EditRegion(x: 0.3, y: 0.4, r: 0.05)]),
  MapEntry('heal', (e) {
    e.heal = [
      EditRegion(x: 0.25, y: 0.35, r: 0.03),
      EditRegion(x: 0.7, y: 0.6, r: 0.08),
    ];
  }),
  // Master tone curve (off-diagonal → non-identity).
  MapEntry('curves', (e) {
    e.curve = const [
      Offset(0, 0),
      Offset(0.25, 0.4),
      Offset(0.75, 0.6),
      Offset(1, 1),
    ];
  }),
  // Text overlays, incl. every grammar delimiter + non-ASCII in the payload.
  MapEntry('text', (e) {
    e.texts = [
      TextOverlay(x: 0.5, y: 0.9, size: 0.08, color: 0xC17A3A, text: 'Héllo'),
      TextOverlay(
          x: 0.2, y: 0.1, size: 0.05, color: 0x2563EB, text: 'a=b;c,d|e%f'),
    ];
  }),
];

/// ~30 specs: one per mod (every field family alone) + multi-family combos.
List<EditSpec> _specs() {
  EditSpec combo(List<String> names) {
    final e = EditSpec();
    for (final n in names) {
      _mods.firstWhere((m) => m.key == n).value(e);
    }
    return e;
  }

  return [
    for (final m in _mods) combo([m.key]),
    // Whole-panel combos.
    combo(['exposure', 'contrast', 'shadows', 'whites', 'clarity', 'dehaze']),
    combo(['temp', 'tint', 'vibrance', 'saturation']),
    combo(['rot90', 'flipH', 'flipV', 'straighten', 'crop']),
    combo(['redeye', 'heal', 'curves', 'text']),
    // Kitchen sink: at least one field from every family at once.
    combo([
      'exposure', 'blacks', 'autofix', 'temp', 'saturation', 'sharpness',
      'vignette', 'filter', 'rot90', 'flipH', 'straighten', 'crop',
      'redeye', 'heal', 'curves', 'text', //
    ]),
  ];
}

void main() {
  test('edit specs round-trip canonically through the real FFI '
      'and content_rev is strictly monotonic', () async {
    final sep = Platform.pathSeparator;
    final tmp = Directory.systemTemp.createTempSync('pablo_ffi_editspec_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    // An extension-valid fake photo is enough: set/get edits is catalog-only,
    // no decode happens until something renders.
    final libDir = '${tmp.path}${sep}lib';
    Directory(libDir).createSync(recursive: true);
    File('$libDir${sep}a.jpg').writeAsBytesSync(List.filled(8, 1));

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
    await _waitFor(
        pump.stream,
        (e) =>
            e.kind == PhotoEventKind.importComplete &&
            e.requestId == importReq);
    final assets = engine.listAssets();
    expect(assets, hasLength(1));
    final assetId = assets.single.assetId;
    expect(engine.assetContentRev(assetId), 0); // unedited

    final specs = _specs();
    expect(specs.length, greaterThanOrEqualTo(30));
    var lastRev = 0;
    for (final spec in specs) {
      final encoded = spec.encode();
      expect(spec.isIdentity, isFalse, reason: 'generator bug: $encoded');
      expect(encoded, isNotEmpty);

      // Persist: native parses the Dart encoding and stores its own canonical
      // re-serialization, returning the bumped content_rev.
      final rev = engine.setAssetEdits(assetId, encoded);
      expect(rev, greaterThan(lastRev),
          reason: 'content_rev not strictly monotonic for: $encoded');
      lastRev = rev;
      expect(engine.assetContentRev(assetId), rev);

      // Read back: the native canonical form must decode (in Dart) to a spec
      // whose re-encoding equals the original Dart encoding byte-for-byte —
      // the cross-language canonical-form invariant.
      final back = engine.assetEdits(assetId);
      expect(back, isNotEmpty);
      final roundTripped = EditSpec.decode(back).encode();
      expect(roundTripped, encoded,
          reason: 'canonical-form drift: native returned "$back"');
    }

    // An identity spec is a revert: rev collapses to 0 and the edit clears.
    expect(engine.setAssetEdits(assetId, EditSpec().encode()), 0);
    expect(engine.assetContentRev(assetId), 0);
    expect(engine.assetEdits(assetId), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
