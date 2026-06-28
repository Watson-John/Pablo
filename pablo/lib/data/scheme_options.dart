// scheme_options.dart — the processing options of a [StorageScheme], split out
// of storage_scheme.dart to keep each file small.
//
// Most options only take effect once Pablo can actually write files (the
// ingest / reorganize pipeline, Phase B). They live in the model now so the
// builder UI and persistence are complete and forward-compatible; the engine
// (scheme_engine.dart) consumes the ones that affect path/name rendering today
// (date source, counter base, filename case, night-owl).

/// Which capture timestamp the folder/name date tokens resolve from.
enum DateSource { originalFirst, digitizedFirst, fileTimeOnly }

/// How the rendered filename is cased.
enum FilenameCase { asIs, upper, lower }

/// Disambiguation suffix appended when two files would collide.
class Suffix {
  const Suffix({
    this.alwaysApply = false,
    this.separator = '-',
    this.minDigits = 2,
    this.ignoreExtensionOnClash = true,
  });

  factory Suffix.fromJson(Map<String, dynamic> j) => Suffix(
        alwaysApply: j['always'] as bool? ?? false,
        separator: j['sep'] as String? ?? '-',
        minDigits: (j['digits'] as num?)?.toInt() ?? 2,
        ignoreExtensionOnClash: j['ignoreExt'] as bool? ?? true,
      );

  /// Apply the suffix even when there is no clash (e.g. `name-01`, `name-02`).
  final bool alwaysApply;
  final String separator;
  final int minDigits;

  /// When true, a clash is judged on the name root only, not the extension.
  final bool ignoreExtensionOnClash;

  Map<String, dynamic> toJson() => {
        'always': alwaysApply,
        'sep': separator,
        'digits': minDigits,
        'ignoreExt': ignoreExtensionOnClash,
      };
}

/// Keep a RAW file and its sidecar JPG together when filing.
class RawPairing {
  const RawPairing({
    this.enabled = false,
    this.rawExts = const {'.cr2', '.cr3', '.nef', '.arw', '.raf', '.orf', '.rw2', '.dng'},
    this.cookedExts = const {'.jpg', '.jpeg'},
  });

  factory RawPairing.fromJson(Map<String, dynamic> j) => RawPairing(
        enabled: j['on'] as bool? ?? false,
        rawExts: _strSet(j['raw']) ?? const {},
        cookedExts: _strSet(j['cooked']) ?? const {},
      );

  final bool enabled;
  final Set<String> rawExts;
  final Set<String> cookedExts;

  Map<String, dynamic> toJson() => {
        'on': enabled,
        'raw': rawExts.toList(),
        'cooked': cookedExts.toList(),
      };
}

/// Roll shots taken before [thresholdHour] back by [offsetHours] so a late
/// night event files under the day it started. Disabled when offset is 0.
class NightOwl {
  const NightOwl({this.thresholdHour = 0, this.offsetHours = 0});

  factory NightOwl.fromJson(Map<String, dynamic> j) => NightOwl(
        thresholdHour: (j['threshold'] as num?)?.toInt() ?? 0,
        offsetHours: (j['offset'] as num?)?.toInt() ?? 0,
      );

  final int thresholdHour;
  final int offsetHours;

  bool get enabled => offsetHours > 0;

  Map<String, dynamic> toJson() =>
      {'threshold': thresholdHour, 'offset': offsetHours};
}

