// EditSpec — the Dart mirror of the native parametric edit stack
// (native/core/src/edit/edit_spec). Serializes to the same compact
// `key=value;` grammar so a spec authored here renders identically when sent to
// `previewEdits` / `setAssetEdits`. Only non-default fields are emitted, so an
// identity spec encodes to "".

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// A circular retouch region (mirrors native Region): normalized centre plus a
/// radius expressed as a fraction of the image's SHORT edge. Used for both
/// red-eye circles and heal brush dabs.
class EditRegion {
  EditRegion({this.x = 0.5, this.y = 0.5, this.r = 0.04});
  double x, y, r;

  EditRegion clone() => EditRegion(x: x, y: y, r: r);
}

/// One text overlay (mirrors native TextItem). Position + size are normalized to
/// the image; size is a fraction of image height; color is 0xRRGGBB.
class TextOverlay {
  TextOverlay({
    this.x = 0.5,
    this.y = 0.5,
    this.size = 0.06,
    this.color = 0xFFFFFF,
    this.text = '',
  });
  double x, y, size;
  int color;
  String text;

  TextOverlay clone() =>
      TextOverlay(x: x, y: y, size: size, color: color, text: text);
}

class EditSpec {
  EditSpec({
    this.rot90 = 0,
    this.flipH = false,
    this.flipV = false,
    this.straighten = 0,
    this.cropL = 0,
    this.cropT = 0,
    this.cropW = 1,
    this.cropH = 1,
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.clarity = 0,
    this.dehaze = 0,
    this.temperature = 0,
    this.tint = 0,
    this.vibrance = 0,
    this.saturation = 0,
    this.sharpness = 0,
    this.noise = 0,
    this.vignette = 0,
    this.autoFix = false,
    List<Offset>? curve,
    List<EditRegion>? redeye,
    List<EditRegion>? heal,
    List<TextOverlay>? texts,
    this.filter = 'none',
  })  : curve = curve ?? <Offset>[],
        redeye = redeye ?? <EditRegion>[],
        heal = heal ?? <EditRegion>[],
        texts = texts ?? <TextOverlay>[];

  // Geometry.
  int rot90;
  bool flipH;
  bool flipV;
  double straighten;
  double cropL, cropT, cropW, cropH;

  // Tone (Light).
  double exposure, contrast, highlights, shadows, whites, blacks, clarity, dehaze;

  // Colour.
  double temperature, tint, vibrance, saturation;

  // Detail.
  double sharpness, noise, vignette;

  // One-click enhance (auto-levels).
  bool autoFix;

  // Master tone curve control points (normalized); empty/diagonal = identity.
  List<Offset> curve;

  // Retouch (post-geometry, normalized coords).
  List<EditRegion> redeye; // red-eye correction circles
  List<EditRegion> heal; // heal / spot-removal dabs

  // Text overlays (rendered last, on top).
  List<TextOverlay> texts;

  // Filter preset id (matches kEditorFilters / filter_matrices.dart).
  String filter;

  bool get curveIsIdentity {
    if (curve.isEmpty) return true;
    for (final p in curve) {
      if ((p.dx - p.dy).abs() > 1e-3) return false;
    }
    return true;
  }

  static const double _eps = 1e-6;
  static bool _z(double v) => v.abs() < _eps;

  bool get hasGeometry =>
      rot90 != 0 ||
      flipH ||
      flipV ||
      !_z(straighten) ||
      !_z(cropL) ||
      !_z(cropT) ||
      !_z(cropW - 1) ||
      !_z(cropH - 1) ||
      cropW <= 0;

  bool get isIdentity =>
      !hasGeometry &&
      !autoFix &&
      curveIsIdentity &&
      redeye.isEmpty &&
      heal.isEmpty &&
      texts.isEmpty &&
      (filter.isEmpty || filter == 'none') &&
      _z(exposure) &&
      _z(contrast) &&
      _z(highlights) &&
      _z(shadows) &&
      _z(whites) &&
      _z(blacks) &&
      _z(clarity) &&
      _z(dehaze) &&
      _z(temperature) &&
      _z(tint) &&
      _z(vibrance) &&
      _z(saturation) &&
      _z(sharpness) &&
      _z(noise) &&
      _z(vignette);

  EditSpec clone() => EditSpec(
        rot90: rot90,
        flipH: flipH,
        flipV: flipV,
        straighten: straighten,
        cropL: cropL,
        cropT: cropT,
        cropW: cropW,
        cropH: cropH,
        exposure: exposure,
        contrast: contrast,
        highlights: highlights,
        shadows: shadows,
        whites: whites,
        blacks: blacks,
        clarity: clarity,
        dehaze: dehaze,
        temperature: temperature,
        tint: tint,
        vibrance: vibrance,
        saturation: saturation,
        sharpness: sharpness,
        noise: noise,
        vignette: vignette,
        autoFix: autoFix,
        curve: List<Offset>.from(curve),
        redeye: redeye.map((r) => r.clone()).toList(),
        heal: heal.map((r) => r.clone()).toList(),
        texts: texts.map((t) => t.clone()).toList(),
        filter: filter,
      );

