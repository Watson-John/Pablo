// scheme_presets.dart — built-in starting templates, the DIM "recipes" minus
// location (which needs a reverse-geocoder Pablo doesn't have yet). The
// drag-and-drop builder seeds from one of these and the user customizes;
// scheme_store installs them on first run.

import '../../data/storage_scheme.dart';

/// All presets, in the order shown in the preset gallery.
List<StorageScheme> buildPresetSchemes() => [
      byYearMonthDay(),
      byYearMonth(),
      flatDate(),
      byCameraThenDate(),
      byEventThenDate(),
    ];

PatternLane _level(List<Segment> segs) => PatternLane(segs);
TokenSegment _t(TokenType type, {int? pad}) => TokenSegment(type, pad: pad);
LiteralSegment _dash() => const LiteralSegment('-');

/// `2024 / 03 / 15` then the original file name.
StorageScheme byYearMonthDay() => StorageScheme(
      id: 'preset.ymd',
      name: 'By Year / Month / Day',
      folderLevels: [
        _level([_t(TokenType.year4)]),
        _level([_t(TokenType.month)]),
        _level([_t(TokenType.day)]),
      ],
      filename: _level([_t(TokenType.originalName)]),
    );

/// `2024 / 03` then the original file name.
StorageScheme byYearMonth() => StorageScheme(
      id: 'preset.ym',
      name: 'By Year / Month',
      folderLevels: [
        _level([_t(TokenType.year4)]),
        _level([_t(TokenType.month)]),
      ],
      filename: _level([_t(TokenType.originalName)]),
    );

/// No folders; files named `2024-03-15-001`.
StorageScheme flatDate() => StorageScheme(
      id: 'preset.flat',
      name: 'Flat (YYYY-MM-DD)',
      folderLevels: const [],
      filename: _level([
        _t(TokenType.year4),
        _dash(),
        _t(TokenType.month),
        _dash(),
        _t(TokenType.day),
        _dash(),
        _t(TokenType.counter, pad: 3),
      ]),
    );

/// `Canon / EOS_R5 / 2024` then a dated, numbered name.
StorageScheme byCameraThenDate() => StorageScheme(
      id: 'preset.camera',
      name: 'By Camera then Date',
      folderLevels: [
        _level([_t(TokenType.make)]),
        _level([_t(TokenType.model)]),
        _level([_t(TokenType.year4)]),
      ],
      filename: _level([
        _t(TokenType.year4),
        _dash(),
        _t(TokenType.month),
        _dash(),
        _t(TokenType.day),
        _dash(),
        _t(TokenType.counter, pad: 3),
      ]),
    );

/// `<event you type> / 2024` then a dated, numbered name.
StorageScheme byEventThenDate() => StorageScheme(
      id: 'preset.event',
      name: 'By Event then Date',
      folderLevels: [
        _level([_t(TokenType.prompt)]),
        _level([_t(TokenType.year4)]),
      ],
      filename: _level([
        _t(TokenType.year4),
        _dash(),
        _t(TokenType.month),
        _dash(),
        _t(TokenType.day),
        _dash(),
        _t(TokenType.counter, pad: 3),
      ]),
    );