class SchemeOptions {
  const SchemeOptions({
    this.fileTypes = const {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'},
    this.suffix = const Suffix(),
    this.rawPairing = const RawPairing(),
    this.smartCopy = true,
    this.dateSource = DateSource.originalFirst,
    this.filenameCase = FilenameCase.asIs,
    this.counterBase = 1,
    this.nightOwl = const NightOwl(),
    this.verifyAfterCopy = true,
    this.writeProtectAfterCopy = false,
    this.deleteAfterCopy = false,
    this.backupTargetPath,
  });

  factory SchemeOptions.fromJson(Map<String, dynamic> j) => SchemeOptions(
        fileTypes: _strSet(j['types']) ??
            const {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'},
        suffix: j['suffix'] == null
            ? const Suffix()
            : Suffix.fromJson((j['suffix'] as Map).cast<String, dynamic>()),
        rawPairing: j['raw'] == null
            ? const RawPairing()
            : RawPairing.fromJson((j['raw'] as Map).cast<String, dynamic>()),
        smartCopy: j['smartCopy'] as bool? ?? true,
        dateSource:
            DateSource.values.byName(j['dateSource'] as String? ?? 'originalFirst'),
        filenameCase:
            FilenameCase.values.byName(j['case'] as String? ?? 'asIs'),
        counterBase: (j['counterBase'] as num?)?.toInt() ?? 1,
        nightOwl: j['nightOwl'] == null
            ? const NightOwl()
            : NightOwl.fromJson((j['nightOwl'] as Map).cast<String, dynamic>()),
        verifyAfterCopy: j['verify'] as bool? ?? true,
        writeProtectAfterCopy: j['writeProtect'] as bool? ?? false,
        deleteAfterCopy: j['move'] as bool? ?? false,
        backupTargetPath: j['backup'] as String?,
      );

  /// Extensions the scheme processes (lower-case, with leading dot).
  final Set<String> fileTypes;
  final Suffix suffix;
  final RawPairing rawPairing;

  /// Skip a copy when the destination already holds the same bytes (Phase B).
  final bool smartCopy;
  final DateSource dateSource;
  final FilenameCase filenameCase;
  final int counterBase;
  final NightOwl nightOwl;
  final bool verifyAfterCopy;
  final bool writeProtectAfterCopy;

  /// Move instead of copy (i.e. delete the source after a verified copy).
  final bool deleteAfterCopy;
  final String? backupTargetPath;

  SchemeOptions copyWith({
    Set<String>? fileTypes,
    Suffix? suffix,
    RawPairing? rawPairing,
    bool? smartCopy,
    DateSource? dateSource,
    FilenameCase? filenameCase,
    int? counterBase,
    NightOwl? nightOwl,
    bool? verifyAfterCopy,
    bool? writeProtectAfterCopy,
    bool? deleteAfterCopy,
    String? backupTargetPath,
  }) =>
      SchemeOptions(
        fileTypes: fileTypes ?? this.fileTypes,
        suffix: suffix ?? this.suffix,
        rawPairing: rawPairing ?? this.rawPairing,
        smartCopy: smartCopy ?? this.smartCopy,
        dateSource: dateSource ?? this.dateSource,
        filenameCase: filenameCase ?? this.filenameCase,
        counterBase: counterBase ?? this.counterBase,
        nightOwl: nightOwl ?? this.nightOwl,
        verifyAfterCopy: verifyAfterCopy ?? this.verifyAfterCopy,
        writeProtectAfterCopy:
            writeProtectAfterCopy ?? this.writeProtectAfterCopy,
        deleteAfterCopy: deleteAfterCopy ?? this.deleteAfterCopy,
        backupTargetPath: backupTargetPath ?? this.backupTargetPath,
      );

  Map<String, dynamic> toJson() => {
        'types': fileTypes.toList(),
        'suffix': suffix.toJson(),
        'raw': rawPairing.toJson(),
        'smartCopy': smartCopy,
        'dateSource': dateSource.name,
        'case': filenameCase.name,
        'counterBase': counterBase,
        'nightOwl': nightOwl.toJson(),
        'verify': verifyAfterCopy,
        'writeProtect': writeProtectAfterCopy,
        'move': deleteAfterCopy,
        if (backupTargetPath != null) 'backup': backupTargetPath,
      };
}

Set<String>? _strSet(Object? v) =>
    v is List ? v.map((e) => e as String).toSet() : null;
