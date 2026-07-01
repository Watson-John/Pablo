// search_service.dart — real catalog + retrieval-index backed search (Stage 9).
//
// Search runs over a list of [SearchDoc]s, each a catalog-derived projection of
// one photo (metadata, star, faces, tags, dominant colour). The app builds them
// from the native catalog + embedding index; tests construct them directly. This
// keeps the service PURE and unit-testable while the data stays catalog-backed.
//
// Text queries are ranked semantically via an injectable [TextRanker] (the app
// wires it to the native embedder; tests pass a deterministic one). Metadata,
// star, person, colour, and combined filters are applied first, then the
// candidate set is ranked. Nothing here is heuristic — the counts and results
// come from real data.

import '../../app/app_state.dart';
import '../../data/models.dart';

/// A catalog-derived, searchable projection of one photo.
class SearchDoc {
  SearchDoc({
    required this.photo,
    required this.assetId,
    this.starred = false,
    this.date,
    this.camera,
    this.lens,
    this.iso,
    this.aperture,
    this.focalLength,
    this.hasLocation = false,
    this.inAlbum = false,
    this.edited = false,
    this.isVideo = false,
    Set<String>? people,
    List<String>? tags,
    this.fileType = '',
    this.dominantRgb,
  })  : people = people ?? const {},
        tags = tags ?? const [];

  final Photo photo;
  final int assetId;
  final bool starred;
  final DateTime? date;
  final String? camera;
  final String? lens;
  final int? iso;
  final double? aperture;
  final double? focalLength;
  final bool hasLocation;
  final bool inAlbum;
  final bool edited;
  final bool isVideo;
  final Set<String> people;
  final List<String> tags;
  final String fileType; // 'JPEG' | 'PNG' | 'HEIC' | …
  final int? dominantRgb; // 0xRRGGBB, null if not yet indexed
}

/// Reorders candidate asset ids by relevance to a text query (best first). May
/// drop candidates it can't score. The app backs this with the native embedder;
/// tests inject a deterministic function.
typedef TextRanker = List<int> Function(String text, List<int> candidateIds);

class SearchService {
  SearchService({TextRanker? ranker}) : _ranker = ranker;
  final TextRanker? _ranker;

  /// True if [text]+[criteria] would run a search (vs. an empty/no-op query).
  static bool isActive(String text, AdvSearchCriteria? c) =>
      text.trim().isNotEmpty || (c != null && !c.isEmpty);

