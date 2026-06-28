// Integration test for the Phase B file seam against a real temp filesystem:
// plan a batch (with a name collision) and apply it by copy and by move, plus
// over-long names that must be truncated to a path the OS can actually create.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/file_ops.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/data/scheme_planner.dart';
import 'package:pablo/features/organize/scheme_presets.dart';

PhotoMeta _meta({String name = 'IMG', DateTime? date}) => PhotoMeta(
      fileMtime: date ?? DateTime(2024, 3, 15),
      captureDate: date ?? DateTime(2024, 3, 15),
      originalName: name,
      ext: '.jpg',
    );

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_fileops_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('copy files into the scheme layout, resolving a name collision', () {
    final a = File('${tmp.path}/src/a.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3, 4]);
    final b = File('${tmp.path}/src/b.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9, 9]);
    final dest = '${tmp.path}/dest';

    final plan = planFiling(byYearMonthDay(), [
      SourcePhoto(a.path, _meta()),
      SourcePhoto(b.path, _meta()), // same render -> collision
    ]);
    final results = FileOps.applyPlan(plan, dest);

    expect(results.every((r) => r.ok), isTrue);
    expect(File('$dest/2024/03/15/IMG.jpg').existsSync(), isTrue);
    expect(File('$dest/2024/03/15/IMG-01.jpg').existsSync(), isTrue);
    // bytes preserved, sources untouched (copy)
    expect(File('$dest/2024/03/15/IMG.jpg').readAsBytesSync(), [1, 2, 3, 4]);
    expect(a.existsSync(), isTrue);
  });

  test('move relocates the file and removes the source', () {
    final src = File('${tmp.path}/x.jpg')..writeAsBytesSync([5, 5, 5]);
    final dest = '${tmp.path}/dest';

    final plan = planFiling(
      byYearMonth(),
      [SourcePhoto(src.path, _meta(name: 'X', date: DateTime(2024, 1, 2)))],
    );
    final results = FileOps.applyPlan(plan, dest, move: true);

    expect(results.single.ok, isTrue);
    expect(File('$dest/2024/01/X.jpg').existsSync(), isTrue);
    expect(src.existsSync(), isFalse);
  });

  // Every path component must be ≤255 UTF-8 bytes (NAME_MAX on APFS/ext4),
  // otherwise applyPlan throws a FileSystemException and reports a failure.
  void expectComponentsWithinBudget(String relPath) {
    for (final part in relPath.split('/')) {
      expect(utf8.encode(part).length, lessThanOrEqualTo(255),
          reason: 'component too long: $part');
    }
  }

  test('a >255-byte original name files into a path that actually creates', () {
    final src = File('${tmp.path}/long.jpg')..writeAsBytesSync([1, 2, 3]);
    final dest = '${tmp.path}/dest';

    final plan = planFiling(
      byYearMonthDay(),
      [SourcePhoto(src.path, _meta(name: 'x' * 400))],
    );
    final result = FileOps.applyPlan(plan, dest).single;

    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(File(result.destPath).existsSync(), isTrue);
    expect(result.destPath.endsWith('.jpg'), isTrue); // extension preserved
    expectComponentsWithinBudget(result.entry.relPath);
  });

  test('a long typed event renders a folder that actually creates', () {
    final src = File('${tmp.path}/evt.jpg')..writeAsBytesSync([7, 7]);
    final dest = '${tmp.path}/dest';

    final plan = planFiling(
      byEventThenDate(),
      [SourcePhoto(src.path, _meta())],
      prompts: RunPrompts.event('E' * 400),
    );
    final result = FileOps.applyPlan(plan, dest).single;

    expect(result.ok, isTrue, reason: result.error?.toString());
    expect(File(result.destPath).existsSync(), isTrue);
    expectComponentsWithinBudget(result.entry.relPath);
  });

  test('two max-length names collide but the suffix still fits and creates', () {
    final a = File('${tmp.path}/a.jpg')..writeAsBytesSync([1]);
    final b = File('${tmp.path}/b.jpg')..writeAsBytesSync([2, 2]);
    final dest = '${tmp.path}/dest';

    final plan = planFiling(byYearMonthDay(), [
      SourcePhoto(a.path, _meta(name: 'y' * 400)),
      SourcePhoto(b.path, _meta(name: 'y' * 400)), // same render -> collision
    ]);
    final results = FileOps.applyPlan(plan, dest);

    expect(results.every((r) => r.ok), isTrue,
        reason: results.map((r) => r.error).toString());
    expect(results[0].destPath, isNot(results[1].destPath));
    for (final r in results) {
      expect(File(r.destPath).existsSync(), isTrue);
      expectComponentsWithinBudget(r.entry.relPath);
    }
  });
}
