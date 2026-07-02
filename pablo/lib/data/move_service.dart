// move_service.dart — the ONE orchestrator for every in-app file move or
// rename (drag-drop reorganize, Move to Folder, Split Folder, Batch Rename).
// Keeps the disk, the native catalog, and the in-memory id maps convergent:
//
//   1. move each file (FileOps.move — atomic rename, cross-device fallback;
//      moveInto plans collision-free `-NN` destinations via LibraryMover)
//   2. move its sidecars best-effort (`<path>.xmp`, `<stem>.pablo.tif`)
//   3. ONE Engine.relocateAssets call for the moved files that have hydrated
//      catalog ids — so faces/albums/tags/edits/embeddings stay attached to
//      the same asset id. Per-run hash fallback ids are never sent.
//   4. remap the in-memory path→id maps (asset_id.dart)
//   5. record a reversible batch on the caller's UndoStack
//
// The filesystem move happens BEFORE the catalog update on purpose: a crash
// between the two degrades to the old rescan-as-remove+add behavior (metadata
// loss on that file, recoverable by rescan), whereas the reverse order could
// leave the catalog pointing at paths that no longer exist.
//
// No UI here — callers refresh the Library snapshot, remap selection state
// (PabloAppState.remapPhotoIds), and surface snackbars.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../utils/asset_id.dart';
import '../utils/sidecar_paths.dart';
import 'file_ops.dart';
import 'library.dart';
import 'library_mover.dart';
import 'undo_stack.dart';

/// An explicit (from → to) move, for callers that plan their own destinations
/// (Split Folder, Batch Rename). `moveInto` plans destinations itself.
class PlannedMove {
  const PlannedMove(this.from, this.to);
  final String from;
  final String to;
}

/// The result of one MoveService batch.
class MoveOutcome {
  const MoveOutcome({
    required this.moves,
    required this.emptiedSourceDirs,
    this.undoOp,
  });

  /// Every attempted move, ok or failed (reuses LibraryMover's MoveResult).
  final List<MoveResult> moves;

  /// Source directories that no longer contain any image file after this
  /// batch — offered for cleanup (Stage 6); never auto-deleted.
  final List<String> emptiedSourceDirs;

  /// The reversible record pushed onto the undo stack; null when nothing
  /// moved (also null for undo batches themselves — no redo).
  final UndoableFileOp? undoOp;

  int get movedCount => moves.where((m) => m.ok).length;
  int get failedCount => moves.where((m) => !m.ok).length;
  bool get anyMoved => movedCount > 0;

  /// Old path → new path for the ok rows (callers remap selection with this).
  Map<String, String> get remapped =>
      {for (final m in moves.where((m) => m.ok)) m.fromPath: m.toPath};
}

class MoveService {
  /// Move [paths] into [destDir] (skip files already there; `-NN` suffix on
  /// name clashes — LibraryMover semantics). Pushes an undoable batch onto
  /// [undo] when anything moved.
  static MoveOutcome moveInto(
    List<String> paths,
    String destDir, {
    Engine? engine,
    UndoStack? undo,
    String? label,
    List<String> createdDirs = const [],
  }) {
    final batch = LibraryMover.moveInto(paths, destDir);
    return _finish(
      batch.moves,
      engine: engine,
      undo: undo,
      createdDirs: createdDirs,
      label: label ?? _movedLabel(batch.movedCount),
    );
  }

  /// Execute explicit (from → to) pairs. Identity pairs are dropped; a pair
  /// whose destination already exists fails that row (FileOps refuses to
  /// overwrite) — callers plan collision-free names first.
  static MoveOutcome moveExact(
    List<PlannedMove> moves, {
    Engine? engine,
    UndoStack? undo,
    required String label,
    List<String> createdDirs = const [],
  }) {
    final results = <MoveResult>[];
    for (final m in moves) {
      if (m.from == m.to) continue;
      final r = FileOps.move(m.from, m.to);
      results.add(MoveResult(m.from, m.to, r.ok, r.error));
    }
    return _finish(
      results,
      engine: engine,
      undo: undo,
      createdDirs: createdDirs,
      label: label,
    );
  }