  /// Run [text] + [criteria] over [docs], returning matching photos ordered by
  /// semantic relevance (text query + ranker), colour proximity (colour query),
  /// or date descending.
  List<Photo> search(
    List<SearchDoc> docs, {
    String text = '',
    AdvSearchCriteria? criteria,
    int limit = 5000,
  }) {
    final color = _ColorMatcher.parse(criteria?.color);
    final matched = <SearchDoc>[
      for (final d in docs)
        if (_matches(d, criteria, color)) d,
    ];

    final query = text.trim();
    if (query.isNotEmpty && _ranker != null) {
      final ranked = _ranker(query, [for (final d in matched) d.assetId]);
      final byId = {for (final d in matched) d.assetId: d};
      final out = <Photo>[];
      final seen = <int>{};
      for (final id in ranked) {
        final d = byId[id];
        if (d != null && seen.add(id)) out.add(d.photo);
      }
      // Candidates the ranker dropped (e.g. not yet embedded) keep their place
      // at the tail so a partially-indexed library still shows metadata matches.
      for (final d in matched) {
        if (seen.add(d.assetId)) out.add(d.photo);
      }
      return out.take(limit).toList();
    }

    if (color != null) {
      matched.sort((a, b) => color
          .distance(a.dominantRgb)
          .compareTo(color.distance(b.dominantRgb)));
    } else {
      matched.sort((a, b) {
        final da = a.date, db = b.date;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da); // newest first
      });
    }
    return [for (final d in matched.take(limit)) d.photo];
  }

  bool _matches(SearchDoc d, AdvSearchCriteria? c, _ColorMatcher? color) {
    if (c == null) return true;
    if (c.starred && !d.starred) return false;
    if (c.videosOnly && !d.isVideo) return false;
    if (c.hasLocation && !d.hasLocation) return false;
    if (c.notInAlbum && d.inAlbum) return false;
    if (c.hasBeenEdited && !d.edited) return false;
    if (c.fileType != 'Any' && !_fileTypeMatch(d.fileType, c.fileType)) {
      return false;
    }
    if (!_dateMatches(d.date, c)) return false;
    if (c.camera != 'Any' &&
        (d.camera == null ||
            !d.camera!.toLowerCase().contains(c.camera.toLowerCase()))) {
      return false;
    }
    final lens = c.lens.trim();
    if (lens.isNotEmpty &&
        (d.lens == null ||
            !d.lens!.toLowerCase().contains(lens.toLowerCase()))) {
      return false;
    }
    if (!_inIntRange(d.iso, c.isoMin, c.isoMax)) return false;
    if (!_inNumRange(d.aperture, c.apertureMin, c.apertureMax)) return false;
    if (!_inNumRange(d.focalLength, c.focalMin, c.focalMax)) return false;
    if (!_tagsMatch(d.tags, c.tags)) return false;
    if (!_peopleMatch(d.people, c.people, c.peopleMatch)) return false;
    if (color != null && !color.matches(d.dominantRgb)) return false;
    return true;
  }

  static bool _fileTypeMatch(String docType, String want) {
    String norm(String s) {
      final l = s.toLowerCase();
      return l == 'jpg' ? 'jpeg' : l;
    }

    return norm(docType) == norm(want);
  }

  static bool _dateMatches(DateTime? date, AdvSearchCriteria c) {
    if (c.dateMode == 'any') return true;
    if (date == null) return false;
    switch (c.dateMode) {
      case 'range':
        final from = DateTime.tryParse(c.dateFrom);
        final to = DateTime.tryParse(c.dateTo);
        if (from != null && date.isBefore(from)) return false;
        if (to != null && date.isAfter(to.add(const Duration(days: 1)))) {
          return false;
        }
        return true;
      case 'specificMonth':
        return _monthIndex(c.specificMonth) == date.month;
      case 'dayOfMonth':
        final d = int.tryParse(c.dayOfMonth.trim());
        return d != null && d == date.day;
      case 'year':
        final y = int.tryParse(c.year.trim());
        return y != null && y == date.year;
      default:
        return true;
    }
  }

  static const _months = [
    'january', 'february', 'march', 'april', 'may', 'june',
    'july', 'august', 'september', 'october', 'november', 'december',
  ];
  static int _monthIndex(String name) => _months.indexOf(name.toLowerCase()) + 1;

  static bool _inIntRange(int? v, String minS, String maxS) {
    final min = int.tryParse(minS.trim());
    final max = int.tryParse(maxS.trim());
    if (min == null && max == null) return true;
    if (v == null) return false;
    if (min != null && v < min) return false;
    if (max != null && v > max) return false;
    return true;
  }

  static bool _inNumRange(double? v, String minS, String maxS) {
    final min = double.tryParse(minS.trim());
    final max = double.tryParse(maxS.trim());
    if (min == null && max == null) return true;
    if (v == null) return false;
    if (min != null && v < min) return false;
    if (max != null && v > max) return false;
    return true;
  }

  static bool _tagsMatch(List<String> tags, String csv) {
    final want = [
      for (final t in csv.split(','))
        if (t.trim().isNotEmpty) t.trim().toLowerCase(),
    ];
    if (want.isEmpty) return true;
    final have = {for (final t in tags) t.toLowerCase()};
    return want.every(have.contains);
  }

  static bool _peopleMatch(Set<String> have, Set<String> want, String mode) {
    if (want.isEmpty) return true;
    final low = {for (final p in have) p.toLowerCase()};
    final w = {for (final p in want) p.toLowerCase()};
    return mode == 'and' ? w.every(low.contains) : w.any(low.contains);
  }
}

/// Named-colour matcher over 0xRRGGBB dominant colours. Chromatic colours match
/// by hue; achromatic (white/black/gray) by luminance/saturation.
class _ColorMatcher {
  _ColorMatcher._(this._name, this._hue);

  final String _name;
  final double _hue; // chromatic centre in degrees; ignored for achromatic

  static const _hues = <String, double>{
    'red': 0, 'orange': 30, 'yellow': 55, 'green': 120,
    'cyan': 180, 'blue': 220, 'purple': 285, 'pink': 330,
  };
  static const _achromatic = {'white', 'black', 'gray', 'grey'};

  static _ColorMatcher? parse(String? name) {
    if (name == null) return null;
    final n = name.trim().toLowerCase();
    if (n.isEmpty || n == 'any') return null;
    if (_hues.containsKey(n)) return _ColorMatcher._(n, _hues[n]!);
    if (_achromatic.contains(n)) return _ColorMatcher._(n, -1);
    return null;
  }

  bool matches(int? rgb) => distance(rgb) < 60.0;

  /// A sortable distance to the target (smaller = closer). null/unindexed
  /// colours sort last.
  double distance(int? rgb) {
    if (rgb == null || rgb < 0) return 1e9;
    final r = ((rgb >> 16) & 0xff) / 255.0;
    final g = ((rgb >> 8) & 0xff) / 255.0;
    final b = (rgb & 0xff) / 255.0;
    final mx = [r, g, b].reduce((a, c) => a > c ? a : c);
    final mn = [r, g, b].reduce((a, c) => a < c ? a : c);
    final v = mx;
    final sat = mx <= 0 ? 0.0 : (mx - mn) / mx;

    if (_name == 'white') return v > 0.72 && sat < 0.22 ? (1 - v) * 100 : 1e6;
    if (_name == 'black') return v < 0.25 ? v * 100 : 1e6;
    if (_name == 'gray' || _name == 'grey') {
      return (sat < 0.18 && v >= 0.2 && v <= 0.8) ? sat * 100 : 1e6;
    }

    if (sat < 0.15) return 1e6; // too washed-out to be this hue
    double h;
    final d = mx - mn;
    if (d < 1e-6) {
      h = 0;
    } else if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
    if (h < 0) h += 360;
    var dh = (h - _hue).abs();
    if (dh > 180) dh = 360 - dh; // wrap
    return dh;
  }
}
