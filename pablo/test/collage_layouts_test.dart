// collage_layouts_test.dart — pure normalized-cell math: cells stay in [0,1],
// never overlap, honour spacing, and produce one rect per photo for n=2..9.

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/collage/collage_layouts.dart';

bool _overlap(Rect a, Rect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

void _assertValid(List<Rect> cells) {
  for (final c in cells) {
    expect(c.left, greaterThanOrEqualTo(-1e-9));
    expect(c.top, greaterThanOrEqualTo(-1e-9));
    expect(c.right, lessThanOrEqualTo(1.0 + 1e-9));
    expect(c.bottom, lessThanOrEqualTo(1.0 + 1e-9));
    expect(c.width, greaterThan(0));
    expect(c.height, greaterThan(0));
  }
  for (var i = 0; i < cells.length; i++) {
    for (var j = i + 1; j < cells.length; j++) {
      expect(_overlap(cells[i], cells[j]), isFalse,
          reason: 'cells $i and $j overlap');
    }
  }
}

void main() {
  test('grid: one rect per photo for n=2..9, all valid + non-overlapping', () {
    for (var n = 2; n <= 9; n++) {
      final cells = collageCells(n, CollageTemplate.grid);
      expect(cells.length, n);
      _assertValid(cells);
    }
  });

  test('featureLeft: one rect per photo, valid + non-overlapping', () {
    for (var n = 2; n <= 6; n++) {
      final cells = collageCells(n, CollageTemplate.featureLeft);
      expect(cells.length, n);
      _assertValid(cells);
    }
    // The feature (first) cell is the tallest.
    final cells = collageCells(4, CollageTemplate.featureLeft);
    for (var i = 1; i < cells.length; i++) {
      expect(cells.first.height, greaterThan(cells[i].height));
    }
  });

  test('gridColumns is near-square', () {
    expect(gridColumns(4), 2);
    expect(gridColumns(9), 3);
    expect(gridColumns(2), 2);
    expect(gridColumns(6), 3);
  });

  test('larger spacing shrinks cells', () {
    final tight = collageCells(4, CollageTemplate.grid, spacing: 0.01);
    final loose = collageCells(4, CollageTemplate.grid, spacing: 0.1);
    expect(loose.first.width, lessThan(tight.first.width));
  });

  test('empty input yields no cells', () {
    expect(collageCells(0, CollageTemplate.grid), isEmpty);
  });
}
