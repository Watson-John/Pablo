// PhotoSurface — renders a real photo's pixels.
//
// When the native backend is mounted, routes the file through a
// [NativeAssetTexture] (libvips decode → GPU texture). Until the frame is ready
// — or when the backend is off — it shows a neutral surface, never a synthetic
// gradient. Shared by the gallery thumbnail, the lightbox, and the info panel
// preview so there is exactly one place that knows how a Photo becomes pixels.

import 'package:flutter/material.dart';

import '../../backend/native_backend.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import 'native_asset_texture.dart';

class PhotoSurface extends StatelessWidget {
  const PhotoSurface({
    required this.photo,
    this.targetW = 256,
    this.targetH = 256,
    super.key,
  });

  final Photo photo;
  final int targetW;
  final int targetH;

  @override
  Widget build(BuildContext context) {
    final backend = NativeBackendScope.maybeOf(context);
    const fallback = ColoredBox(color: PabloColors.backgroundSurfaceAlt);
    if (backend == null) return fallback;
    return NativeAssetTexture(
      engine: backend.engine,
      events: backend.events,
      assetId: assetIdFor(photo.id),
      path: photo.filePath,
      targetW: targetW,
      targetH: targetH,
      fallback: fallback,
    );
  }
}
