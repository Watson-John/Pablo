// dedup_repository.dart — the Find Duplicates UI's data source.
//
// Mirrors face_repository.dart's seam. The default [DartDedupRepository] does
// REAL exact-duplicate detection in Dart (content hashing, off the UI thread)
// on photos that have a real file path, and falls back to a synthetic mock for
// path-less gradient photos so the workflow still demos. Visually-similar groups
// are still synthetic until photo_core's native DedupService (SSCD) is wired —
// at which point a NativeDedupRepository slots in behind this same interface.

import 'dart:isolate';

import '../../data/models.dart';
import '../../features/find_duplicates/dedup_models.dart';
import '../../features/find_duplicates/dedup_scanner.dart';

abstract interface class DedupRepository {
  /// True when visual-similarity is backed by the live native (SSCD) pipeline.
  bool get isLive;

  /// Byte/perceptual-identical groups. Cheap — the pass that runs on import.
  Future<List<DupCluster>> findExact(List<Photo> photos);

  /// Visual near-duplicate groups at the given cosine [threshold] (0..1).
  /// Lower threshold ⇒ more/larger clusters.
  Future<List<DupCluster>> findSimilar(List<Photo> photos, double threshold);
}

/// Picks the live repository when a dedup-capable native engine is wired, else
/// the Dart implementation. (Native wiring arrives with photo_core's DedupService.)
DedupRepository createDedupRepository() => const DartDedupRepository();

class DartDedupRepository implements DedupRepository {
  const DartDedupRepository();

  @override
  bool get isLive => false; // exact is real; similar is still synthetic

  @override
  Future<List<DupCluster>> findExact(List<Photo> photos) async {
    final real = [
      for (final p in photos) (id: p.id, path: p.filePath),
    ];
    if (real.isEmpty) return _mockExact(photos); // gradient-mock mode
    // Hash off the UI thread; byte-identical files group together.
    final groups = await Isolate.run(() => findExactGroups(real));
    return [
      for (final ids in groups)
        DupCluster(
          id: 'exact-${ids.first}',
          kind: DupKind.exact,
          score: 1.0,
          photoIds: ids,
          keeperId: ids.first,
        ),
    ];
  }

  @override
  Future<List<DupCluster>> findSimilar(List<Photo> photos, double threshold) async {
    // Synthetic until SSCD is wired: bucket into "scenes" with fixed scores so
    // the slider reveals more/larger clusters as the threshold drops.
    final ids = [for (final p in photos) p.id];
    final scenes = <int, List<String>>{};
    final buckets = (ids.length ~/ 3).clamp(1, 4000);
    for (final id in ids) {
      scenes.putIfAbsent(_h(id) % buckets, () => []).add(id);
    }
    final out = <DupCluster>[];
    scenes.forEach((key, members) {
      if (members.length < 2) return;
      final score = 0.55 + (key.abs() % 45) / 100.0; // 0.55..0.99
      if (score + 1e-9 < threshold) return;
      out.add(DupCluster(
        id: 'sim-$key',
        kind: DupKind.similar,
        score: score,
        photoIds: members,
        keeperId: members.first,
      ));
    });
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  // Synthetic exact pairs for the gradient mock (no real files to hash).
  List<DupCluster> _mockExact(List<Photo> photos) {
    final marked = [for (final p in photos) if (_h(p.id) % 20 == 0) p.id];
    final out = <DupCluster>[];
    for (var i = 0; i + 1 < marked.length; i += 2) {
      out.add(DupCluster(
        id: 'exact-${marked[i]}',
        kind: DupKind.exact,
        score: 1.0,
        photoIds: [marked[i], marked[i + 1]],
        keeperId: marked[i],
      ));
    }
    return out;
  }

  static int _h(String s) => s.hashCode & 0x7fffffff;
}
