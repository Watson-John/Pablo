// Property + cross-OS integration tests for the file reorganizer.
//
// Two seeded-random arms (reproducible — every failure prints its seed) plus
// targeted deterministic cases the loops can't express:
//   • pure arm (200 seeds): renderScheme -> planFiling invariants (legal, unique,
//     well-formed, counter shared/monotonic) — OS-independent string facts.
//   • filesystem arm (40 seeds): plan -> FileOps.applyPlan copy & move against a
//     real temp dir — bytes round-trip, sources retained/removed, paths joined
//     with the platform separator.
//
// Cross-OS: generators strip trailing '.'/' ' (Windows strips those), the FS arm
// lowercases free text + appends a counter so no case-insensitive-FS collisions
// occur, and rare Windows-reserved-name renders are skipped on Windows only.
// This file runs under `flutter test` in the existing CI matrix
// (ubuntu/windows/macos), so these invariants are checked on every OS.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/file_ops.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/data/scheme_options.dart';
import 'package:pablo/data/scheme_planner.dart';
import 'package:pablo/data/storage_scheme.dart';
import 'package:pablo/features/organize/scheme_presets.dart';

final _illegal = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
const _winReserved = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};
final String _sep = Platform.pathSeparator;

// DateTime has no const constructor, so this is a top-level final (not const).
final DateTime _fixed = DateTime(2024, 3, 15);

bool _winHostile(String s) =>
    _winReserved.contains(s.toLowerCase()) || s.endsWith('.') || s.endsWith(' ');

// A pool mixing legal chars, spaces/dots, and the illegal set so sanitization is
// exercised. Trailing '.'/' ' are stripped (Windows would otherwise drop them).
String _randText(Random r, {int maxLen = 8, bool lower = false}) {
  const pool = 'abcAB12 .-_()/:*?"<>|';
  final n = r.nextInt(maxLen + 1);
  var s = '';
  for (var i = 0; i < n; i++) {
    s += pool[r.nextInt(pool.length)];
  }
  if (lower) s = s.toLowerCase();
  return s.replaceAll(RegExp(r'[ .]+$'), '');
}

PhotoMeta _randMeta(Random r, {bool lower = false}) {
  String? maybe() => r.nextBool() ? _randText(r, lower: lower) : null;
  DateTime d() => DateTime(1990 + r.nextInt(50), 1 + r.nextInt(12),
      1 + r.nextInt(28), r.nextInt(24), r.nextInt(60), r.nextInt(60));
  return PhotoMeta(
    fileMtime: d(),
    captureDate: r.nextBool() ? d() : null,
    originalName: _randText(r, maxLen: 12, lower: lower),
    ext: const ['.jpg', '.png', '.jpeg'][r.nextInt(3)],
    make: maybe(),
    model: maybe(),
    owner: maybe(),
    uniqueId: maybe(),
    parentDirs: r.nextBool() ? [_randText(r, lower: lower)] : const [],
  );
}

PatternLane _randLane(Random r, {bool lower = false}) {
  final segs = <Segment>[];
  final n = 1 + r.nextInt(4);
  for (var i = 0; i < n; i++) {
    if (r.nextBool()) {
      segs.add(LiteralSegment(_randText(r, lower: lower)));
    } else {
      final t = TokenType.values[r.nextInt(TokenType.values.length)];
      segs.add(TokenSegment(t,
          pad: t == TokenType.counter ? 1 + r.nextInt(4) : null));
    }
  }
  return PatternLane(segs);
}

StorageScheme _randScheme(Random r, {bool lower = false, bool forceCounter = false}) {
  final folders = [for (var i = 0; i < r.nextInt(4); i++) _randLane(r, lower: lower)];
  var filename = _randLane(r, lower: lower);
  if (forceCounter) {
    filename = PatternLane(
        [...filename.segments, const TokenSegment(TokenType.counter, pad: 3)]);
  }
  return StorageScheme(
    id: 'rand',
    name: 'rand',
    folderLevels: folders,
    filename: filename,
    options: SchemeOptions(
      suffix: Suffix(
        alwaysApply: r.nextBool(),
        separator: const ['-', '_', '.'][r.nextInt(3)],
        minDigits: 1 + r.nextInt(4),
        ignoreExtensionOnClash: r.nextBool(),
      ),
      counterBase: r.nextInt(10),
    ),
  );
}

