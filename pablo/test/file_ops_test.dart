// Integration test for the Phase B file seam against a real temp filesystem:
// plan a batch (with a name collision) and apply it by copy and by move.

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
}
