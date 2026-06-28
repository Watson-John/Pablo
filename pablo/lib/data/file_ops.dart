// file_ops.dart — the filesystem seam Phase B consumers use to actually place
// files: copy/move with parent-dir creation, a cross-device move fallback, and
// a size-based verify. Plus [applyPlan], which executes a planner [FilingPlan]
// under a destination root. dart:io only, defensive — no catalog logic here.

import 'dart:io';

import 'scheme_planner.dart';

class FileOpResult {
  const FileOpResult(this.ok, [this.error]);
  final bool ok;
  final Object? error;
}

/// Outcome of applying one [FilingEntry].
class FileApplyResult {
  const FileApplyResult(this.entry, this.destPath, this.ok, [this.error]);
  final FilingEntry entry;
  final String destPath;
  final bool ok;
  final Object? error;
}

class FileOps {
  /// Copy [src] → [destPath], creating parent dirs. Fails if the destination
  /// already exists (callers resolve collisions via the planner first).
  static FileOpResult copy(String src, String destPath, {bool verify = true}) {
    try {
      final dest = File(destPath);
      if (dest.existsSync()) return const FileOpResult(false, 'destination exists');
      dest.parent.createSync(recursive: true);
      File(src).copySync(destPath);
      if (verify && !_sameSize(src, destPath)) {
        return const FileOpResult(false, 'size mismatch after copy');
      }
      return const FileOpResult(true);
    } catch (e) {
      return FileOpResult(false, e);
    }
  }

  /// Move [src] → [destPath]. Tries an atomic rename; on a cross-device error
  /// falls back to a verified copy + delete.
  static FileOpResult move(String src, String destPath, {bool verify = true}) {
    try {
      final dest = File(destPath);
      if (dest.existsSync()) return const FileOpResult(false, 'destination exists');
      dest.parent.createSync(recursive: true);
      try {
        File(src).renameSync(destPath);
        return const FileOpResult(true);
      } on FileSystemException {
        File(src).copySync(destPath); // different volume → copy then delete
        if (verify && !_sameSize(src, destPath)) {
          return const FileOpResult(false, 'size mismatch after copy');
        }
        File(src).deleteSync();
        return const FileOpResult(true);
      }
    } catch (e) {
      return FileOpResult(false, e);
    }
  }

  /// Execute [plan] under [destRoot]. When [move] is true sources are moved,
  /// otherwise copied. Never throws — failures are reported per entry.
  static List<FileApplyResult> applyPlan(
    FilingPlan plan,
    String destRoot, {
    bool move = false,
  }) {
    final sep = Platform.pathSeparator;
    return [
      for (final e in plan.entries)
        () {
          final destPath = '$destRoot$sep${e.relPath.replaceAll('/', sep)}';
          final r = move
              ? FileOps.move(e.sourcePath, destPath)
              : FileOps.copy(e.sourcePath, destPath);
          return FileApplyResult(e, destPath, r.ok, r.error);
        }()
    ];
  }

  static bool _sameSize(String a, String b) {
    try {
      return File(a).lengthSync() == File(b).lengthSync();
    } catch (_) {
      return false;
    }
  }
}
