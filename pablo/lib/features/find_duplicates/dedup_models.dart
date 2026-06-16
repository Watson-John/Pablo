// Models + ranking for the Find Duplicates workflow.
//
// A [DupCluster] is a set of photo ids the engine believes are the same image.
// Exact clusters come from content/perceptual hashing (cheap, run on import);
// similar clusters come from the SSCD visual-similarity pass (on demand, with a
// user-tunable threshold). Ranking picks the "keeper" so the user can auto-keep
// the best copy and quarantine the rest with minimal manual checking.

import '../../data/models.dart';
import 'dedup_meta.dart';

/// What the user scoped the scan to.
enum DedupScopeKind { selection, folders, library }

/// Which detection produced a cluster.
enum DupKind { exact, similar }

/// Auto-selection rule for choosing the keeper within each cluster.
enum KeeperRule { newest, oldest, largest, highestRes }

extension KeeperRuleLabel on KeeperRule {
  String get label => switch (this) {
        KeeperRule.newest => 'Newest (EXIF date)',
        KeeperRule.oldest => 'Oldest (EXIF date)',
        KeeperRule.largest => 'Largest file',
        KeeperRule.highestRes => 'Highest resolution',
      };
}

/// A group of duplicate/near-duplicate photos with a suggested keeper.
class DupCluster {
  const DupCluster({
    required this.id,
    required this.kind,
    required this.score,
    required this.photoIds,
    required this.keeperId,
  });

  final String id;
  final DupKind kind;

  /// Visual similarity in [0,1]. 1.0 for exact (byte/perceptual) matches.
  final double score;

  /// Member photo ids, keeper first after [rankedBy].
  final List<String> photoIds;

  /// The id the workflow proposes to keep (others are quarantine candidates).
  final String keeperId;

  /// Photos that would be quarantined if the user accepts the suggestion.
  Iterable<String> get discards => photoIds.where((p) => p != keeperId);

  DupCluster copyWith({List<String>? photoIds, String? keeperId}) => DupCluster(
        id: id,
        kind: kind,
        score: score,
        photoIds: photoIds ?? this.photoIds,
        keeperId: keeperId ?? this.keeperId,
      );

  /// Re-rank members by [rule] using real file metadata (via [photos]),
  /// returning a copy with the best keeper first.
  DupCluster rankedBy(KeeperRule rule, Map<String, Photo> photos) {
    final ordered = [...photoIds]
      ..sort((a, b) => _rankValue(photos[b], rule).compareTo(_rankValue(photos[a], rule)));
    return copyWith(
      photoIds: ordered,
      keeperId: ordered.isEmpty ? keeperId : ordered.first,
    );
  }
}

/// Higher = better keeper under [rule]. Unknown photos rank lowest.
int _rankValue(Photo? p, KeeperRule rule) {
  if (p == null) return -1 << 62;
  return switch (rule) {
    KeeperRule.newest => DedupMeta.dateKey(p),
    KeeperRule.oldest => -DedupMeta.dateKey(p),
    KeeperRule.largest => DedupMeta.bytes(p),
    KeeperRule.highestRes => DedupMeta.resolution(p),
  };
}
