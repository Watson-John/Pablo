// library_mover.dart — relocate photos between folders on disk for in-app
// drag-and-drop reorganize. Keeps each file's name, resolves collisions in the
// destination by appending a numbered suffix, and records the batch so the move
// can be undone. Built on file_ops (the verified move seam).
//
// This only touches the filesystem; the caller refreshes the in-memory library
// afterwards (re-scan + libraryRevision bump). No catalog logic here.

import 'dart:io';

import 'file_ops.dart';

class MoveResult {
  const MoveResult(this.fromPath, this.toPath, this.ok, [this.error]);
  final String fromPath;
  final String toPath;
  final bool ok;
  final Object? error;
}

/// The outcome of one reorganize gesture, reversible via [LibraryMover.undo].
class MoveBatch {
  const MoveBatch(this.moves);
  final List<MoveResult> moves;

  int get movedCount => moves.where((m) => m.ok).length;
  int get failedCount => moves.where((m) => !m.ok).length;
  bool get anyMoved => movedCount > 0;
}

class LibraryMover {
  /// Move each of [sourcePaths] into [destDir] (an absolute directory). Files
  /// already in [destDir] are skipped. Name clashes get a `-NN` suffix.
  static MoveBatch moveInto(List<String> sourcePaths, String destDir) {
    final moves = <MoveResult>[];
    for (final src in sourcePaths) {
      try {
        final srcFile = File(src);
        if (srcFile.parent.path == destDir) continue; // already here
        final dest = _freeDest(destDir, _baseName(src));
        final r = FileOps.move(src, dest);
        moves.add(MoveResult(src, dest, r.ok, r.error));
      } catch (e) {
        moves.add(MoveResult(src, src, false, e));
      }
    }
    return MoveBatch(moves);
  }

  /// Reverse a [batch]: move each successfully-moved file back to its origin.
  static MoveBatch undo(MoveBatch batch) {
    final moves = <MoveResult>[];
    for (final m in batch.moves.reversed) {
      if (!m.ok) continue;
      final r = FileOps.move(m.toPath, m.fromPath);
      moves.add(MoveResult(m.toPath, m.fromPath, r.ok, r.error));
    }
    return MoveBatch(moves);
  }

  static String _baseName(String path) =>
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  /// A non-colliding absolute path for [fileName] inside [destDir].
  static String _freeDest(String destDir, String fileName) {
    final sep = Platform.pathSeparator;
    final dot = fileName.lastIndexOf('.');
    final name = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var candidate = '$destDir$sep$fileName';
    var n = 1;
    while (File(candidate).existsSync()) {
      candidate = '$destDir$sep$name-${n.toString().padLeft(2, '0')}$ext';
      n++;
    }
    return candidate;
  }
}
