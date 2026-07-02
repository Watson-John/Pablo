// gallery_scroll_math_test.dart — the pure offset math behind Show in Pablo
// and sidebar-click scroll. Grid offsets are exact; masonry packing mirrors
// SliverMasonryGrid.count's shortest-column algorithm.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/gallery/gallery_scroll.dart';

void main() {
  const header = 64.0, padTop = 12.0, padBottom = 18.0, gap = 8.0;

  group('gridSectionExtent', () {
    test('sums header + padding + rows (each with a trailing gap)', () {
      // Two rows of 100px: 64 + (12 + (100+8) + (100+8) + 18) = 310.
      expect(
        gridSectionExtent([100, 100],
            gap: gap, headerExtent: header, padTop: padTop, padBottom: padBottom),
        64 + 12 + 108 + 108 + 18,
      );
    });

    test('an empty section is just its header', () {
      expect(
        gridSectionExtent([],
            gap: gap, headerExtent: header, padTop: padTop, padBottom: padBottom),
        header,
      );
    });
  });

  group('gridTargetOffset', () {
    test('first row of the first section lands at 0 (row clears header)', () {
      final o = gridTargetOffset(
        sectionExtentsBefore: const [],
        headerExtent: header,
        padTop: padTop,
        targetRowHeights: const [100, 100],
        gap: gap,
        targetRowIndex: 0,
      );
      // header + padTop - header = padTop, then never negative.
      expect(o, padTop);
    });

    test('a later row sums the rows above it', () {
      final o = gridTargetOffset(
        sectionExtentsBefore: const [],
        headerExtent: header,
        padTop: padTop,
        targetRowHeights: const [100, 120, 80],
        gap: gap,
        targetRowIndex: 2,
      );
      // padTop + (100+8) + (120+8) = 12 + 108 + 128 = 248.
      expect(o, 248);
    });

    test('preceding section extents are added', () {
      final o = gridTargetOffset(
        sectionExtentsBefore: const [310, 64],
        headerExtent: header,
        padTop: padTop,
        targetRowHeights: const [100],
        gap: gap,
        targetRowIndex: 0,
      );
      expect(o, 310 + 64 + padTop);
    });
  });

  group('rowIndexForPhoto', () {
    final rows = [
      (start: 0, count: 3),
      (start: 3, count: 2),
      (start: 5, count: 4),
    ];
    test('locates the row that holds the photo index', () {
      expect(rowIndexForPhoto(rows, 0), 0);
      expect(rowIndexForPhoto(rows, 4), 1);
      expect(rowIndexForPhoto(rows, 8), 2);
    });
    test('out-of-range falls back to 0', () {
      expect(rowIndexForPhoto(rows, 99), 0);
    });
  });

  group('masonryLayout', () {
    test('packs into the shortest column and reports tops', () {
      // 2 cols, gap 10. Heights: 100, 50, 30.
      //  tile0 → col0 top 0; col0 = 110
      //  tile1 → col1 top 0; col1 = 60
      //  tile2 → col1 (shorter) top 60; col1 = 100
      final r = masonryLayout([100, 50, 30], 2, 10);
      expect(r.tops, [0, 0, 60]);
      // content = max(110,100) - gap = 100.
      expect(r.contentHeight, 100);
    });

    test('single column stacks with gaps', () {
      final r = masonryLayout([40, 40], 1, 5);
      expect(r.tops, [0, 45]);
      // col height after both = 40+5 + 40+5 = 90; drop the trailing gap → 85.
      expect(r.contentHeight, 85);
    });
  });
}
