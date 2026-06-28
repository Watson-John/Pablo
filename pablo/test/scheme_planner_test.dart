// Tests for the filing planner: within-batch collision resolution, always-apply
// suffix, ignore-extension-on-clash, destination-exists checks, counter schemes,
// and custom separator/min-digits.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/data/scheme_options.dart';
import 'package:pablo/data/scheme_planner.dart';
import 'package:pablo/features/organize/scheme_presets.dart';

SourcePhoto _src(String path,
        {String name = 'IMG', String ext = '.jpg', DateTime? date}) =>
    SourcePhoto(
      path,
      PhotoMeta(
        fileMtime: date ?? DateTime(2024, 3, 15),
        captureDate: date ?? DateTime(2024, 3, 15),
        originalName: name,
        ext: ext,
      ),
    );

List<String> _rels(FilingPlan p) => p.entries.map((e) => e.relPath).toList();

void main() {
  test('within-batch collisions get a numbered suffix', () {
    final plan = planFiling(byYearMonthDay(), [
      _src('a'),
      _src('b'),
      _src('c'),
    ]);
    expect(_rels(plan), [
      '2024/03/15/IMG.jpg',
      '2024/03/15/IMG-01.jpg',
      '2024/03/15/IMG-02.jpg',
    ]);
  });

  test('alwaysApply suffixes even the first file', () {
    final scheme = byYearMonthDay()
      ..options = const SchemeOptions(suffix: Suffix(alwaysApply: true));
    final plan = planFiling(scheme, [_src('a'), _src('b'), _src('c')]);
    expect(_rels(plan), [
      '2024/03/15/IMG-01.jpg',
      '2024/03/15/IMG-02.jpg',
      '2024/03/15/IMG-03.jpg',
    ]);
  });

  test('ignoreExtensionOnClash treats same root across extensions as a clash',
      () {
    final plan = planFiling(byYearMonthDay(), [
      _src('a', name: 'A', ext: '.jpg'),
      _src('b', name: 'A', ext: '.png'),
    ]);
    expect(_rels(plan), ['2024/03/15/A.jpg', '2024/03/15/A-01.png']);
  });

  test('ignoreExtensionOnClash=false lets different extensions coexist', () {
    final scheme = byYearMonthDay()
      ..options =
          const SchemeOptions(suffix: Suffix(ignoreExtensionOnClash: false));
    final plan = planFiling(scheme, [
      _src('a', name: 'A', ext: '.jpg'),
      _src('b', name: 'A', ext: '.png'),
    ]);
    expect(_rels(plan), ['2024/03/15/A.jpg', '2024/03/15/A.png']);
  });

  test('an existing destination path forces a suffix', () {
    final plan = planFiling(
      byYearMonthDay(),
      [_src('a')],
      destExists: (rel) => rel == '2024/03/15/IMG.jpg',
    );
    expect(_rels(plan), ['2024/03/15/IMG-01.jpg']);
  });

  test('counter schemes avoid collisions on their own', () {
    final plan = planFiling(flatDate(), [_src('a'), _src('b'), _src('c')]);
    expect(_rels(plan), [
      '2024-03-15-001.jpg',
      '2024-03-15-002.jpg',
      '2024-03-15-003.jpg',
    ]);
  });

  test('custom separator and min-digits', () {
    final scheme = byYearMonthDay()
      ..options = const SchemeOptions(
        suffix: Suffix(separator: '_', minDigits: 3),
      );
    final plan = planFiling(scheme, [_src('a'), _src('b')]);
    expect(_rels(plan), ['2024/03/15/IMG.jpg', '2024/03/15/IMG_001.jpg']);
  });
}
