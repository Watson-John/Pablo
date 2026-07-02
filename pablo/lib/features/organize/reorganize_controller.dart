// reorganize_controller.dart — the UI side of in-app file moves: route the
// gesture through MoveService (which keeps disk + catalog + id maps
// convergent), remap app selection state, refresh the library snapshot, and
// surface a snackbar with Undo. Also hosts the shared undo entry points the
// Edit→Undo menu and Cmd/Ctrl+Z use.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Engine;

import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/boot.dart';
import '../../data/library.dart';
import '../../data/move_service.dart';
import '../../data/undo_stack.dart';
import 'folder_ops.dart';
import 'move_palette.dart';

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
  List<String> createdDirs = const [],
  String? label,
}) async {
  if (paths.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final engine = NativeBackendScope.maybeOf(context)?.engine;

  final outcome = MoveService.moveInto(
    paths,
    destDir,
    engine: engine,
    undo: st.undoStack,
    createdDirs: createdDirs,
    label: label,
  );
  if (!outcome.anyMoved) {
    messenger?.showSnackBar(const SnackBar(
        content: Text('Nothing to move (already in that folder)')));
    return;
  }
  await _applyOutcome(st, outcome, refresh: refresh);
  final n = outcome.movedCount;
  messenger?.showSnackBar(SnackBar(
    content: Text('Moved $n photo${n == 1 ? '' : 's'}'
        '${outcome.failedCount > 0 ? ' · ${outcome.failedCount} failed' : ''}'),
    action: outcome.undoOp == null
        ? null
        : SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                undoFileOp(messenger, st, outcome.undoOp!, engine: engine, refresh: refresh),
          ),
  ));
  // Offer to clean up any source folder the move emptied of photos.
  if (context.mounted && outcome.emptiedSourceDirs.isNotEmpty) {
    offerEmptyFolderCleanup(context, st, outcome.emptiedSourceDirs);
  }
}

/// Open the Move-to-Folder palette for [ids] and, on a pick, create the folder
/// if new and move into it. Shared by the context menu and Cmd/Ctrl+Shift+M.
/// No-op for an empty selection.
Future<void> promptMoveToFolder(
  BuildContext context,
  PabloAppState st,
  List<String> ids,
) async {
  if (ids.isEmpty) return;
  final dest = await showMovePalette(
    context,
    folders: [
      for (final f in Library.instance.folderSections)
        FolderCandidate(path: f.id, name: f.name),
    ],
    photoCount: ids.length,
    recents: st.recentMoveDests,
  );
  if (dest == null || !context.mounted) return;
  final createdDirs = <String>[];
  if (dest.isNew) {
    try {
      Directory(dest.dir).createSync(recursive: true);
      createdDirs.add(dest.dir);
    } catch (e) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Could not create folder: $e')));
      return;
    }
  }
  st.noteMoveDestination(dest.dir);
  if (!context.mounted) return;
  await reorganizeMove(context, st, ids, dest.dir, createdDirs: createdDirs);
}

/// Undo a SPECIFIC op (a snackbar's Undo action). Silently does nothing when
/// the op was already consumed by Cmd+Z / Edit→Undo — [UndoStack.remove]
/// guards the double-reverse.
Future<void> undoFileOp(
  ScaffoldMessengerState? messenger,
  PabloAppState st,
  UndoableFileOp op, {
  Engine? engine,
  Future<void> Function()? refresh,
}) async {
  if (!st.undoStack.remove(op)) return;
  await _reverse(messenger, st, op, engine: engine, refresh: refresh);
}

/// Undo the NEWEST file op (Cmd/Ctrl+Z and Edit→Undo). No-op when the stack
/// is empty.
Future<void> undoLastFileOp(
  BuildContext context,
  PabloAppState st, {
  Future<void> Function()? refresh,
}) async {
  final op = st.undoStack.pop();
  if (op == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final engine = NativeBackendScope.maybeOf(context)?.engine;
  await _reverse(messenger, st, op, engine: engine, refresh: refresh);
}

Future<void> _reverse(
  ScaffoldMessengerState? messenger,
  PabloAppState st,
  UndoableFileOp op, {
  Engine? engine,
  Future<void> Function()? refresh,
}) async {
  // A non-move op (folder rename) reverses itself; otherwise move files back.
  if (op.reverse != null) {
    await op.reverse!();
    await (refresh ?? _refreshLibrary)();
    st.libraryChanged();
    messenger?.showSnackBar(SnackBar(content: Text('Undid ${op.label}')));
    return;
  }
  final result = MoveService.undoOp(op, engine: engine);
  await _applyOutcome(st, result, refresh: refresh);
  messenger?.showSnackBar(SnackBar(
    content: Text(result.failedCount > 0
        ? 'Undo partially failed (${result.failedCount})'
        : 'Undid ${op.label}'),
  ));
}

/// Shared post-move bookkeeping: remap ids everywhere, refresh the snapshot,
/// rebuild.
Future<void> _applyOutcome(
  PabloAppState st,
  MoveOutcome outcome, {
  Future<void> Function()? refresh,
}) async {
  st.remapPhotoIds(outcome.remapped);
  await (refresh ?? _refreshLibrary)();
  st.libraryChanged();
}

/// Re-scan the import root and notify the app to rebuild against it. A full
/// rescan is the simple, correct refresh; it can be made incremental later.
Future<void> _refreshLibrary() async {
  final root = BootConfig.instance.libraryRoot;
  if (root.isEmpty) return;
  Library.instance = await Library.scanAsync(root);
  libraryRevision.value++;
}
