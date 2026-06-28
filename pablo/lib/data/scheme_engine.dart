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
    // A folder name is one path component, so cap+harden it here.
    final seg =
        hardenComponent(_capUtf8(renderLane(lane).trim(), kMaxComponentBytes));
    if (seg.isNotEmpty) folders.add(seg); // never create an empty folder level
  }

  var name = renderLane(scheme.filename).trim();
  if (name.isEmpty) name = _sanitize(meta.originalName);
  if (name.isEmpty) name = 'untitled';
  name = _applyCase(name, scheme.options.filenameCase);
  // Bound the filename to one path component, reserving room for the extension
  // (which must survive) but not the collision suffix — the planner re-fits with
  // the suffix in hand. A stem that hardens away (all dots) → 'untitled'.
  name = fitFilename(name, meta.ext);
  if (name.isEmpty) name = 'untitled';

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

// --- Path-component safety: length and cross-OS legality -------------------
//
// A single path component (one folder name, or `filename + ext`) has a hard
// length ceiling and a few names the OS rejects or silently rewrites. Without
// this, a very long originalName or typed event renders a path that
// FileOps.applyPlan simply can't create. The cap is per *component* — applied
// to a whole assembled segment/filename, never per token — and is enforced on
// every host so a library files identically wherever Pablo runs.

/// Hard per-path-component budget, in UTF-8 bytes. `NAME_MAX` is 255 bytes on
/// macOS APFS and Linux ext4/most filesystems; NTFS counts 255 UTF-16 units,
/// which 255 UTF-8 bytes can never exceed. Measured in bytes so a multibyte
/// name is bounded by what the filesystem actually stores, not its rune count.
const int kMaxComponentBytes = 255;

/// Windows reserved device names. Illegal as a path component (with or without
/// an extension, case-insensitively) — `CON`, `CON.jpg`, and `con.tar.gz` all
/// resolve to the console device. We neutralize them on every OS for parity.
const Set<String> _kReservedNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

final RegExp _kTrailingDotsSpaces = RegExp(r'[ .]+$');

/// UTF-8 byte length of a single Unicode code point.
int _utf8Len(int rune) => rune <= 0x7f
    ? 1
    : rune <= 0x7ff
        ? 2
        : rune <= 0xffff
            ? 3
            : 4;

/// Total UTF-8 byte length of [s].
int _utf8Bytes(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += _utf8Len(r);
  }
  return n;
}

/// Truncate [s] to at most [maxBytes] UTF-8 bytes, cutting only on a whole-rune
/// (code-point) boundary so a multibyte character is never split mid-sequence.
String _capUtf8(String s, int maxBytes) {
  if (maxBytes <= 0) return '';
  if (_utf8Bytes(s) <= maxBytes) return s; // common case: nothing to do
  final buf = StringBuffer();
  var used = 0;
  for (final rune in s.runes) {
    final n = _utf8Len(rune);
    if (used + n > maxBytes) break;
    buf.writeCharCode(rune);
    used += n;
  }
  return buf.toString();
}

/// Make [s] safe as a single path component on every desktop OS: drop trailing
/// dots and spaces (Windows strips them silently, so a rendered "name." would
/// not match the file actually created), and prefix a Windows reserved device
/// name with '_'. Returns '' for an empty or all-dots input (".", "..", "...")
/// so the caller can drop the folder level or fall back to a default name.
String hardenComponent(String s) {
  final trimmed = s.replaceAll(_kTrailingDotsSpaces, '');
  if (trimmed.isEmpty) return '';
  // Windows keys the reserved check on the name up to the first dot.
  final stem = trimmed.split('.').first.toLowerCase();
  return _kReservedNames.contains(stem) ? '_$trimmed' : trimmed;
}

/// Fit `stem + suffix + ext` into [kMaxComponentBytes] by trimming only the
/// [stem]: the collision [suffix] disambiguates and the [ext] must be kept, so
/// neither is sacrificed. The stem is byte-capped (rune-safe) then hardened.
/// The engine calls this with no suffix; the planner passes its collision
/// suffix so a name that is already at budget still fits once numbered.
String fitFilename(String stem, String ext, {String suffix = ''}) {
  final budget = kMaxComponentBytes - _utf8Bytes(ext) - _utf8Bytes(suffix);
  return '${hardenComponent(_capUtf8(stem, budget))}$suffix';
}