  /// Reverse [op]: move each applied file back (dest → source), reverse its
  /// sidecars and catalog row, then remove any directories the original op
  /// created, if they are now empty. The caller is responsible for having
  /// taken [op] OFF the undo stack (pop/remove) before calling — undo does
  /// not push a redo entry.
  static MoveOutcome undoOp(UndoableFileOp op, {Engine? engine}) {
    final results = <MoveResult>[];
    for (final m in op.applied.reversed) {
      final r = FileOps.move(m.toPath, m.fromPath);
      results.add(MoveResult(m.toPath, m.fromPath, r.ok, r.error));
    }
    final outcome =
        _finish(results, engine: engine, undo: null, label: '', createdDirs: const []);
    // Deepest-first, non-recursive delete: a directory that gained unrelated
    // files in the meantime simply refuses to die — that's the race guard.
    final dirs = [...op.createdDirs]..sort((a, b) => b.length.compareTo(a.length));
    for (final d in dirs) {
      try {
        Directory(d).deleteSync();
      } catch (_) {/* not empty or already gone — leave it */}
    }
    return outcome;
  }

  // Shared tail: sidecars → catalog relocate → id remap → emptied dirs →
  // undo record.
  static MoveOutcome _finish(
    List<MoveResult> results, {
    required Engine? engine,
    required UndoStack? undo,
    required String label,
    required List<String> createdDirs,
  }) {
    final ok = results.where((m) => m.ok).toList();

    for (final m in ok) {
      for (final (sFrom, sTo) in sidecarMovesFor(m.fromPath, m.toPath)) {
        _moveSidecar(sFrom, sTo);
      }
    }

    // One catalog call for the rows with real (hydrated) ids. Skipped rows
    // (collisions with rows the catalog already has at the destination) are
    // logged; the next rescan reconciles them.
    final withIds = [
      for (final m in ok)
        if (catalogIdForPath(m.fromPath) != null)
          (catalogIdForPath(m.fromPath)!, m.toPath, m.fromPath),
    ];
    if (engine != null && withIds.isNotEmpty) {
      final outcome =
          engine.relocateAssets([for (final w in withIds) (w.$1, w.$2)]);
      for (var i = 0; i < withIds.length; i++) {
        if (!outcome.okByIndex[i]) {
          debugPrint('[move] catalog relocate skipped '
              '${withIds[i].$3} → ${withIds[i].$2} (id ${withIds[i].$1})');
        }
      }
    }
    for (final m in ok) {
      remapCatalogPath(m.fromPath, m.toPath);
    }

    final emptied = _emptiedDirs(ok);

    UndoableFileOp? undoOp;
    if (ok.isNotEmpty && undo != null) {
      undoOp = UndoableFileOp(
        label: label,
        applied: List.unmodifiable(ok),
        createdDirs: createdDirs,
      );
      undo.push(undoOp);
    }
    return MoveOutcome(
        moves: results, emptiedSourceDirs: emptied, undoOp: undoOp);
  }

  /// Best-effort sidecar move: a missing sidecar is the normal case; a failed
  /// move is logged but never fails the photo's own move.
  static void _moveSidecar(String from, String to) {
    try {
      if (!File(from).existsSync()) return;
      final r = FileOps.move(from, to);
      if (!r.ok) debugPrint('[move] sidecar move failed: $from (${r.error})');
    } catch (e) {
      debugPrint('[move] sidecar move failed: $from ($e)');
    }
  }

  /// Distinct source parents of [ok] moves that now contain no image file
  /// (leftover sidecars/other files don't count as photos, but they will
  /// still block an actual rmdir later — deliberately).
  static List<String> _emptiedDirs(List<MoveResult> ok) {
    final dirs = <String>{for (final m in ok) File(m.fromPath).parent.path};
    final emptied = <String>[];
    for (final d in dirs) {
      try {
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        final hasImage = dir
            .listSync(recursive: true, followLinks: false)
            .any((e) => e is File && hasImageExtension(e.path));
        if (!hasImage) emptied.add(d);
      } catch (_) {/* unreadable — don't offer cleanup */}
    }
    emptied.sort();
    return emptied;
  }

  static String _movedLabel(int n) =>
      'Move $n photo${n == 1 ? '' : 's'}';
}