  /// Reset every field to its neutral default in place.
  void reset() {
    rot90 = 0;
    flipH = flipV = false;
    straighten = 0;
    cropL = cropT = 0;
    cropW = cropH = 1;
    exposure = contrast = highlights = shadows = whites = blacks = 0;
    clarity = dehaze = temperature = tint = vibrance = saturation = 0;
    sharpness = noise = vignette = 0;
    autoFix = false;
    curve = <Offset>[];
    redeye = <EditRegion>[];
    heal = <EditRegion>[];
    texts = <TextOverlay>[];
    filter = 'none';
  }

  static String _fmt(double v) {
    if ((v - v.roundToDouble()).abs() < _eps) {
      return v.round().toString();
    }
    var s = v.toStringAsFixed(4);
    // Trim trailing zeros then a dangling dot.
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  // Percent-encode the grammar delimiters so arbitrary text survives a spec
  // value (mirrors native esc/unesc in edit_spec.cpp).
  static String _esc(String s) {
    final b = StringBuffer();
    for (final cu in s.runes) {
      if (cu == 0x25 || cu == 0x3B || cu == 0x3D || cu == 0x2C || cu == 0x7C ||
          cu < 0x20) {
        b.write('%${cu.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        b.writeCharCode(cu);
      }
    }
    return b.toString();
  }

  // Parse a numeric field, mirroring native to_double: reject non-finite
  // (Dart's double.tryParse admits "Infinity"/"NaN" where strtod+isfinite in
  // edit_spec.cpp rejects them) and any unparseable token, falling back to [fb].
  static double _num(String v, double fb) {
    final x = double.tryParse(v);
    return (x != null && x.isFinite) ? x : fb;
  }

  static String _unesc(String s) {
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '%' && i + 2 < s.length) {
        final h = int.tryParse(s.substring(i + 1, i + 3), radix: 16);
        if (h != null) {
          b.writeCharCode(h);
          i += 2;
          continue;
        }
      }
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Serialize to the compact `key=value;` grammar (only non-default fields).
  String encode() {
    final b = StringBuffer();
    void kv(String k, String v) {
      b
        ..write(k)
        ..write('=')
        ..write(v)
        ..write(';');
    }

    if (rot90 != 0) kv('rot', '$rot90');
    if (flipH) kv('fliph', '1');
    if (flipV) kv('flipv', '1');
    if (!_z(straighten)) kv('straighten', _fmt(straighten));
    if (hasGeometry &&
        (!_z(cropL) || !_z(cropT) || !_z(cropW - 1) || !_z(cropH - 1))) {
      kv('crop',
          '${_fmt(cropL)},${_fmt(cropT)},${_fmt(cropW)},${_fmt(cropH)}');
    }
    if (!_z(exposure)) kv('exposure', _fmt(exposure));
    if (!_z(contrast)) kv('contrast', _fmt(contrast));
    if (!_z(highlights)) kv('highlights', _fmt(highlights));
    if (!_z(shadows)) kv('shadows', _fmt(shadows));
    if (!_z(whites)) kv('whites', _fmt(whites));
    if (!_z(blacks)) kv('blacks', _fmt(blacks));
    if (!_z(clarity)) kv('clarity', _fmt(clarity));
    if (!_z(dehaze)) kv('dehaze', _fmt(dehaze));
    if (!_z(temperature)) kv('temp', _fmt(temperature));
    if (!_z(tint)) kv('tint', _fmt(tint));
    if (!_z(vibrance)) kv('vibrance', _fmt(vibrance));
    if (!_z(saturation)) kv('saturation', _fmt(saturation));
    if (!_z(sharpness)) kv('sharpness', _fmt(sharpness));
    if (!_z(noise)) kv('noise', _fmt(noise));
    if (!_z(vignette)) kv('vignette', _fmt(vignette));
    if (autoFix) kv('autofix', '1');
    if (!curveIsIdentity) {
      kv('curves',
          curve.map((p) => '${_fmt(p.dx)},${_fmt(p.dy)}').join('|'));
    }
    if (texts.isNotEmpty) {
      kv(
        'text',
        texts.map((t) {
          final col =
              (t.color & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0');
          return '${_fmt(t.x)},${_fmt(t.y)},${_fmt(t.size)},$col,${_esc(t.text)}';
        }).join('|'),
      );
    }
    if (redeye.isNotEmpty) {
      kv('redeye',
          redeye.map((r) => '${_fmt(r.x)},${_fmt(r.y)},${_fmt(r.r)}').join('|'));
    }
    if (heal.isNotEmpty) {
      kv('heal',
          heal.map((r) => '${_fmt(r.x)},${_fmt(r.y)},${_fmt(r.r)}').join('|'));
    }
    if (filter.isNotEmpty && filter != 'none') kv('filter', filter);
    return b.toString();
  }

  static List<EditRegion> _decodeRegions(String v) {
    final out = <EditRegion>[];
    for (final item in v.split('|')) {
      if (item.isEmpty) continue;
      final cs = item.split(',');
      if (cs.length < 3) continue;
      out.add(EditRegion(
        x: _num(cs[0], 0.5),
        y: _num(cs[1], 0.5),
        r: _num(cs[2], 0.04),
      ));
    }
    return out;
  }

  /// Parse the `key=value;` grammar (unknown keys ignored; malformed numbers
  /// fall back to the field default).
  static EditSpec decode(String s) {
    final e = EditSpec();
    for (final tok in s.split(';')) {
      if (tok.isEmpty) continue;
      final eq = tok.indexOf('=');
      if (eq < 0) continue;
      final k = tok.substring(0, eq);
      final v = tok.substring(eq + 1);
      double d(double fb) => _num(v, fb);
      switch (k) {
        case 'rot':
          e.rot90 = ((int.tryParse(v) ?? 0) % 4 + 4) % 4;
          break;
        case 'fliph':
          e.flipH = v == '1' || v == 'true';
          break;
        case 'flipv':
          e.flipV = v == '1' || v == 'true';
          break;
        case 'straighten':
          e.straighten = d(0);
          break;
        case 'crop':
          // Mirror native's index-walk: tolerate <4 fields, keeping each
          // field's own default (l,t=0; w,h=1) for anything missing/malformed.
          final parts = v.split(',');
          final c = <double>[0, 0, 1, 1];
          for (var i = 0; i < 4 && i < parts.length; i++) {
            c[i] = _num(parts[i], c[i]);
          }
          e.cropL = c[0];
          e.cropT = c[1];
          e.cropW = c[2];
          e.cropH = c[3];
          break;
        case 'exposure':
          e.exposure = d(0);
          break;
        case 'contrast':
          e.contrast = d(0);
          break;
        case 'highlights':
          e.highlights = d(0);
          break;
        case 'shadows':
          e.shadows = d(0);
          break;
        case 'whites':
          e.whites = d(0);
          break;
        case 'blacks':
          e.blacks = d(0);
          break;
        case 'clarity':
          e.clarity = d(0);
          break;
        case 'dehaze':
          e.dehaze = d(0);
          break;
        case 'temp':
          e.temperature = d(0);
          break;
        case 'tint':
          e.tint = d(0);
          break;
        case 'vibrance':
          e.vibrance = d(0);
          break;
        case 'saturation':
          e.saturation = d(0);
          break;
        case 'sharpness':
          e.sharpness = d(0);
          break;
        case 'noise':
          e.noise = d(0);
          break;
        case 'vignette':
          e.vignette = d(0);
          break;
        case 'autofix':
          e.autoFix = v == '1' || v == 'true';
          break;
        case 'curves':
          e.curve = [];
          for (final pt in v.split('|')) {
            if (pt.isEmpty) continue;
            final cs = pt.split(',');
            if (cs.length >= 2) {
              e.curve.add(Offset(_num(cs[0], 0), _num(cs[1], 0)));
            }
          }
          break;
        case 'text':
          e.texts = [];
          for (final item in v.split('|')) {
            if (item.isEmpty) continue;
            final parts = item.split(',');
            if (parts.length < 5) continue;
            e.texts.add(TextOverlay(
              x: _num(parts[0], 0.5),
              y: _num(parts[1], 0.5),
              size: _num(parts[2], 0.06),
              color: int.tryParse(parts[3], radix: 16) ?? 0xFFFFFF,
              // The escaped text has no raw comma, but rejoin defensively.
              text: _unesc(parts.sublist(4).join(',')),
            ));
          }
          break;
        case 'redeye':
          e.redeye = _decodeRegions(v);
          break;
        case 'heal':
          e.heal = _decodeRegions(v);
          break;
        case 'filter':
          e.filter = v;
          break;
      }
    }
    return e;
  }

  /// Net clockwise quarter-turns including flips, useful for UI badges.
  int get netRotation => rot90 % 4;

  /// A rough "is this a big geometry change" flag for preview sizing.
  double get cropZoom =>
      cropW <= 0 ? 1 : 1 / math.min(cropW, cropH).clamp(1e-3, 1.0);
}
