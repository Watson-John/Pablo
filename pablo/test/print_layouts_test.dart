// print_layouts_test.dart — pure page-layout math: cell tiling per layout,
// contact-sheet pagination, and captions.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/print/print_layouts.dart';

void main() {
  test('full layout: one centered cell per page, one page per photo', () {
    final pages = layoutPages(3, PrintLayout.full);
    expect(pages.length, 3);
    expect(pages.every((p) => p.length == 1), isTrue);
    expect(pages.expand((p) => p).every((c) => !c.caption), isTrue);
  });

  test('4-up tiles a 2x2 grid without overlap and within bounds', () {
    final pages = layoutPages(4, PrintLayout.fourUp);
    expect(pages.length, 1);
    final cells = pages.first;
    expect(cells.length, 4);
    for (final c in cells) {
      expect(c.left, greaterThanOrEqualTo(0));
      expect(c.top, greaterThanOrEqualTo(0));
      expect(c.left + c.width, lessThanOrEqualTo(1.0 + 1e-9));
      expect(c.top + c.height, lessThanOrEqualTo(1.0 + 1e-9));
    }
    // No two cells overlap.
    for (var i = 0; i < cells.length; i++) {
      for (var j = i + 1; j < cells.length; j++) {
        expect(_overlap(cells[i], cells[j]), isFalse,
            reason: 'cells $i and $j overlap');
      }
    }
  });

  test('4-up spills to a second page for 5 photos', () {
    final pages = layoutPages(5, PrintLayout.fourUp);
    expect(pages.length, 2);
    expect(pages[0].length, 4);
    expect(pages[1].length, 1);
    // Indices are contiguous and complete.
    expect(pages.expand((p) => p).map((c) => c.index).toList(),
        [0, 1, 2, 3, 4]);
  });

  test('contact sheet: 35 photos at 5x6 → 2 pages, second has 5, captioned',
      () {
    final pages = layoutPages(35, PrintLayout.contactSheet,
        contactColumns: 5, contactRows: 6);
    expect(pages.length, 2);
    expect(pages[0].length, 30);
    expect(pages[1].length, 5);
    expect(pages.expand((p) => p).every((c) => c.caption), isTrue);
  });

  test('contactGrid is near-square and column-capped', () {
    expect(contactGrid(4), (columns: 2, rows: 2));
    expect(contactGrid(30).columns, lessThanOrEqualTo(5));
    final g = contactGrid(30);
    expect(g.columns * g.rows, greaterThanOrEqualTo(30));
  });

  test('renderDimFor: contact cells small, n-up large', () {
    expect(renderDimFor(PrintLayout.contactSheet), lessThan(2000));
    expect(renderDimFor(PrintLayout.fourUp), greaterThan(2000));
  });

  test('empty input yields no pages', () {
    expect(layoutPages(0, PrintLayout.full), isEmpty);
  });
}

bool _overlap(PrintCell a, PrintCell b) {
  final ax2 = a.left + a.width, ay2 = a.top + a.height;
  final bx2 = b.left + b.width, by2 = b.top + b.height;
  return a.left < bx2 && b.left < ax2 && a.top < by2 && b.top < ay2;
}
