// Dart-side integration test permuting COMBINATIONS of edits through the
// EditSpec grammar + EditSession — the mirror of the native edit_integration
// test. Verifies the `key=value;` round-trip is stable across geometry + tone +
// colour + filter combinations and that the session tracks them coherently.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/edit_session.dart';
import 'package:pablo/features/editor/edit_spec.dart';
import 'package:pablo/features/editor/edits_store.dart';

typedef Mod = void Function(EditSpec);

final List<MapEntry<String, Mod>> _mods = [
  MapEntry('exposure', (e) => e.exposure = 22),
  MapEntry('contrast', (e) => e.contrast = -18),
  MapEntry('shadows', (e) => e.shadows = 35),
  MapEntry('temp', (e) => e.temperature = -25),
  MapEntry('saturation', (e) => e.saturation = 40),
  MapEntry('vignette', (e) => e.vignette = -30),
  MapEntry('filter', (e) => e.filter = 'vivid'),
  MapEntry('rot90', (e) => e.rot90 = 1),
  MapEntry('flipH', (e) => e.flipH = true),
  MapEntry('straighten', (e) => e.straighten = 7.5),
  MapEntry('crop', (e) {
    e.cropL = 0.1;
    e.cropT = 0.15;
    e.cropW = 0.75;
    e.cropH = 0.7;
  }),
];

List<EditSpec> _permutations() {
  final out = <EditSpec>[];
  for (var i = 0; i < _mods.length; i++) {
    final single = EditSpec();
    _mods[i].value(single);
    out.add(single);
    for (var j = i + 1; j < _mods.length; j++) {
      final pair = EditSpec();
      _mods[i].value(pair);
      _mods[j].value(pair);
      out.add(pair);
    }
  }
  return out;
}

void main() {
  test('every permutation round-trips stably and flags agree', () {
    for (final spec in _permutations()) {
      final s1 = spec.encode();
      final parsed = EditSpec.decode(s1);
      final s2 = parsed.encode();
      expect(s2, s1, reason: 'unstable round-trip: $s1');
      expect(parsed.isIdentity, isFalse, reason: s1);
      expect(parsed.isIdentity, !parsed.hasGeometry && !_hasPixelOps(parsed));
    }
  });

  test('session stays dirty + edited across a permuted sequence (engine-free)',
      () {
    final session = EditSession(
      engine: null,
      assetId: 7,
      path: '/lib/x.jpg',
      saved: EditSpec(),
      contentRev: 0,
    );
    var lastRevision = session.specRevision;
    for (final spec in _permutations()) {
      session.spec = spec.clone();
      session.mutate((_) {}); // bump revision + notify
      expect(session.specRevision, greaterThan(lastRevision));
      lastRevision = session.specRevision;
      expect(session.isDirty, isTrue);
      expect(session.encoded, isNotEmpty);
    }
    // Reset returns to the neutral baseline.
    session.resetAdjustments();
    expect(session.isDirty, isFalse);
    expect(session.spec.isIdentity, isTrue);
  });

  test('geometry actions compose on the session', () {
    final session = EditSession(
      engine: null,
      assetId: 1,
      path: '/lib/g.jpg',
      saved: EditSpec(),
      contentRev: 0,
    );
    session.rotate(1);
    session.rotate(1);
    expect(session.spec.rot90, 2);
    session.rotate(-1);
    expect(session.spec.rot90, 1);
    session.rotate(-1);
    session.rotate(-1); // wraps below 0
    expect(session.spec.rot90, 3);
    session.toggleFlipH();
    expect(session.spec.flipH, isTrue);
    session.setStraighten(-12.5);
    expect(session.spec.straighten, closeTo(-12.5, 1e-6));
    session.setCrop(0.2, 0.2, 0.6, 0.6);
    expect(session.spec.cropW, closeTo(0.6, 1e-6));
    expect(session.spec.hasGeometry, isTrue);
    session.clearCrop();
    expect(session.spec.cropW, 1.0);
    EditsStore.instance.clear(1);
  });
}

// Mirror of the native EditSpec::has_pixel_ops for the flag-agreement check.
bool _hasPixelOps(EditSpec e) {
  bool z(double v) => v.abs() < 1e-6;
  final filterDefault = e.filter.isEmpty || e.filter == 'none';
  return !(filterDefault &&
      z(e.exposure) &&
      z(e.contrast) &&
      z(e.highlights) &&
      z(e.shadows) &&
      z(e.whites) &&
      z(e.blacks) &&
      z(e.clarity) &&
      z(e.dehaze) &&
      z(e.temperature) &&
      z(e.tint) &&
      z(e.vibrance) &&
      z(e.saturation) &&
      z(e.sharpness) &&
      z(e.noise) &&
      z(e.vignette));
}
