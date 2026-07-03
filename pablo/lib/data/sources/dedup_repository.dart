// dedup_repository.dart — the Find Duplicates UI's data source.
//
// Mirrors face_repository.dart's seam. The default [DartDedupRepository] does
// REAL exact-duplicate detection in Dart (content hashing, off the UI thread)
// on photos that have a real file path, and falls back to a synthetic mock for
// path-less gradient photos so the workflow still demos. Visually-similar groups
// are still synthetic until photo_core's native DedupService (SSCD) is wired —
// at which point a NativeDedupRepository slots in behind this same interface.

import 'dart:isolate';

import 'package:photo_native/photo_native.dart' show Engine;

import '../../data/models.dart';
import '../../features/find_duplicates/dedup_models.dart';
import '../../features/find_duplicates/dedup_scanner.dart';
import '../../utils/asset_id.dart';

abstract interface class DedupRepository {
  /// True when visual-similarity is backed by the live native (SSCD) pipeline.
  bool get isLive;

  /// Byte/perceptual-identical groups. Cheap — the pass that runs on import.
  Future<List<DupCluster>> findExact(List<Photo> photos);

  /// Visual near-duplicate groups at the given cosine [threshold] (0..1).
  /// Lower threshold ⇒ more/larger clusters.
  Future<List<DupCluster>> findSimilar(List<Photo> photos, double threshold);
}

/// Picks the live repository when a native engine is wired (visual similarity
/// = pairwise semantic cosine in photo_core), else the Dart implementation
/// (real exact-dupes, synthetic similar).
DedupRepository createDedupRepository({Engine? engine}) => engine == null
    ? const DartDedupRepository()
    : NativeDedupRepository(engine);

/// Live repository: exact stays the Dart content-hash pass (it is already
/// real); visually-similar comes from photo_dedup_similar — pairwise SigLIP2
/// cosine over the scope's catalog embeddings. That reads as "similar scene"
/// rather than SSCD's "same photo re-encoded", which is honest-but-useful
/// until an SSCD analyzer slots in behind this same interface (FUTURE_WORK).
class NativeDedupRepository implements DedupRepository {
  const NativeDedupRepository(this._engine);
  final Engine _engine;

  @override
  bool get isLive => true;

  @override
  Future<List<DupCluster>> findExact(List<Photo> photos) =>
      const DartDedupRepository().findExact(photos);

  @override
  Future<List<DupCluster>> findSimilar(
      List<Photo> photos, double threshold) async {
    // Map scope photos → hydrated catalog ids (hash-fallback ids never cross
    // the FFI); remember the inverse to translate pairs back.
    final idToPhoto = <int, String>{};
    for (final p in photos) {
      final cid = catalogIdForPath(p.filePath);
      if (cid != null) idToPhoto[cid] = p.id;
    }
    if (idToPhoto.length < 2) return const [];
    final pairs = _engine.dedupSimilar(idToPhoto.keys.toList(), threshold);
    if (pairs.isEmpty) return const [];

    // Union-find the pairs into clusters; a cluster's score is its strongest
    // pair so the review slider keeps its meaning (higher = tighter).
    final parent = <int, int>{};
    int find(int x) {
      var r = parent[x] ?? x;
      while (r != (parent[r] ?? r)) {
        r = parent[r] ?? r;
      }
      parent[x] = r;
      return r;
    }

    void union(int a, int b) => parent[find(a)] = find(b);
    for (final p in pairs) {
      union(p.a, p.b);
    }
    final members = <int, List<int>>{};
    for (final id in {
      for (final p in pairs) ...[p.a, p.b]
    }) {
      members.putIfAbsent(find(id), () => []).add(id);
    }
    final best = <int, double>{};
    for (final p in pairs) {
      final root = find(p.a);
      if (p.score > (best[root] ?? 0)) best[root] = p.score;
    }
    return [
      for (final e in members.entries)
        if (e.value.length >= 2)
          DupCluster(
            id: 'sim-${e.key}',
            kind: DupKind.similar,
            score: (best[e.key] ?? threshold).clamp(0.0, 1.0),
            photoIds: [for (final id in e.value) idToPhoto[id]!],
            keeperId: idToPhoto[e.value.first]!,
          ),
    ];
  }
}

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
