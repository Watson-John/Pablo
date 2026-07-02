// PhotoSurface — renders a real photo's pixels.
//
// When the native backend is mounted, routes the file through a
// [NativeAssetTexture] (libvips decode → GPU texture). Until the frame is ready
// — or when the backend is off — it shows a neutral surface, never a synthetic
// gradient. Shared by the gallery thumbnail, the lightbox, and the info panel
// preview so there is exactly one place that knows how a Photo becomes pixels.
//
// It also threads the asset's saved-edit content_rev (from [EditsStore]) into
// the texture so an edit repaints already-displayed tiles, and forwards an
// optional live-edit [previewSpec] for the editor.

import 'package:flutter/material.dart';

import '../../backend/native_backend.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../editor/edits_store.dart';
import 'native_asset_texture.dart';

class PhotoSurface extends StatelessWidget {
  const PhotoSurface({
    required this.photo,
    this.targetW = 256,
    this.targetH = 256,
    this.previewSpec,
    super.key,
  });

  final Photo photo;
  final int targetW;
  final int targetH;

  /// Transient live-edit spec for the editor preview (see NativeAssetTexture).
  final String? previewSpec;

  @override
  Widget build(BuildContext context) {
    final backend = NativeBackendScope.maybeOf(context);
    const fallback = ColoredBox(color: PabloColors.backgroundSurfaceAlt);
    if (backend == null) return fallback;
    final assetId = assetIdFor(photo.id);
    // Rebuild when the edited-assets index changes so a saved edit repaints
    // on-screen tiles (the rev change makes the texture rebind + re-request).
    return ListenableBuilder(
      listenable: EditsStore.instance,
      builder: (context, _) => NativeAssetTexture(
        engine: backend.engine,
        events: backend.events,
        assetId: assetId,
        path: photo.filePath,
        targetW: targetW,
        targetH: targetH,
        contentRev: EditsStore.instance.revOf(assetId),
        previewSpec: previewSpec,
        fallback: fallback,
      ),
    );
  }
}
