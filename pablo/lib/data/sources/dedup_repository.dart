// dedup_repository.dart — the Find Duplicates UI's data source.
//
// Mirrors face_repository.dart's seam: the staged workflow talks to a
// [DedupRepository] read from AppScope, and [createDedupRepository] picks the
// implementation by what's wired.
//   * [MockDedupRepository] — synthesizes plausible exact + similar clusters
//     from the scoped photo set so the full staged UI is demonstrable with the
//     native backend off (same role MockFaceRepository plays for People).
//   * NativeDedupRepository — added in the native-engine phase: submits a scan
//     to photo_core's DedupService and maps the read-back clusters here.

import '../../features/find_duplicates/dedup_models.dart';

abstract interface class DedupRepository {
  /// True when backed by the live native (SSCD/FAISS) pipeline.
  bool get isLive;

  /// Byte/perceptual-identical groups within [photoIds]. Cheap — this is the
  /// pass that runs automatically on import. score == 1.0.
  Future<List<DupCluster>> findExact(List<String> photoIds);

  /// Visual near-duplicate groups at the given cosine [threshold] (0..1).
  /// Lower threshold ⇒ more/larger clusters. Backed by SSCD when live.
  Future<List<DupCluster>> findSimilar(List<String> photoIds, double threshold);
}

/// Picks the live repository when a dedup-capable engine is wired, else the
/// mock. (Native wiring arrives with photo_core's DedupService.)
DedupRepository createDedupRepository() => const MockDedupRepository();

// ---------------------------------------------------------------------------
// Mock — deterministic synthetic clusters so the workflow is fully exercisable.
// ---------------------------------------------------------------------------

class MockDedupRepository implements DedupRepository {
  const MockDedupRepository();

  @override
  bool get isLive => false;

  @override
  Future<List<DupCluster>> findExact(List<String> photoIds) async {
    // ~1 in 20 photos forms an exact pair with the next such photo.
    final marked = [for (final id in photoIds) if (_h(id) % 20 == 0) id];
    final clusters = <DupCluster>[];
    for (var i = 0; i + 1 < marked.length; i += 2) {
      final members = [marked[i], marked[i + 1]];
      // a third identical copy now and then
      if (i + 2 < marked.length && _h(marked[i]) % 3 == 0) members.add(marked[i + 2]);
      clusters.add(DupCluster(
        id: 'exact-${marked[i]}',
        kind: DupKind.exact,
        score: 1.0,
        photoIds: members,
        keeperId: members.first,
      ).rankedBy(KeeperRule.highestRes));
    }
    return clusters;
  }

  @override
  Future<List<DupCluster>> findSimilar(List<String> photoIds, double threshold) async {
    // Bucket photos into synthetic "scenes"; each scene has a fixed similarity
    // score, so lowering the threshold reveals more (and larger) clusters.
    final scenes = <int, List<String>>{};
    final n = photoIds.length;
    final buckets = (n ~/ 3).clamp(1, 4000);
    for (final id in photoIds) {
      scenes.putIfAbsent(_h(id) % buckets, () => []).add(id);
    }
    final clusters = <DupCluster>[];
    scenes.forEach((key, members) {
      if (members.length < 2) return;
      final score = 0.55 + (key.abs() % 45) / 100.0; // 0.55..0.99
      if (score + 1e-9 < threshold) return;
      clusters.add(DupCluster(
        id: 'sim-$key',
        kind: DupKind.similar,
        score: score,
        photoIds: members,
        keeperId: members.first,
      ).rankedBy(KeeperRule.highestRes));
    });
    clusters.sort((a, b) => b.score.compareTo(a.score));
    return clusters;
  }

  // Stable non-negative hash for an id (mock determinism only).
  static int _h(String s) => s.hashCode & 0x7fffffff;
}
