// storage_scheme.dart — the data model for a "storage scheme": how imported
// photos are filed into folders and renamed. Adapted from DIM (Digital Image
// Mover): a scheme is a folder-path pattern + a filename pattern, both built
// from one shared token vocabulary, plus a bag of processing options
// ([SchemeOptions], in scheme_options.dart).
//
// This is pure data — no I/O, no rendering. scheme_engine.dart turns a scheme +
// a photo's metadata into a concrete relative path; scheme_store.dart persists
// schemes as JSON; the drag-and-drop builder (features/organize) edits it.
//
// Location tokens (country/state/city/lat/lon) are intentionally absent in v1:
// Pablo reads raw GPS but has no reverse-geocoder yet.

import '../components/pablo_icon.dart';
import 'scheme_options.dart';

/// A token's category — drives palette grouping and chip color.
enum TokenGroup { date, camera, file, counter, prompt }

/// Whether a token can be produced from what Pablo knows today.
enum TokenFeasibility {
  /// Available now from EXIF / filesystem / engine state.
  ready,

  /// Needs EXIF fields Pablo doesn't parse yet (camera owner, unique id).
  needsExif,
}

/// The vocabulary of dynamic tokens. Literal text is a separate [Segment].
enum TokenType {
  year4,
  year2,
  quarter,
  month,
  monthAbbr,
  day,
  hour,
  minute,
  second,
  make,
  model,
  owner,
  uniqueId,
  originalName,
  parentFolder,
  counter,
  prompt,
}

/// Static, user-facing metadata for a [TokenType] — drives the palette.
class TokenSpec {
  const TokenSpec({
    required this.type,
    required this.label,
    required this.group,
    required this.icon,
    required this.example,
    this.feasibility = TokenFeasibility.ready,
    this.supportsPad = false,
  });

  final TokenType type;
  final String label;
  final TokenGroup group;
  final PabloIconName icon;

  /// A representative rendering shown on the palette chip ("2024", "Mar"…).
  final String example;
  final TokenFeasibility feasibility;

  /// True when the token takes a minimum-digits pad (the counter).
  final bool supportsPad;

  bool get isReady => feasibility == TokenFeasibility.ready;

  static TokenSpec of(TokenType t) => _specs[t]!;
  static List<TokenSpec> inGroup(TokenGroup g) =>
      _specs.values.where((s) => s.group == g).toList(growable: false);
}

const Map<TokenType, TokenSpec> _specs = {
  TokenType.year4: TokenSpec(type: TokenType.year4, label: 'Year', group: TokenGroup.date, icon: PabloIconName.calendar, example: '2024'),
  TokenType.year2: TokenSpec(type: TokenType.year2, label: 'Year (2-digit)', group: TokenGroup.date, icon: PabloIconName.calendar, example: '24'),
  TokenType.quarter: TokenSpec(type: TokenType.quarter, label: 'Quarter', group: TokenGroup.date, icon: PabloIconName.calendar, example: '1'),
  TokenType.month: TokenSpec(type: TokenType.month, label: 'Month', group: TokenGroup.date, icon: PabloIconName.calendar, example: '03'),
  TokenType.monthAbbr: TokenSpec(type: TokenType.monthAbbr, label: 'Month (Jan)', group: TokenGroup.date, icon: PabloIconName.calendar, example: 'Mar'),
  TokenType.day: TokenSpec(type: TokenType.day, label: 'Day', group: TokenGroup.date, icon: PabloIconName.calendar, example: '15'),
  TokenType.hour: TokenSpec(type: TokenType.hour, label: 'Hour', group: TokenGroup.date, icon: PabloIconName.clock, example: '14'),
  TokenType.minute: TokenSpec(type: TokenType.minute, label: 'Minute', group: TokenGroup.date, icon: PabloIconName.clock, example: '30'),
  TokenType.second: TokenSpec(type: TokenType.second, label: 'Second', group: TokenGroup.date, icon: PabloIconName.clock, example: '05'),
  TokenType.make: TokenSpec(type: TokenType.make, label: 'Camera make', group: TokenGroup.camera, icon: PabloIconName.camera, example: 'Canon'),
  TokenType.model: TokenSpec(type: TokenType.model, label: 'Camera model', group: TokenGroup.camera, icon: PabloIconName.camera, example: 'EOS R5'),
  TokenType.owner: TokenSpec(type: TokenType.owner, label: 'Camera owner', group: TokenGroup.camera, icon: PabloIconName.person, example: 'Owner', feasibility: TokenFeasibility.needsExif),
  TokenType.uniqueId: TokenSpec(type: TokenType.uniqueId, label: 'Unique ID', group: TokenGroup.camera, icon: PabloIconName.tag, example: 'A1B2C3', feasibility: TokenFeasibility.needsExif),
  TokenType.originalName: TokenSpec(type: TokenType.originalName, label: 'Original name', group: TokenGroup.file, icon: PabloIconName.copy, example: 'IMG_1234'),
  TokenType.parentFolder: TokenSpec(type: TokenType.parentFolder, label: 'Parent folder', group: TokenGroup.file, icon: PabloIconName.folder, example: 'Vacation'),
  TokenType.counter: TokenSpec(type: TokenType.counter, label: 'Counter', group: TokenGroup.counter, icon: PabloIconName.sort, example: '001', supportsPad: true),
  TokenType.prompt: TokenSpec(type: TokenType.prompt, label: 'Event / label', group: TokenGroup.prompt, icon: PabloIconName.sparkle, example: 'Event'),
};

