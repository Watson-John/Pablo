// FaceThumb — renders a single detected face as a cropped image tile.
//
// Live: clips the asset's thumbnail texture to the face's box via
// [NativeAssetTexture]. Face boxes are in SOURCE-IMAGE pixels, so we normalize
// them with the source dimensions the controller recorded at ingestion. When
// the backend is off, the path/dims are unknown, or this is the mock app, it
// falls back to the gradient tile the People mockup used.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../backend/native_backend.dart';
import '../../theme/tokens.dart';
import '../gallery/native_asset_texture.dart';
import 'people_scope.dart';

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
    final fallback = _GradientTile(hue: hue ?? ((face.clusterId.abs() * 47) % 360));

    Widget child = fallback;
    if (backend != null && path != null && dims != null) {
      final w = dims.width.toDouble();
      final h = dims.height.toDouble();
      if (w > 0 && h > 0) {
        // Normalize the source-pixel box; pad a little so the crop isn't a
        // tight head-only clip, then clamp to the image.
        final pad = 0.15;
        var l = (face.boxX - face.boxW * pad) / w;
        var t = (face.boxY - face.boxH * pad) / h;
        var cw = face.boxW * (1 + 2 * pad) / w;
        var ch = face.boxH * (1 + 2 * pad) / h;
        l = l.clamp(0.0, 1.0);
        t = t.clamp(0.0, 1.0);
        cw = cw.clamp(0.01, 1.0 - l);
        ch = ch.clamp(0.01, 1.0 - t);
        child = NativeAssetTexture(
          engine: backend.engine,
          events: backend.events,
          assetId: face.assetId,
          path: path,
          crop: Rect.fromLTWH(l, t, cw, ch),
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

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.hue});
  final int hue;

  @override
  Widget build(BuildContext context) {
    final h = hue % 360;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, h.toDouble(), 0.32, 0.72).toColor(),
            HSLColor.fromAHSL(1, ((h + 20) % 360).toDouble(), 0.44, 0.56).toColor(),
          ],
        ),
      ),
    );
  }
}
