// scheme_engine.dart — the pure renderer: (scheme, photo metadata, counter,
// run prompts) -> a concrete relative folder path + filename. No I/O, so it is
// fully unit-testable.
//
// This stage produces the deterministic name a photo *wants*. Steps that need a
// real filesystem — collision suffixes, RAW+JPEG pairing, smart-copy skipping —
// are applied later by the ingest/reorganize pipeline (Phase B), not here.

import 'scheme_options.dart';
import 'storage_scheme.dart';

const List<String> _kMonthAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// The metadata the engine needs about one photo. Built from EXIF + the file
/// itself by the caller (see `photoMetaForPath` in the preview layer); kept
/// dependency-free here so the engine has no `dart:io` coupling.
class PhotoMeta {
  const PhotoMeta({
    required this.fileMtime,
    required this.originalName,
    required this.ext,
    this.captureDate,
    this.make,
    this.model,
    this.owner,
    this.uniqueId,
    this.parentDirs = const [],
  });

  /// Always present (filesystem modified time).
  final DateTime fileMtime;

  /// EXIF capture date when the file carries one.
  final DateTime? captureDate;

  /// File name without its extension.
  final String originalName;

  /// Extension including the dot, lower-case (e.g. `.jpg`).
  final String ext;

  final String? make;
  final String? model;
  final String? owner;
  final String? uniqueId;

  /// Containing directories, immediate parent first then upward.
  final List<String> parentDirs;
}

/// Mutable running counter. [next] starts at the scheme's counter base and is
/// advanced once per photo that actually uses a counter token.
class CounterState {
  CounterState(this.next);
  int next;
}

/// Values typed by the user at run time for prompt tokens (event/label).
class RunPrompts {
  const RunPrompts(this.values);
  factory RunPrompts.event(String value) => RunPrompts({_kEventKey: value});

  final Map<String, String> values;
  String get event => values[_kEventKey] ?? '';
}

const String _kEventKey = 'event';

class SchemeResult {
  const SchemeResult({
    required this.folderSegments,
    required this.filename,
    required this.ext,
  });

  /// Folder levels, top-down. Empty levels are already dropped.
  final List<String> folderSegments;
  final String filename;
  final String ext;

  /// Folder segments joined with '/', then `filename` + `ext`.
  String get relativePath =>
      [...folderSegments, '$filename$ext'].join('/');
}

/// Render [scheme] for one photo. [counter] is advanced in place; pass the same
/// instance across a batch so the running number carries over.
SchemeResult renderScheme(
  StorageScheme scheme,
  PhotoMeta meta,
  CounterState counter, [
  RunPrompts prompts = const RunPrompts({}),
]) {
  final date = _resolveDate(scheme.options, meta);
  // One counter value per photo, shared by every counter token in the scheme;
  // advanced once, and only if a counter token was actually used.
  final counterValue = counter.next;
  var usedCounter = false;

  String expand(Segment seg) {
    if (seg is LiteralSegment) return _sanitize(seg.text);
    final tok = seg as TokenSegment;
    if (tok.type == TokenType.counter) usedCounter = true;
    return _token(tok, date, meta, prompts, counterValue);
  }

  String renderLane(PatternLane lane) => lane.segments.map(expand).join();

  final folders = <String>[];
  for (final lane in scheme.folderLevels) {
    final seg = renderLane(lane).trim();
    if (seg.isNotEmpty) folders.add(seg); // never create an empty folder level
  }

  var name = renderLane(scheme.filename).trim();
  if (name.isEmpty) name = _sanitize(meta.originalName);
  if (name.isEmpty) name = 'untitled';
  name = _applyCase(name, scheme.options.filenameCase);

  if (usedCounter) counter.next++;

  return SchemeResult(folderSegments: folders, filename: name, ext: meta.ext);
}

DateTime _resolveDate(SchemeOptions o, PhotoMeta m) {
  DateTime base;
  switch (o.dateSource) {
    case DateSource.fileTimeOnly:
      base = m.fileMtime;
    case DateSource.originalFirst:
    case DateSource.digitizedFirst:
      // Pablo's EXIF reader exposes a single capture date today; the original
      // vs digitized ordering is honored once both are parsed.
      base = m.captureDate ?? m.fileMtime;
  }
  final owl = o.nightOwl;
  if (owl.enabled && base.hour < owl.thresholdHour) {
    base = base.subtract(Duration(hours: owl.offsetHours));
  }
  return base;
}

String _token(
  TokenSegment t,
  DateTime d,
  PhotoMeta m,
  RunPrompts p,
  int counterValue,
) {
  switch (t.type) {
    case TokenType.year4:
      return _pad(d.year, 4);
    case TokenType.year2:
      return _pad(d.year % 100, 2);
    case TokenType.quarter:
      return '${((d.month - 1) ~/ 3) + 1}';
    case TokenType.month:
      return _pad(d.month, 2);
    case TokenType.monthAbbr:
      return _kMonthAbbr[d.month];
    case TokenType.day:
      return _pad(d.day, 2);
    case TokenType.hour:
      return _pad(d.hour, 2);
    case TokenType.minute:
      return _pad(d.minute, 2);
    case TokenType.second:
      return _pad(d.second, 2);
    case TokenType.make:
      return _word(m.make);
    case TokenType.model:
      return _word(m.model);
    case TokenType.owner:
      return _word(m.owner);
    case TokenType.uniqueId:
      return _word(m.uniqueId);
    case TokenType.originalName:
      return _sanitize(m.originalName);
    case TokenType.parentFolder:
      return _word(m.parentDirs.isNotEmpty ? m.parentDirs.first : null);
    case TokenType.counter:
      return _pad(counterValue, t.pad ?? 1);
    case TokenType.prompt:
      return _sanitize(p.event);
  }
}

String _pad(int v, int width) => v.toString().padLeft(width, '0');

/// Camera/word fields (make/model/owner/id/parent): unavailable → empty; any
/// run of non-alphanumeric characters → a single `_` (so "EOS 10D" → "EOS_10D",
/// matching DIM), trimmed of leading/trailing underscores.
String _word(String? v) {
  if (v == null) return '';
  final s = v.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return s.replaceAll(RegExp(r'^_+|_+$'), '');
}

/// Strip characters illegal in a path component; literals/prompts keep spaces
/// and dashes. A user-typed "/" can't smuggle in an extra folder level.
String _sanitize(String v) =>
    v.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();

String _applyCase(String s, FilenameCase c) {
  switch (c) {
    case FilenameCase.asIs:
      return s;
    case FilenameCase.upper:
      return s.toUpperCase();
    case FilenameCase.lower:
      return s.toLowerCase();
  }
}
