// export_runner.dart — glue between the export dialog, the pure batch tracker,
// and the live native engine. Resolves which photos to export (the tray if it
// has anything, else the current selection, else the active photo), shows the
// options dialog, then submits one export per photo and reports progress via a
// TaskInfo row + a completion snackbar.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../utils/asset_id.dart';
import 'export_controller.dart';
import 'export_dialog.dart';

/// Photos to export, in priority order: tray, else multi-selection, else the
/// active (open/last-clicked) photo. Empty when nothing is available.
List<Photo> resolveExportPhotos(PabloAppState st) {
  Iterable<String> ids;
  if (st.trayPhotos.isNotEmpty) {
    ids = st.trayPhotos;
  } else if (st.selectedPhotos.isNotEmpty) {
    ids = st.selectedPhotos;
  } else if (st.activePhotoId != null) {
    ids = [st.activePhotoId!];
  } else {
    return const [];
  }
  return [
    for (final id in ids)
      if (photoById(id) case final p?) p,
  ];
}

/// Run the full export flow from a context that can reach the backend + state.
/// Optionally restrict to [photos] (e.g. a single right-clicked photo);
/// otherwise resolves from the app state.
Future<void> runExportToFolder(
  BuildContext context, {
  List<Photo>? photos,
}) async {
  final backend = NativeBackendScope.maybeOf(context);
  final st = AppScope.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final targets = photos ?? resolveExportPhotos(st);

  if (backend == null) {
    messenger?.showSnackBar(
        const SnackBar(content: Text('Export needs the native backend.')));
    return;
  }
  if (targets.isEmpty) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Add photos to the tray or select some to export.')));
    return;
  }

  final settings = await showExportDialog(context, count: targets.length);
  if (settings == null || settings.folder.isEmpty) return;

  const taskId = 'export';
  st.startTask(TaskInfo(
      id: taskId, name: 'Exporting ${targets.length} photos', percent: 1));

  final tracker = ExportBatchTracker(
    completions: backend.events
        .where((e) => e.kind == PhotoEventKind.exportComplete)
        .map((e) => (requestId: e.requestId, status: e.status)),
    onProgress: (done, total) => st.updateTaskPercent(
        taskId, total == 0 ? 100 : (done / total * 100).clamp(1, 100)),
  );

  final taken = <String>{};
  final argb = watermarkArgb(settings.watermarkOpacityPct);
  final result = await tracker.run(targets.length, (i) {
    final photo = targets[i];
    final dst = exportDestination(
      folder: settings.folder,
      srcPath: photo.filePath,
      taken: taken,
    );
    final spec = backend.engine.assetEdits(assetIdFor(photo.id));
    return backend.engine.exportAsset2(
      srcPath: photo.filePath,
      dstPath: dst,
      spec: spec,
      maxDim: settings.maxDim,
      quality: settings.quality,
      watermarkText: settings.watermarkText,
      watermarkArgb: argb,
    );
  });

  st.updateTaskPercent(taskId, 100); // tickTasks() sweeps it off
  st.tickTasks();

  final msg = result.allOk
      ? 'Exported ${result.ok} photo${result.ok == 1 ? '' : 's'} to ${settings.folder}'
      : 'Exported ${result.ok} of ${result.total} · ${result.failed} failed';
  messenger?.showSnackBar(SnackBar(content: Text(msg)));
}