void main() {
  group('property (pure render + plan)', () {
    test('plans are legal, unique, and well-formed across 200 seeds', () {
      for (var seed = 0; seed < 200; seed++) {
        final ctx = 'seed=$seed';
        final r = Random(seed);
        final scheme = _randScheme(r);
        final n = 1 + r.nextInt(29);
        final sources = [
          for (var i = 0; i < n; i++) SourcePhoto('src_$i', _randMeta(r))
        ];
        final plan = planFiling(scheme, sources);

        expect(plan.entries.length, n, reason: ctx);
        final rels = plan.entries.map((e) => e.relPath).toList();
        expect(rels.toSet().length, rels.length, reason: '$ctx not unique: $rels');

        for (final e in plan.entries) {
          expect(e.filename, isNotEmpty, reason: '$ctx empty filename');
          expect(_illegal.hasMatch(e.filename), isFalse,
              reason: '$ctx illegal in "${e.filename}"');
          expect(e.folderSegments.length <= scheme.folderLevels.length, isTrue,
              reason: '$ctx phantom folder level');
          for (final f in e.folderSegments) {
            expect(f, isNotEmpty, reason: '$ctx empty folder segment');
            expect(_illegal.hasMatch(f), isFalse,
                reason: '$ctx illegal in folder "$f"');
          }
        }
      }
    });

    test('counter is shared within a photo and +1 across the batch', () {
      for (var seed = 0; seed < 50; seed++) {
        final ctx = 'seed=$seed';
        final r = Random(seed);
        final base = r.nextInt(100);
        final scheme = StorageScheme(
          id: 'c',
          name: 'c',
          folderLevels: [PatternLane([const TokenSegment(TokenType.counter, pad: 4)])],
          filename: PatternLane([const TokenSegment(TokenType.counter, pad: 2)]),
          options: SchemeOptions(counterBase: base),
        );
        final n = 1 + r.nextInt(10);
        final plan = planFiling(scheme,
            [for (var i = 0; i < n; i++) SourcePhoto('s$i', _randMeta(r))]);
        for (var i = 0; i < n; i++) {
          final e = plan.entries[i];
          expect(int.parse(e.folderSegments.single), int.parse(e.filename),
              reason: '$ctx counter not shared');
          expect(int.parse(e.filename), base + i, reason: '$ctx not monotonic');
        }
      }
    });
  });

  group('property (real filesystem round-trip)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_prop_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('copy then move round-trips bytes across 40 seeds', () {
      for (var seed = 0; seed < 40; seed++) {
        final ctx = 'seed=$seed';
        final r = Random(seed);
        final scheme = _randScheme(r, lower: true, forceCounter: true);
        final n = 1 + r.nextInt(8);
        final seedDir = '${tmp.path}${_sep}s$seed';
        final srcDir = '$seedDir${_sep}src';
        Directory(srcDir).createSync(recursive: true);

        final sources = <SourcePhoto>[];
        final bytes = <String, List<int>>{};
        for (var i = 0; i < n; i++) {
          final p = '$srcDir${_sep}f$i.bin';
          final b = [for (var k = 0; k < 1 + r.nextInt(16); k++) r.nextInt(256)];
          File(p).writeAsBytesSync(b);
          bytes[p] = b;
          sources.add(SourcePhoto(p, _randMeta(r, lower: true)));
        }
        final plan = planFiling(scheme, sources);

        // Skip the rare Windows-reserved-name render on Windows only.
        if (Platform.isWindows &&
            plan.entries.any((e) =>
                e.folderSegments.any(_winHostile) || _winHostile(e.filename))) {
          continue;
        }

        final destCopy = '$seedDir${_sep}copy';
        final copyRes = FileOps.applyPlan(plan, destCopy);
        expect(copyRes.length, n, reason: '$ctx applyPlan totality');
        expect(copyRes.every((x) => x.ok), isTrue, reason: '$ctx copy failed');
        for (final res in copyRes) {
          expect(res.destPath,
              '$destCopy$_sep${res.entry.relPath.replaceAll('/', _sep)}',
              reason: '$ctx path join');
          expect(File(res.destPath).readAsBytesSync(),
              bytes[res.entry.sourcePath],
              reason: '$ctx bytes changed');
          expect(File(res.entry.sourcePath).existsSync(), isTrue,
              reason: '$ctx source removed by copy');
        }

        final destMove = '$seedDir${_sep}move';
        final moveRes = FileOps.applyPlan(plan, destMove, move: true);
        expect(moveRes.every((x) => x.ok), isTrue, reason: '$ctx move failed');
        for (final res in moveRes) {
          expect(File(res.destPath).readAsBytesSync(),
              bytes[res.entry.sourcePath],
              reason: '$ctx move bytes changed');
          expect(File(res.entry.sourcePath).existsSync(), isFalse,
              reason: '$ctx source kept after move');
        }
      }
    });
  });

  group('targeted edge cases', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_edge_'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('collision group past 99 stays unique with growing width', () {
      final meta = PhotoMeta(
          fileMtime: _fixed, captureDate: _fixed, originalName: 'IMG', ext: '.jpg');
      final plan = planFiling(
          byYearMonthDay(), [for (var i = 0; i < 150; i++) SourcePhoto('s$i', meta)]);
      final rels = plan.entries.map((e) => e.relPath).toList();
      expect(rels.toSet().length, 150);
      expect(rels[0], '2024/03/15/IMG.jpg');
      expect(rels[1], '2024/03/15/IMG-01.jpg');
      expect(rels[100], '2024/03/15/IMG-100.jpg');
    });

    test('alwaysApply suffixes every file (none bare)', () {
      final scheme = byYearMonthDay()
        ..options = const SchemeOptions(suffix: Suffix(alwaysApply: true));
      final meta = PhotoMeta(
          fileMtime: _fixed, captureDate: _fixed, originalName: 'P', ext: '.jpg');
      final plan =
          planFiling(scheme, [for (var i = 0; i < 5; i++) SourcePhoto('s$i', meta)]);
      for (final e in plan.entries) {
        expect(e.filename, matches(RegExp(r'^P-\d{2,}$')), reason: e.filename);
      }
    });

    test('filename fallback vs sanitization of the original name', () {
      final scheme = StorageScheme(
        id: 'n',
        name: 'n',
        folderLevels: const [],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
      );
      String nameFor(String orig) => planFiling(scheme, [
            SourcePhoto('s',
                PhotoMeta(fileMtime: _fixed, originalName: orig, ext: '.jpg'))
          ]).entries.single.filename;

      expect(nameFor(''), 'untitled');
      expect(nameFor('   '), 'untitled'); // trims to empty -> fallback
      expect(nameFor('<<>>'), '____'); // per-char sanitize, non-empty
      expect(nameFor('a:b'), 'a_b');
    });

    test('all-punctuation word token drops its folder level', () {
      final scheme = StorageScheme(
        id: 'w',
        name: 'w',
        folderLevels: [
          PatternLane([const TokenSegment(TokenType.make)]),
          PatternLane([const TokenSegment(TokenType.year4)]),
        ],
        filename: PatternLane([const TokenSegment(TokenType.originalName)]),
      );
      final plan = planFiling(scheme, [
        SourcePhoto(
            's',
            PhotoMeta(
                fileMtime: _fixed,
                captureDate: _fixed,
                make: '!!!',
                originalName: 'x',
                ext: '.jpg'))
      ]);
      expect(plan.entries.single.folderSegments, ['2024']);
    });

    test('overlong component is truncated to a creatable path (no throw, ok)',
        () {
      final scheme = StorageScheme(
        id: 'l',
        name: 'l',
        folderLevels: const [],
        filename: PatternLane([LiteralSegment('x' * 300)]),
      );
      final src = File('${tmp.path}${_sep}long.bin')..writeAsBytesSync([1]);
      final plan = planFiling(scheme, [
        SourcePhoto(src.path,
            PhotoMeta(fileMtime: _fixed, originalName: 'i', ext: '.jpg'))
      ]);
      final res = FileOps.applyPlan(plan, '${tmp.path}${_sep}ld').single;
      // The engine caps each component to NAME_MAX, so an over-long name now
      // files instead of erroring: it is trimmed (extension preserved) to a path
      // every OS can create, rather than failing the entry.
      expect(res.ok, isTrue, reason: res.error?.toString());
      expect(File(res.destPath).existsSync(), isTrue);
      expect(res.destPath.endsWith('.jpg'), isTrue); // extension survives
      for (final part in res.entry.relPath.split('/')) {
        expect(utf8.encode(part).length, lessThanOrEqualTo(255),
            reason: 'component over budget: $part');
      }
    });

    test('missing source -> per-entry failure, no throw', () {
      final plan = planFiling(byYearMonth(), [
        SourcePhoto('${tmp.path}${_sep}nope.jpg',
            PhotoMeta(fileMtime: _fixed, captureDate: _fixed, originalName: 'g', ext: '.jpg'))
      ]);
      expect(FileOps.applyPlan(plan, '${tmp.path}${_sep}md').single.ok, isFalse);
    });

    test('partial batch: present succeeds, missing fails', () {
      final ok = File('${tmp.path}${_sep}ok.jpg')..writeAsBytesSync([1, 2]);
      final plan = planFiling(flatDate(), [
        SourcePhoto(ok.path,
            PhotoMeta(fileMtime: _fixed, captureDate: _fixed, originalName: 'a', ext: '.jpg')),
        SourcePhoto('${tmp.path}${_sep}missing.jpg',
            PhotoMeta(fileMtime: _fixed, captureDate: _fixed, originalName: 'b', ext: '.jpg')),
      ]);
      final res = FileOps.applyPlan(plan, '${tmp.path}${_sep}pd');
      expect(res.where((x) => x.ok).length, 1);
      expect(res.where((x) => !x.ok).length, 1);
    });

    test('pre-occupied destination: copy fails, original untouched', () {
      final meta = PhotoMeta(
          fileMtime: _fixed, captureDate: _fixed, originalName: 'z', ext: '.jpg');
      final src = File('${tmp.path}${_sep}z.jpg')..writeAsBytesSync([5]);
      final dest = '${tmp.path}${_sep}occ';
      final rel =
          planFiling(byYearMonth(), [SourcePhoto(src.path, meta)]).entries.single.relPath;
      final occupied = File('$dest$_sep${rel.replaceAll('/', _sep)}')
        ..createSync(recursive: true)
        ..writeAsBytesSync([9]);
      final res = FileOps.applyPlan(
          planFiling(byYearMonth(), [SourcePhoto(src.path, meta)]), dest);
      expect(res.single.ok, isFalse);
      expect(occupied.readAsBytesSync(), [9]); // sentinel untouched
    });
  });
}
