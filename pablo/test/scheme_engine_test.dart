// Golden tests for the storage-scheme renderer: each preset maps a fixed photo
// to an exact relative path, plus the tricky bits — counter sharing/advance,
// night-owl rollback, date-source selection, word sanitization, empty-level
// dropping, filename casing, and JSON round-trip.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/data/scheme_options.dart';
import 'package:pablo/data/storage_scheme.dart';
import 'package:pablo/features/organize/scheme_presets.dart';

// Sentinel so callers can pass `capture: null` to mean "no EXIF date" while the
// default (omitted) still supplies the fixed capture date below.
const Object _unset = Object();

PhotoMeta _meta({
  Object? capture = _unset,
  DateTime? mtime,
  String name = 'IMG_1234',
  String ext = '.jpg',
  String? make = 'Canon',
  String? model = 'EOS 10D',
  List<String> parents = const ['Vacation', 'Trips'],
}) =>
    PhotoMeta(
      fileMtime: mtime ?? DateTime(2020, 1, 2, 9, 0, 0),
      captureDate: identical(capture, _unset)
          ? DateTime(2024, 3, 15, 14, 30, 5)
          : capture as DateTime?,
      originalName: name,
      ext: ext,
      make: make,
      model: model,
      parentDirs: parents,
    );

CounterState _counter([int base = 1]) => CounterState(base);

void main() {
  group('presets render to exact paths', () {
    final m = _meta();

    test('By Year / Month / Day', () {
      final r = renderScheme(byYearMonthDay(), m, _counter());
      expect(r.relativePath, '2024/03/15/IMG_1234.jpg');
    });

    test('By Year / Month', () {
      final r = renderScheme(byYearMonth(), m, _counter());
      expect(r.relativePath, '2024/03/IMG_1234.jpg');
    });

    test('Flat (YYYY-MM-DD) — no folders, dated+numbered name', () {
      final r = renderScheme(flatDate(), m, _counter());
      expect(r.folderSegments, isEmpty);
      expect(r.relativePath, '2024-03-15-001.jpg');
    });

    test('By Camera then Date — model space becomes underscore', () {
      final r = renderScheme(byCameraThenDate(), m, _counter());
      expect(r.relativePath, 'Canon/EOS_10D/2024/2024-03-15-001.jpg');
    });

    test('By Event then Date — typed event keeps its spaces', () {
      final r = renderScheme(
        byEventThenDate(),
        m,
        _counter(),
        RunPrompts.event('Birthday Party'),
      );
      expect(r.relativePath, 'Birthday Party/2024/2024-03-15-001.jpg');
    });
  });

  group('counter', () {
    test('advances once per photo and carries across a batch', () {
      final c = _counter();
      expect(renderScheme(flatDate(), _meta(), c).filename, '2024-03-15-001');
      expect(renderScheme(flatDate(), _meta(), c).filename, '2024-03-15-002');
      expect(renderScheme(flatDate(), _meta(), c).filename, '2024-03-15-003');
    });

    test('respects the base and does not advance for counterless schemes', () {
      final c = _counter(7);
      renderScheme(byYearMonthDay(), _meta(), c); // no counter token
      expect(c.next, 7);
      expect(renderScheme(flatDate(), _meta(), c).filename, '2024-03-15-007');
      expect(c.next, 8);
    });
  });

  group('date resolution', () {
    test('falls back to file mtime when there is no capture date', () {
      final r = renderScheme(
        byYearMonth(),
        _meta(capture: null, mtime: DateTime(2019, 11, 4)),
        _counter(),
      );
      expect(r.folderSegments, ['2019', '11']);
    });

    test('fileTimeOnly ignores the capture date', () {
      final s = StorageScheme(
        id: 't',
        name: 't',
        folderLevels: [PatternLane([const TokenSegment(TokenType.year4)])],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
        options: const SchemeOptions(dateSource: DateSource.fileTimeOnly),
      );
      final r = renderScheme(
        s,
        _meta(capture: DateTime(2024), mtime: DateTime(2018, 6, 1)),
        _counter(),
      );
      expect(r.folderSegments, ['2018']);
    });

    test('night-owl rolls an early shot back to the previous day', () {
      final s = StorageScheme(
        id: 't',
        name: 't',
        folderLevels: [PatternLane([const TokenSegment(TokenType.day)])],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
        options: const SchemeOptions(
          nightOwl: NightOwl(thresholdHour: 4, offsetHours: 5),
        ),
      );
      // 01:30 on the 15th, rolled back 5h -> 20:30 on the 14th.
      final r = renderScheme(
        s,
        _meta(capture: DateTime(2024, 3, 15, 1, 30)),
        _counter(),
      );
      expect(r.folderSegments, ['14']);
    });
  });

  group('edge cases', () {
    test('an empty folder level is dropped (missing make)', () {
      final s = StorageScheme(
        id: 't',
        name: 't',
        folderLevels: [
          PatternLane([const TokenSegment(TokenType.make)]),
          PatternLane([const TokenSegment(TokenType.year4)]),
        ],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
      );
      final r = renderScheme(s, _meta(make: null), _counter());
      expect(r.folderSegments, ['2024']); // empty make level dropped
    });

    test('empty file name falls back to "untitled"', () {
      final r = renderScheme(byYearMonthDay(), _meta(name: ''), _counter());
      expect(r.filename, 'untitled');
    });

    test('a literal "/" cannot smuggle in an extra folder level', () {
      final s = StorageScheme(
        id: 't',
        name: 't',
        folderLevels: [PatternLane([const LiteralSegment('a/b')])],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
      );
      final r = renderScheme(s, _meta(), _counter());
      expect(r.folderSegments, ['a_b']);
    });

    test('filename case option', () {
      final upper = byYearMonthDay()
        ..options = const SchemeOptions(filenameCase: FilenameCase.upper);
      expect(renderScheme(upper, _meta(), _counter()).filename, 'IMG_1234');
      final lower = byYearMonthDay()
        ..options = const SchemeOptions(filenameCase: FilenameCase.lower);
      expect(renderScheme(lower, _meta(), _counter()).filename, 'img_1234');
    });
  });

  group('serialization', () {
    test('every preset round-trips through JSON', () {
      for (final preset in buildPresetSchemes()) {
        final back = StorageScheme.fromJson(preset.toJson());
        final m = _meta();
        expect(
          renderScheme(back, m, _counter(), RunPrompts.event('Trip')).relativePath,
          renderScheme(preset, m, _counter(), RunPrompts.event('Trip'))
              .relativePath,
          reason: preset.name,
        );
      }
    });
  });
}
