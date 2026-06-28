// reorganize_controller.dart — the in-app drag-drop reorganize action: move the
// dragged photos into a target folder on disk, refresh the library, and offer an
// Undo. Built on LibraryMover (verified moves) + the existing Dart Library scan
// (the chosen Phase-B foundation on this branch).

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../data/boot.dart';
import '../../data/library.dart';
import '../../data/library_mover.dart';

/// Move [paths] into [destDir], then refresh the library and show a result
/// snackbar with Undo. No-op for an empty drop or a same-folder drop.
///
/// [refresh] is injectable for tests; in the app it defaults to a full re-scan
/// of the import root ([_refreshLibrary]).
Future<void> reorganizeMove(
  BuildContext context,
  PabloAppState st,
  List<String> paths,
  String destDir, {
  Future<void> Function()? refresh,
}) async {
  if (paths.isEmpty) return;
  final doRefresh = refresh ?? _refreshLibrary;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final batch = LibraryMover.moveInto(paths, destDir);
  if (!batch.anyMoved) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Nothing to move (already in that folder)')));
    return;
  }
  // Old ids (== source paths) are now stale; drop them from selection/tray.
  for (final m in batch.moves) {
    if (m.ok) {
      st.selectedPhotos.remove(m.fromPath);
      st.trayPhotos.remove(m.fromPath);
    }
  }
  await doRefresh();
  st.libraryChanged();
  if (!context.mounted) return;
  final n = batch.movedCount;
  messenger?.showSnackBar(SnackBar(
    content: Text('Moved $n photo${n == 1 ? '' : 's'}'
        '${batch.failedCount > 0 ? ' · ${batch.failedCount} failed' : ''}'),
    action: SnackBarAction(
      label: 'Undo',
      onPressed: () => _undo(context, st, batch, refresh: refresh),
    ),
  ));
}

Future<void> _undo(
  BuildContext context,
  PabloAppState st,
  MoveBatch batch, {
  Future<void> Function()? refresh,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = LibraryMover.undo(batch);
  await (refresh ?? _refreshLibrary)();
  st.libraryChanged();
  messenger?.showSnackBar(SnackBar(
    content: Text(result.failedCount > 0
        ? 'Undo partially failed (${result.failedCount})'
        : 'Move undone'),
  ));
}

/// Re-scan the import root and notify the app to rebuild against it. A full
/// rescan is the simple, correct refresh; it can be made incremental later.
Future<void> _refreshLibrary() async {
  final root = BootConfig.instance.libraryRoot;
  if (root.isEmpty) return;
  Library.instance = await Library.scanAsync(root);
  libraryRevision.value++;
}
