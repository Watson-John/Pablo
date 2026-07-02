// fuzzy_match.dart — a small, dependency-free subsequence matcher for the
// Move-to-Folder palette (and reusable for any "type to filter paths" list).
//
// Every character of the query must appear in order in the candidate
// (case-insensitive). Score rewards word-boundary hits (after a separator or
// space) and consecutive runs, and penalizes gaps; a match inside the
// basename outweighs one buried in the parent path. Returns the matched
// candidate indices too, so callers can bold them.

class FuzzyResult {
  const FuzzyResult(this.score, this.matched);

  /// Higher is better. Only meaningful when [matched] is non-null.
  final double score;

  /// Indices into the candidate string that the query matched, or null when
  /// the query is not a subsequence of the candidate.
  final List<int>? matched;

  bool get isMatch => matched != null;
}

const double _wordBoundaryBonus = 3;
const double _consecutiveBonus = 2;
const double _gapPenalty = 1;
const double _basenameWeight = 2;

bool _isBoundary(String s, int i) {
  if (i == 0) return true;
  final prev = s.codeUnitAt(i - 1);
  // '/', '\', '_', '-', ' ', '.'
  return prev == 0x2F ||
      prev == 0x5C ||
      prev == 0x5F ||
      prev == 0x2D ||
      prev == 0x20 ||
      prev == 0x2E;
}

/// Score [query] against [candidate]. An empty query matches everything with
/// score 0 (callers keep their default ordering). Non-subsequence → no match.
///
/// Because a greedy left-to-right match can land the query on the wrong
/// occurrence (e.g. "trip" catching the "t" in "phoTos"), we score the whole
/// path AND the basename in isolation, then keep whichever is stronger — so a
/// clean basename hit is never lost to an earlier accidental one in the parent
/// path. The basename match carries a weight bonus.
FuzzyResult fuzzyMatch(String query, String candidate) {
  if (query.isEmpty) return const FuzzyResult(0, <int>[]);

  final full = _scoreWithin(query, candidate, 0, weight: 1);

  var sep = -1;
  for (var i = 0; i < candidate.length; i++) {
    final u = candidate.codeUnitAt(i);
    if (u == 0x2F || u == 0x5C) sep = i;
  }
  final baseStart = sep + 1;
  final base = baseStart > 0
      ? _scoreWithin(query, candidate.substring(baseStart), baseStart,
          weight: _basenameWeight)
      : null;

  if (base != null && base.isMatch) {
    if (!full.isMatch || base.score >= full.score) return base;
  }
  return full;
}

/// Greedy subsequence match of [query] within [text], with match indices
/// offset by [base] (so a basename substring reports absolute indices) and the
/// final score multiplied by [weight]. Boundary detection uses the offset text.
FuzzyResult _scoreWithin(String query, String text, int base,
    {required double weight}) {
  final q = query.toLowerCase();
  final c = text.toLowerCase();
  final matched = <int>[];
  var score = 0.0;
  var ci = 0;
  var lastMatch = -2;
  for (var qi = 0; qi < q.length; qi++) {
    final target = q.codeUnitAt(qi);
    var found = -1;
    for (var k = ci; k < c.length; k++) {
      if (c.codeUnitAt(k) == target) {
        found = k;
        break;
      }
    }
    if (found < 0) return const FuzzyResult(0, null); // not a subsequence
    var s = 1.0;
    if (_isBoundary(text, found)) s += _wordBoundaryBonus;
    if (found == lastMatch + 1) s += _consecutiveBonus;
    if (found > lastMatch + 1 && lastMatch >= 0) {
      s -= _gapPenalty * (found - lastMatch - 1).clamp(0, 3);
    }
    score += s;
    matched.add(base + found);
    lastMatch = found;
    ci = found + 1;
  }
  return FuzzyResult(score * weight, matched);
}

/// Rank [candidates] by fuzzy score against [query], dropping non-matches.
/// A tie (or empty query) preserves the input order — callers pre-sort by
/// their own priority (pins, recents) so those survive an empty query.
List<T> fuzzyRank<T>(
  String query,
  List<T> candidates,
  String Function(T) keyOf,
) {
  if (query.isEmpty) return List<T>.of(candidates);
  final scored = <(int, double, T)>[];
  for (var i = 0; i < candidates.length; i++) {
    final r = fuzzyMatch(query, keyOf(candidates[i]));
    if (r.isMatch) scored.add((i, r.score, candidates[i]));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$1.compareTo(b.$1); // stable
  });
  return [for (final s in scored) s.$3];
}
