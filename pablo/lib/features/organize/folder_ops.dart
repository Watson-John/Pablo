// folder_ops.dart — folder-level organize actions: Split Folder Here, New /
// Rename / Delete folder, and the post-move empty-folder cleanup offer. Moves
// route through the shared reorganizeMove pipeline (catalog-aware + undo +
// snackbar); rename is a single transactional dir rename + catalog rebase with
// its own undo.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/boot.dart';
import '../../data/library.dart';
import '../../data/models.dart' show Photo;
import '../../data/scheme_engine.dart' show hardenComponent;
import '../../data/undo_stack.dart';
import '../../utils/asset_id.dart';
import 'reorganize_controller.dart';

/// Split [folderId] at [clickedPhotoId]: move that photo and every photo after
/// it (in the visible sort) into a new sibling folder. If the clicked photo is
/// part of a multi-selection, the selection (restricted to this folder) is
/// moved instead. Prompts for the new folder name (date-prefilled).
Future<void> splitFolderAt(
  BuildContext context,
  PabloAppState st,
  String folderId,
  String clickedPhotoId,
) async {
  final photos = photosFor(folderId);
  final targets = splitTargetIds(st.selectedPhotos, photos, clickedPhotoId);
  if (targets.isEmpty) return;

  final prefill = _splitNamePrefill(photos, targets.first, folderId);
  final name = await _promptFolderName(context,
      title: 'Split into new folder', initial: prefill, action: 'Split');
  if (name == null || name.trim().isEmpty || !context.mounted) return;

  final leaf = hardenComponent(name.trim());
  if (leaf.isEmpty) return;
  final parent = _parentOf(folderId);
  final newDir = '$parent${Platform.pathSeparator}$leaf';
  if (Directory(newDir).existsSync()) {
    _snack(context, 'A folder named “$leaf” already exists here.');
    return;
  }
  await reorganizeMove(context, st, targets, newDir,
      createdDirs: [newDir], label: 'Split folder');
}

/// The photos a split should move: the selection (∩ this folder) when the
/// clicked photo is in a multi-selection, else the clicked photo and all after
/// it in [photos] (the visible order). Pure — [photos] is the sorted list the
/// user sees, so the "and everything after" set honors the active sort.
List<String> splitTargetIds(
    Set<String> selected, List<Photo> photos, String clickedId) {
  if (selected.length > 1 && selected.contains(clickedId)) {
    return [
      for (final p in photos)
        if (selected.contains(p.id)) p.id,
    ];
  }
  final idx = photos.indexWhere((p) => p.id == clickedId);
  if (idx < 0) return const [];
  return [for (var i = idx; i < photos.length; i++) photos[i].id];
}

String _splitNamePrefill(
    List<Photo> photos, String firstId, String folderId) {
  DateTime? when;
  for (final p in photos) {
    if (p.id == firstId) {
      when = p.modified;
      break;
    }
  }
  if (when != null) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)}';
  }
  return '${_leafOf(folderId)} 2';
}

/// Create a new subfolder under [parentId], then refresh so it appears.
Future<void> newSubfolder(
    BuildContext context, PabloAppState st, String parentId) async {
  final name = await _promptFolderName(context,
      title: 'New folder', initial: '', action: 'Create');
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final leaf = hardenComponent(name.trim());
  if (leaf.isEmpty) return;
  final dir = '$parentId${Platform.pathSeparator}$leaf';
  if (Directory(dir).existsSync()) {
    _snack(context, 'A folder named “$leaf” already exists here.');
    return;
  }
  try {
    Directory(dir).createSync(recursive: true);
  } catch (e) {
    _snack(context, 'Could not create folder: $e');
    return;
  }
  await _refreshAndRebuild(st);
}

/// Rename [folderId] on disk and rebase every descendant path in the catalog,
/// preserving asset ids. Pushes a reversible undo entry.
Future<void> renameFolder(
    BuildContext context, PabloAppState st, String folderId) async {
  final engine = NativeBackendScope.maybeOf(context)?.engine;
  final current = _leafOf(folderId);
  final name = await _promptFolderName(context,
      title: 'Rename folder', initial: current, action: 'Rename');
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  final leaf = hardenComponent(name.trim());
  if (leaf.isEmpty || leaf == current) return;
  final parent = _parentOf(folderId);
  final newPath = '$parent${Platform.pathSeparator}$leaf';
  if (Directory(newPath).existsSync()) {
    _snack(context, 'A folder named “$leaf” already exists here.');
    return;
  }
  try {
    Directory(folderId).renameSync(newPath);
  } catch (e) {
    _snack(context, 'Could not rename folder: $e');
    return;
  }
  engine?.rebaseLibrary(folderId, newPath); // catalog: rows + import roots
  remapCatalogPrefix(folderId, newPath);
  st.undoStack.push(UndoableFileOp(
    label: 'Rename folder',
    applied: const [],
    reverse: () async {
      Directory(newPath).renameSync(folderId);
      engine?.rebaseLibrary(newPath, folderId);
      remapCatalogPrefix(newPath, folderId);
    },
  ));
  await _refreshAndRebuild(st);
  if (context.mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text('Renamed to “$leaf”'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          final op = st.undoStack.top;
          if (op != null) undoFileOp(messenger, st, op, engine: engine);
        },
      ),
    ));
  }
}

/// Delete [folderId] only if it is empty. Non-recursive on purpose: a file
/// that raced in makes the delete throw, which is the race guard (no TOCTOU
/// window). Refreshes on success.
Future<void> deleteFolderIfEmpty(
    BuildContext context, PabloAppState st, String folderId) async {
  try {
    Directory(folderId).deleteSync(); // throws if non-empty
  } catch (_) {
    _snack(context, 'Folder isn’t empty — nothing deleted.');
    return;
  }
  await _refreshAndRebuild(st);
  if (context.mounted) _snack(context, 'Deleted “${_leafOf(folderId)}”');
}

/// After a move emptied [dirs] of photos, offer a one-tap cleanup. Never
/// deletes automatically. Uses non-recursive delete (leftover non-image files
/// keep the folder alive).
void offerEmptyFolderCleanup(
    BuildContext context, PabloAppState st, List<String> dirs) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null || dirs.isEmpty) return;
  final label = dirs.length == 1
      ? 'Folder “${_leafOf(dirs.first)}” is now empty'
      : '${dirs.length} folders are now empty';
  messenger.showSnackBar(SnackBar(
    content: Text(label),
    action: SnackBarAction(
      label: 'Delete',
      onPressed: () async {
        var deleted = 0;
        for (final d in dirs) {
          try {
            Directory(d).deleteSync();
            deleted++;
          } catch (_) {/* raced-in file — leave it */}
        }
        await _refreshAndRebuild(st);
        if (context.mounted) {
          _snack(context,
              deleted == dirs.length ? 'Deleted' : 'Deleted $deleted of ${dirs.length}');
        }
      },
    ),
  ));
}

// ── helpers ────────────────────────────────────────────────────────────────

Future<void> _refreshAndRebuild(PabloAppState st) async {
  final root = BootConfig.instance.libraryRoot;
  if (root.isNotEmpty) {
    Library.instance = await Library.scanAsync(root);
    libraryRevision.value++;
  }
  st.libraryChanged();
}

String _leafOf(String path) =>
    path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

String _parentOf(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i <= 0 ? path : path.substring(0, i);
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));

Future<String?> _promptFolderName(
  BuildContext context, {
  required String title,
  required String initial,
  required String action,
}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: Text(action)),
      ],
    ),
  );
}
