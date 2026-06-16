// Models + ranking for the Find Duplicates workflow.
//
// A [DupCluster] is a set of photo ids the engine believes are the same image.
// Exact clusters come from content/perceptual hashing (cheap, run on import);
// similar clusters come from the SSCD visual-similarity pass (on demand, with a
// user-tunable threshold). Ranking picks the "keeper" so the user can auto-keep
// the best copy and quarantine the rest with minimal manual checking.

import '../../data/mock/photo_factory.dart' show getPhotoExif;

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

  /// Re-rank members by [rule], returning a copy with the keeper first.
  DupCluster rankedBy(KeeperRule rule) {
    final ordered = [...photoIds]..sort((a, b) => _compare(b, a, rule));
    return copyWith(photoIds: ordered, keeperId: ordered.first);
  }
}

// ── ranking primitives (parse the mock/real EXIF strings into comparables) ──

int _resolution(String id) {
  final e = getPhotoExif(id);
  return e.width * e.height;
}

/// "5 MB" / "820 KB" / "1.2 GB" → bytes. Best-effort.
int _fileBytes(String id) {
  final s = getPhotoExif(id).fileSize.trim().toUpperCase();
  final m = RegExp(r'([\d.]+)\s*(KB|MB|GB|B)?').firstMatch(s);
  if (m == null) return 0;
  final v = double.tryParse(m.group(1)!) ?? 0;
  return switch (m.group(2)) {
    'GB' => (v * 1024 * 1024 * 1024).round(),
    'MB' => (v * 1024 * 1024).round(),
    'KB' => (v * 1024).round(),
    _ => v.round(),
  };
}

/// "YYYY-MM-DD" → sortable int (0 if unparseable).
int _dateKey(String id) {
  final d = getPhotoExif(id).date;
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(d);
  if (m == null) return 0;
  return int.parse('${m.group(1)}${m.group(2)}${m.group(3)}');
}

/// Returns >0 if `a` ranks above `b` under `rule` (i.e. `a` is the better keeper).
int _compare(String a, String b, KeeperRule rule) => switch (rule) {
      KeeperRule.newest => _dateKey(a).compareTo(_dateKey(b)),
      KeeperRule.oldest => _dateKey(b).compareTo(_dateKey(a)),
      KeeperRule.largest => _fileBytes(a).compareTo(_fileBytes(b)),
      KeeperRule.highestRes => _resolution(a).compareTo(_resolution(b)),
    };
