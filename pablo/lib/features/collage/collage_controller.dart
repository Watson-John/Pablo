// collage_controller.dart — glue between the collage dialog, the pure layout
// math, and the native compositor. Resolves the tray photos, computes cells,
// submits Engine.createCollage, awaits its event, writes the result under the
// library's Collages/ folder, and imports it back so it appears in the grid
// (Picasa parity: a collage becomes a new asset).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_scope.dart';
import '../../backend/native_backend.dart';
import '../../data/library.dart';
import '../../data/library_import.dart';
import '../../data/models.dart';
import '../../utils/asset_id.dart';
import 'collage_dialog.dart';
import 'collage_layouts.dart';

/// Run the collage flow from a context with access to the backend + state.
Future<void> runCollage(BuildContext context) async {
  final backend = NativeBackendScope.maybeOf(context);
  final st = AppScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final photos = [
    for (final id in st.trayPhotos)
      if (photoById(id) case final p?) p,
  ];
  if (backend == null) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Collage needs the native backend.')));
    return;
  }
  if (photos.length < 2) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Add at least 2 photos to the tray for a collage.')));
    return;
  }

  final opts = await showCollageDialog(context, count: photos.length);
  if (opts == null) return;

  final cells = collageCells(photos.length, opts.template,
      spacing: opts.spacing);
  final nativeCells = <CollageCell>[
    for (var i = 0; i < photos.length && i < cells.length; i++)
      _cellFor(backend.engine, photos[i], cells[i]),
  ];

  final dst = _collageDest(photos.first.filePath);
  if (dst == null) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Could not find a place to save the collage.')));
    return;
  }

  // Await this one export event (subscribe first, race-free).
  final done = Completer<bool>();
  int? reqId;
  final statuses = <int, int>{};
  final sub = backend.events.listen((e) {
    if (e.kind != PhotoEventKind.exportComplete) return;
    statuses[e.requestId] = e.status;
    if (reqId != null && statuses.containsKey(reqId) && !done.isCompleted) {
      done.complete(statuses[reqId] == 0);
    }
  });

  final req = backend.engine.createCollage(
    cells: nativeCells,
    dstPath: dst,
    canvasW: opts.canvas,
    canvasH: opts.canvas,
    bgRgb: opts.bgRgb,
  );
  if (req == 0) {
    await sub.cancel();
    messenger?.showSnackBar(const SnackBar(
        content: Text('Collage is unavailable on this build.')));
    return;
  }
  reqId = req;
  if (statuses.containsKey(req) && !done.isCompleted) {
    done.complete(statuses[req] == 0);
  }

  bool ok;
  try {
    ok = await done.future.timeout(const Duration(seconds: 60),
        onTimeout: () => false);
  } finally {
    await sub.cancel();
  }

  if (!ok) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Collage failed.')));
    return;
  }

  // Import the new file into the catalog + rebuild the Dart library so it shows.
  if (Library.instance.root.isNotEmpty && context.mounted) {
    await LibraryImport.refresh(
        backend: backend, root: Library.instance.root, appState: st);
  } else {
    backend.engine.importPath(dst);
  }
  messenger?.showSnackBar(SnackBar(content: Text('Collage saved to $dst')));
}

CollageCell _cellFor(Engine engine, Photo photo, Rect r) {
  // Honour the photo's saved edit in the collage.
  final spec = engine.assetEdits(assetIdFor(photo.id));
  return CollageCell(
    x: r.left,
    y: r.top,
    w: r.width,
    h: r.height,
    src: photo.filePath,
    spec: spec,
  );
}

/// `<firstPhotoDir>/Collages/collage-<epochMs>.jpg`, or null if the dir is odd.
String? _collageDest(String firstSrc) {
  final sep = Platform.pathSeparator;
  final dir = firstSrc.contains(sep)
      ? firstSrc.substring(0, firstSrc.lastIndexOf(sep))
      : '';
  if (dir.isEmpty) return null;
  final outDir = Directory('$dir${sep}Collages');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final ts = DateTime.now().millisecondsSinceEpoch;
  return '${outDir.path}${sep}collage-$ts.jpg';
}
