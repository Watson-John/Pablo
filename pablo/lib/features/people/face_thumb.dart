// FaceThumb — renders a single detected face as a cropped image tile.
//
// Live: clips the asset's thumbnail texture to the face's box via
// [NativeAssetTexture]. Face boxes are in SOURCE-IMAGE pixels, so we normalize
// them with the source dimensions recorded at ingestion (see [faceCropRect]).
// When the backend is off, the path/dims are unknown, or this is the mock app,
// it falls back to a hue-derived gradient tile.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../backend/native_backend.dart';
import '../../theme/tokens.dart';
import '../../utils/hue.dart';
import '../gallery/native_asset_texture.dart';
import 'face_palette.dart';
import 'people_scope.dart';

/// Padding added around a detected face box before cropping, so the tile isn't
/// a tight head-only clip. Fraction of the box's own width/height.
const double _kFaceCropPad = 0.15;

/// Normalized [0,1) crop rect for a SOURCE-pixel face box within an image of
/// [imgW]×[imgH], padded by [pad] (fraction of the box) and clamped to the
/// image. Null if the dimensions are degenerate. Pure + testable — takes plain
/// numbers (not a FaceRow) so it needs no FFI types and stays out of build().
Rect? faceCropRect({
  required double boxX,
  required double boxY,
  required double boxW,
  required double boxH,
  required int imgW,
  required int imgH,
  double pad = _kFaceCropPad,
}) {
  final w = imgW.toDouble();
  final h = imgH.toDouble();
  if (w <= 0 || h <= 0) return null;
  final l = ((boxX - boxW * pad) / w).clamp(0.0, 1.0);
  final t = ((boxY - boxH * pad) / h).clamp(0.0, 1.0);
  final cw = (boxW * (1 + 2 * pad) / w).clamp(0.01, 1.0 - l);
  final ch = (boxH * (1 + 2 * pad) / h).clamp(0.01, 1.0 - t);
  return Rect.fromLTWH(l, t, cw, ch);
}

class FaceThumb extends StatelessWidget {
  const FaceThumb({
    required this.face,
    this.size = 64,
    this.borderRadius,
    this.hue,
    super.key,
  });

  final FaceRow face;
  final double size;
  final BorderRadius? borderRadius;

  /// Gradient-fallback hue; defaults to a stable hue derived from the face.
  final int? hue;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? PabloRadius.lgAll;
    final backend = NativeBackendScope.maybeOf(context);
    final controller = PeopleScope.read(context);
    final path = controller.assetPath(face.assetId);
    final dims = controller.assetDims(face.assetId);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: faceTileGradient(hue ?? hueForId(face.clusterId)),
      ),
    );

    Widget child = fallback;
    if (backend != null && path != null && dims != null) {
      final crop = faceCropRect(
        boxX: face.boxX,
        boxY: face.boxY,
        boxW: face.boxW,
        boxH: face.boxH,
        imgW: dims.width,
        imgH: dims.height,
      );
      if (crop != null) {
        child = NativeAssetTexture(
          engine: backend.engine,
          events: backend.events,
          assetId: face.assetId,
          path: path,
          crop: crop,
          fallback: fallback,
        );
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}