/// One element of a pattern lane: either a dynamic [TokenSegment] or fixed
/// [LiteralSegment] text.
sealed class Segment {
  const Segment();

  Map<String, dynamic> toJson();

  static Segment fromJson(Map<String, dynamic> j) => j['t'] == 'lit'
      ? LiteralSegment(j['v'] as String? ?? '')
      : TokenSegment(TokenType.values.byName(j['k'] as String),
          pad: (j['p'] as num?)?.toInt());
}

class TokenSegment extends Segment {
  const TokenSegment(this.type, {this.pad});

  final TokenType type;

  /// Minimum digits (the counter's zero-pad); null = the token's natural width.
  final int? pad;

  TokenSpec get spec => TokenSpec.of(type);

  @override
  Map<String, dynamic> toJson() =>
      {'t': 'tok', 'k': type.name, if (pad != null) 'p': pad};
}

class LiteralSegment extends Segment {
  const LiteralSegment(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => {'t': 'lit', 'v': text};
}

/// An ordered run of segments. One folder level is a lane; the filename is a
/// lane. A "/" between folder levels is implied by the level boundary, so lanes
/// never contain path separators themselves.
class PatternLane {
  PatternLane(this.segments);

  factory PatternLane.empty() => PatternLane(<Segment>[]);

  factory PatternLane.of(List<Segment> segments) => PatternLane(segments);

  factory PatternLane.fromJson(List<dynamic> j) => PatternLane(j
      .map((e) => Segment.fromJson((e as Map).cast<String, dynamic>()))
      .toList());

  final List<Segment> segments;

  bool get isEmpty => segments.isEmpty;

  PatternLane clone() => PatternLane(List<Segment>.of(segments));

  List<Map<String, dynamic>> toJson() =>
      segments.map((s) => s.toJson()).toList();
}

/// A complete, named storage scheme.
class StorageScheme {
  StorageScheme({
    required this.id,
    required this.name,
    required this.folderLevels,
    required this.filename,
    this.options = const SchemeOptions(),
  });

  factory StorageScheme.fromJson(Map<String, dynamic> j) => StorageScheme(
        id: j['id'] as String,
        name: j['name'] as String,
        folderLevels: (j['folders'] as List<dynamic>)
            .map((l) => PatternLane.fromJson(l as List<dynamic>))
            .toList(),
        filename: PatternLane.fromJson(j['filename'] as List<dynamic>),
        options:
            SchemeOptions.fromJson((j['options'] as Map).cast<String, dynamic>()),
      );

  final String id;
  String name;
  final List<PatternLane> folderLevels;
  final PatternLane filename;
  SchemeOptions options;

  StorageScheme clone() => StorageScheme(
        id: id,
        name: name,
        folderLevels: folderLevels.map((l) => l.clone()).toList(),
        filename: filename.clone(),
        options: options,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folders': folderLevels.map((l) => l.toJson()).toList(),
        'filename': filename.toJson(),
        'options': options.toJson(),
      };
}
