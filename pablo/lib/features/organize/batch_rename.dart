// batch_rename.dart — the pure planning core for token-based batch rename.
// Reuses the storage-scheme engine (renderScheme) so tokens, date sources,
// case, and counters behave identically to the storage-scheme builder. Renames
// are same-directory (from → dir/newName.ext); collisions — both within the
// batch and against files already on disk — get a `-NN` suffix via the
// planner's suffix-aware fitFilename. Identity renames (new == old) are dropped.

import 'dart:io';

import '../../data/move_service.dart';
import '../../data/scheme_engine.dart';
import '../../data/scheme_options.dart';
import '../../data/storage_scheme.dart';

/// One preview row: the source path and the leaf name (incl. extension) it
/// would take.
class RenamePreview {
  const RenamePreview(this.from, this.newName, {required this.conflictResolved});
  final String from;
  final String newName; // leaf name incl. extension

  String get oldName => from.split(RegExp(r'[/\\]')).last;
  bool get isIdentity => oldName == newName;

  /// True when a `-NN` suffix was applied to dodge a collision.
  final bool conflictResolved;

  /// The absolute destination path (same directory as [from]).
  String get toPath {
    final cut = from.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? newName : '${from.substring(0, cut + 1)}$newName';
  }
}

/// Build the rename plan for [paths]. [metaOf] supplies PhotoMeta (injected in
/// tests; `photoMetaForPath` in the app). [exists] probes on-disk collisions
/// (defaults to a real filesystem check). Deterministic in [paths] order so
/// the counter and collision suffixes are stable.
List<RenamePreview> planRename({
  required List<String> paths,
  required PhotoMeta Function(String) metaOf,
  required PatternLane lane,
  SchemeOptions options = const SchemeOptions(),
  int startCounter = 1,
  bool Function(String)? exists,
}) {
  final probe = exists ?? (p) => File(p).existsSync();
  final scheme = StorageScheme(
    id: 'rename',
    name: 'rename',
    folderLevels: const [],
    filename: lane,
    options: options,
  );
  final counter = CounterState(startCounter);
  final used = <String>{}; // dest paths claimed earlier in this batch
  final out = <RenamePreview>[];

  for (final path in paths) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    final prefix = cut < 0 ? '' : path.substring(0, cut + 1); // keeps the sep
    final meta = metaOf(path);
    final r = renderScheme(scheme, meta, counter);

    // Resolve collisions: the source's own path is fine (identity), but dodge
    // any OTHER claimed/on-disk name with a numbered suffix.
    var stem = r.filename;
    var candidate = '$prefix$stem${r.ext}';
    var n = 1;
    while (candidate != path && (used.contains(candidate) || probe(candidate))) {
      stem = fitFilename(r.filename, r.ext,
          suffix: '-${n.toString().padLeft(2, '0')}');
      candidate = '$prefix$stem${r.ext}';
      n++;
    }
    used.add(candidate);
    out.add(RenamePreview(path, '$stem${r.ext}', conflictResolved: n > 1));
  }
  return out;
}

/// The applicable (non-identity) moves from a plan.
List<PlannedMove> movesFrom(List<RenamePreview> plan) => [
      for (final row in plan)
        if (!row.isIdentity) PlannedMove(row.from, row.toPath),
    ];
