// Unit tests for the Dart EditSpec mirror — encode/decode round-trip + identity.
// The grammar must match native/core/src/edit/edit_spec so a Dart-authored spec
// renders identically when sent to previewEdits / setAssetEdits.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/edit_spec.dart';

void main() {
  test('identity encodes to empty and is detected', () {
    final e = EditSpec();
    expect(e.isIdentity, isTrue);
    expect(e.encode(), isEmpty);

    final f = EditSpec(filter: 'none');
    expect(f.isIdentity, isTrue);
  });

  test('round-trips tone + colour + filter', () {
    final e = EditSpec(
      exposure: 20,
      contrast: -10.5,
      saturation: 35,
      vignette: -40,
      sharpness: 60,
      filter: 'vivid',
    );
    final s = e.encode();
    final r = EditSpec.decode(s);
    expect(r.exposure, closeTo(20, 1e-3));
    expect(r.contrast, closeTo(-10.5, 1e-3));
    expect(r.saturation, closeTo(35, 1e-3));
    expect(r.vignette, closeTo(-40, 1e-3));
    expect(r.sharpness, closeTo(60, 1e-3));
    expect(r.filter, 'vivid');
    expect(r.isIdentity, isFalse);
  });

  test('round-trips geometry', () {
    final e = EditSpec(
      rot90: 1,
      flipH: true,
      cropL: 0.1,
      cropT: 0.1,
      cropW: 0.8,
      cropH: 0.8,
    );
    expect(e.hasGeometry, isTrue);
    final r = EditSpec.decode(e.encode());
    expect(r.rot90, 1);
    expect(r.flipH, isTrue);
    expect(r.flipV, isFalse);
    expect(r.cropW, closeTo(0.8, 1e-3));
  });

  test('decode ignores unknown keys and malformed tokens', () {
    final r = EditSpec.decode('exposure=15;bogus=42;filter=warm;junk;');
    expect(r.exposure, closeTo(15, 1e-3));
    expect(r.filter, 'warm');
  });

  test('autofix round-trips and is non-identity', () {
    final e = EditSpec(autoFix: true);
    expect(e.isIdentity, isFalse);
    expect(e.encode(), contains('autofix=1'));
    final r = EditSpec.decode(e.encode());
    expect(r.autoFix, isTrue);
  });

  test('curve round-trips and identity-diagonal is no-op', () {
    final id = EditSpec(curve: [const Offset(0, 0), const Offset(1, 1)]);
    expect(id.curveIsIdentity, isTrue);
    expect(id.encode(), isEmpty);

    final e = EditSpec(curve: [
      const Offset(0, 0),
      const Offset(0.5, 0.25),
      const Offset(1, 1),
    ]);
    expect(e.isIdentity, isFalse);
    expect(e.encode(), contains('curves='));
    final r = EditSpec.decode(e.encode());
    expect(r.curve.length, 3);
    expect(r.curve[1].dy, closeTo(0.25, 1e-3));
    expect(r.encode(), e.encode());
  });

  test('text overlay round-trips with escaped delimiters', () {
    final e = EditSpec(texts: [
      TextOverlay(x: 0.25, y: 0.8, size: 0.1, color: 0xFF8800, text: 'a;b=c,d|e'),
    ]);
    expect(e.isIdentity, isFalse);
    final r = EditSpec.decode(e.encode());
    expect(r.texts.length, 1);
    expect(r.texts[0].text, 'a;b=c,d|e');
    expect(r.texts[0].color, 0xFF8800);
    expect(r.texts[0].x, closeTo(0.25, 1e-3));
    expect(r.encode(), e.encode());
  });

  test('redeye + heal regions round-trip and are non-identity', () {
    final e = EditSpec(
      redeye: [EditRegion(x: 0.4, y: 0.55, r: 0.03)],
      heal: [
        EditRegion(x: 0.2, y: 0.8, r: 0.05),
        EditRegion(x: 0.6, y: 0.1, r: 0.02),
      ],
    );
    expect(e.isIdentity, isFalse);
    final s = e.encode();
    expect(s, contains('redeye='));
    expect(s, contains('heal='));
    final r = EditSpec.decode(s);
    expect(r.redeye.length, 1);
    expect(r.heal.length, 2);
    expect(r.redeye[0].x, closeTo(0.4, 1e-3));
    expect(r.redeye[0].r, closeTo(0.03, 1e-3));
    expect(r.heal[1].x, closeTo(0.6, 1e-3));
    expect(r.heal[1].r, closeTo(0.02, 1e-3));
    expect(r.encode(), s); // stable round-trip
  });

  test('reset clears retouch regions', () {
    final e = EditSpec(
      redeye: [EditRegion(x: 0.5, y: 0.5, r: 0.04)],
      heal: [EditRegion(x: 0.3, y: 0.3, r: 0.04)],
    );
    e.reset();
    expect(e.redeye, isEmpty);
    expect(e.heal, isEmpty);
    expect(e.isIdentity, isTrue);
  });

  test('decode rejects non-finite numbers (parity with native to_double)', () {
    // Native strtod+isfinite rejects inf/nan/Infinity; Dart double.tryParse
    // ADMITS "Infinity"/"NaN", so the mirror must guard on isFinite or a
    // corrupt spec would poison the render math and diverge from native.
    final r = EditSpec.decode(
        'exposure=inf;contrast=nan;shadows=-infinity;whites=Infinity;'
        'blacks=NaN;clarity=12abc;dehaze=5');
    expect(r.exposure, 0);
    expect(r.contrast, 0);
    expect(r.shadows, 0);
    expect(r.whites, 0); // the "Infinity" admission bug — must fall back to 0
    expect(r.blacks, 0);
    expect(r.clarity, 0); // trailing garbage rejected
    expect(r.dehaze, closeTo(5, 1e-3)); // the one well-formed value survives
    // Non-finite must not leak into geometry / regions / curve / text either.
    final g = EditSpec.decode('crop=0.1,Infinity,0.8,0.7;'
        'redeye=NaN,0.5,0.04;curves=0,0|Infinity,0.5|1,1');
    expect(g.cropT, 0); // Infinity → field default (0), not admitted
    expect(g.cropW, closeTo(0.8, 1e-3));
    expect(g.redeye.single.x, closeTo(0.5, 1e-3)); // NaN x → default 0.5
    expect(g.curve[1].dx, 0); // Infinity → 0
  });

  test('decode tolerates a crop with fewer than 4 fields (native parity)', () {
    // Native tolerates <4 crop fields by keeping each field's default; Dart
    // previously required EXACTLY 4 and dropped the whole crop otherwise.
    final r = EditSpec.decode('crop=0.1,0.2');
    expect(r.cropL, closeTo(0.1, 1e-3));
    expect(r.cropT, closeTo(0.2, 1e-3));
    expect(r.cropW, closeTo(1, 1e-3)); // default kept
    expect(r.cropH, closeTo(1, 1e-3)); // default kept

    final one = EditSpec.decode('crop=0.25');
    expect(one.cropL, closeTo(0.25, 1e-3));
    expect(one.cropW, closeTo(1, 1e-3));
  });

  test('cross-language golden parity (identical literal to native)', () {
    // The EXACT same literal is asserted in native/core/tests/edit_test.cpp
    // (EditSpec.CrossLanguageGoldenParity). preview==saved depends on the two
    // encoders being byte-identical, so drift on either side breaks one side.
    const golden = 'rot=1;fliph=1;straighten=7.5;crop=0.1,0.2,0.7,0.6;'
        'exposure=20;contrast=-10.5;temp=15;vignette=-30;autofix=1;'
        'curves=0,0|0.5,0.25|1,1;text=0.25,0.8,0.1,FF8800,Hi;'
        'redeye=0.4,0.55,0.03;heal=0.6,0.1,0.05;filter=vivid;';
    final e = EditSpec(
      rot90: 1,
      flipH: true,
      straighten: 7.5,
      cropL: 0.1,
      cropT: 0.2,
      cropW: 0.7,
      cropH: 0.6,
      exposure: 20,
      contrast: -10.5,
      temperature: 15,
      vignette: -30,
      autoFix: true,
      curve: [const Offset(0, 0), const Offset(0.5, 0.25), const Offset(1, 1)],
      texts: [TextOverlay(x: 0.25, y: 0.8, size: 0.1, color: 0xFF8800, text: 'Hi')],
      redeye: [EditRegion(x: 0.4, y: 0.55, r: 0.03)],
      heal: [EditRegion(x: 0.6, y: 0.1, r: 0.05)],
      filter: 'vivid',
    );
    expect(e.encode(), golden);
    // Parsing the golden then re-encoding is idempotent (parse also agrees).
    expect(EditSpec.decode(golden).encode(), golden);
  });

  test('float-format ties match native (%.4f vs toStringAsFixed(4))', () {
    // Same literal pinned in native EditSpec.FloatFormatTiesMatchDart.
    final e = EditSpec(straighten: 0.12345, exposure: 0.33335);
    expect(e.encode(), 'straighten=0.1235;exposure=0.3333;');
  });

  test('reset returns to identity', () {
    final e = EditSpec(exposure: 30, filter: 'noir', rot90: 2);
    e.reset();
    expect(e.isIdentity, isTrue);
    expect(e.encode(), isEmpty);
  });

  test('matches the native key set (no surprise keys)', () {
    final e = EditSpec(
      exposure: 5,
      contrast: 5,
      highlights: 5,
      shadows: 5,
      whites: 5,
      blacks: 5,
      clarity: 5,
      dehaze: 5,
      temperature: 5,
      tint: 5,
      vibrance: 5,
      saturation: 5,
      sharpness: 5,
      noise: 5,
      vignette: 5,
      straighten: 5,
      filter: 'film',
    );
    final keys = e
        .encode()
        .split(';')
        .where((t) => t.isNotEmpty)
        .map((t) => t.split('=').first)
        .toSet();
    const expected = {
      'exposure', 'contrast', 'highlights', 'shadows', 'whites', 'blacks',
      'clarity', 'dehaze', 'temp', 'tint', 'vibrance', 'saturation',
      'sharpness', 'noise', 'vignette', 'straighten', 'filter',
    };
    expect(keys, expected);
  });
}
