// The lightbox's main image surface (edit-aware sizing + face overlays),
// extracted from lightbox_view.dart.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../../data/models.dart';
import '../../../theme/tokens.dart';
import '../../editor/crop_overlay.dart';
import '../../editor/edit_preview_surface.dart';
import '../../editor/edit_session.dart';
import '../../editor/retouch_overlay.dart';
import 'face_marker.dart';

/// The big image, sized to the photo's true aspect (so the whole frame shows),
/// with one hover-to-name marker per detected face overlaid on top. Falls back
/// to a 4:3 frame with no markers when the source dimensions aren't known.
class LightboxImage extends StatelessWidget {
  const LightboxImage({
    required this.photo,
    required this.faces,
    required this.imgW,
    required this.imgH,
    super.key,
  });

  final Photo photo;
  final List<FaceRow> faces;
  final int imgW;
  final int imgH;

  @override
  Widget build(BuildContext context) {
    // Depend on the edit session so the box re-sizes as geometry changes.
    final session = EditSessionScope.of(context);
    final spec = session?.spec;
    final cropMode = session?.activeTool == 'crop';
    final retouchMode =
        session?.activeTool == 'redeye' || session?.activeTool == 'heal';
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 900.0;
      final maxH = c.maxHeight.isFinite ? c.maxHeight : 700.0;
      final known = imgW > 0 && imgH > 0;
      // Aspect after rotation (the space the crop overlay maps over)…
      double rotAspect = known ? imgW / imgH : 4 / 3;
      if (spec != null && spec.rot90 % 2 == 1) rotAspect = 1 / rotAspect;
      // …and the displayed-box aspect, which also folds in the crop unless we're
      // actively cropping (then we show the full uncropped frame).
      var aspect = rotAspect;
      if (spec != null &&
          !cropMode &&
          spec.cropW > 0 &&
          (spec.cropW != 1 || spec.cropH != 1)) {
        aspect *= spec.cropW / spec.cropH;
      }
      // Contain the image at that aspect within the available area.
      var dW = maxW;
      var dH = dW / aspect;
      if (dH > maxH) {
        dH = maxH;
        dW = dH * aspect;
      }
      final showFaces = known &&
          !cropMode &&
          !retouchMode &&
          (spec == null || !spec.hasGeometry);
      return Center(
        child: SizedBox(
          width: dW,
          height: dH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: PabloRadius.lgAll,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        offset: const Offset(0, 8),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    // The main image renders the live edit preview when an
                    // EditSession is in scope (editor open); otherwise it shows
                    // the saved/original frame. Keyed by id so navigation
                    // recreates it against the freshly-swapped session.
                    child: EditPreviewSurface(
                      key: ValueKey(photo.id),
                      photo: photo,
                      targetW: 1280,
                      targetH: 1280,
                    ),
                  ),
                ),
              ),
              if (cropMode && session != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    child: CropOverlay(
                        session: session, imageAspect: rotAspect),
                  ),
                ),
              if (retouchMode && session != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    child: RetouchOverlay(
                        session: session, tool: session.activeTool!),
                  ),
                ),
              if (showFaces)
                for (final f in faces)
                  Positioned(
                    left: (f.boxX / imgW) * dW,
                    top: (f.boxY / imgH) * dH,
                    width: (f.boxW / imgW) * dW,
                    height: (f.boxH / imgH) * dH,
                    child: FaceMarker(face: f),
                  ),
            ],
          ),
        ),
      );
    });
  }
}
