// share_service.dart — OS share sheet for photos (Picasa parity §10, modern
// replacement for email/upload). On macOS share_plus drives the
// NSSharingServicePicker; an unedited JPEG shares its original file, an edited
// asset shares a freshly-rendered temp copy (via render_service). The picker is
// a popover, so it needs the invoking widget's screen rect for anchoring.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../backend/native_backend.dart';
import '../../data/models.dart';
import '../export/render_service.dart';

/// The screen rect of [context]'s render box (for the macOS share popover
/// anchor). Null when it can't be resolved.
Rect? shareOriginFrom(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final origin = box.localToGlobal(Offset.zero);
  return origin & box.size;
}

/// Share [photos] through the OS share sheet. Renders edited assets to temp
/// copies first. [origin] anchors the macOS popover (pass [shareOriginFrom]).
Future<void> sharePhotos(
  BuildContext context, {
  required List<Photo> photos,
  Rect? origin,
}) async {
  final backend = NativeBackendScope.maybeOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (photos.isEmpty) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Nothing selected to share.')));
    return;
  }
  if (backend == null) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Sharing needs the native backend.')));
    return;
  }

  final paths = <String>[];
  for (final p in photos) {
    final path = await renderTempCopy(
      engine: backend.engine,
      events: backend.events,
      photo: p,
    );
    if (path != null) paths.add(path);
  }
  if (paths.isEmpty) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Could not prepare files to share.')));
    return;
  }

  await Share.shareXFiles(
    [for (final p in paths) XFile(p)],
    sharePositionOrigin: origin,
  );
}
