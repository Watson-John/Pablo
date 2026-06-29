// Pure unit tests for the justified row packer — no Flutter/GPU needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/gallery/justified_rows.dart';

void main() {
  const avail = 800.0;
  const targetH = 130.0;
  const gap = 8.0;

  group('packRows', () {
    test('empty input produces no rows', () {
      expect(
        packRows(
            aspects: const [], availWidth: avail, targetH: targetH, gap: gap),
        isEmpty,
      );
    });

    test('non-last rows fill the available width exactly', () {
      final aspects = List<double>.filled(60, 1.5);
      final rows = packRows(
          aspects: aspects, availWidth: avail, targetH: targetH, gap: gap);
      expect(rows.length, greaterThan(2));
      for (var r = 0; r < rows.length - 1; r++) {
        final row = rows[r];
        final total =
            row.widths.fold<double>(0, (a, b) => a + b) + gap * (row.count - 1);
        expect(total, closeTo(avail, 0.5),
            reason: 'row $r should be justified to the full width');
      }
    });

    test('every tile in a row shares one height; widths preserve aspect', () {
      final aspects = [
        1.5,
        0.66,
        1.0,
        1.78,
        0.8,
        1.33,
        1.5,
        0.66,
        1.0,
        1.78,
        0.7
      ];
      final rows = packRows(
          aspects: aspects, availWidth: avail, targetH: targetH, gap: gap);
      for (final row in rows) {
        for (var k = 0; k < row.count; k++) {
          // width/height is exactly the (clamped) aspect → no cropping.
          final wantAspect = aspects[row.start + k].clamp(0.2, 5.0);
          expect(row.widths[k] / row.height, closeTo(wantAspect, 1e-9));
        }
      }
    });

    test('last row is left ragged at the target height', () {
      final aspects = List<double>.filled(7, 1.5);
      final rows = packRows(
          aspects: aspects, availWidth: avail, targetH: targetH, gap: gap);
      expect(rows.last.height, targetH);
    });

    test('portrait images stay portrait (taller than wide)', () {
      final rows = packRows(
          aspects: const [0.66], availWidth: avail, targetH: targetH, gap: gap);
      expect(rows.single.widths.single, lessThan(rows.single.height));
    });

    test('extreme aspects are clamped, never degenerate', () {
      final rows = packRows(
          aspects: const [100.0, 0.001, 1.0],
          availWidth: avail,
          targetH: targetH,
          gap: gap);
      for (final row in rows) {
        for (final w in row.widths) {
          expect(w, greaterThan(0));
          expect(w.isFinite, isTrue);
        }
      }
    });
  });

  group('lookAheadIndices', () {
    JRow row(int start, int count) => JRow(
        start: start,
        count: count,
        height: 100,
        widths: List.filled(count, 50));

    test('returns the photo indices of the next N rows', () {
      final plan = [row(0, 3), row(3, 2), row(5, 4), row(9, 1)];
      // From row 0, look ahead 2 rows → row 1 (3,4) + row 2 (5,6,7,8).
      expect(lookAheadIndices(plan, 0, 2), [3, 4, 5, 6, 7, 8]);
    });

    test('clamps at the end of the plan (no rows after the last)', () {
      final plan = [row(0, 2), row(2, 2)];
      expect(lookAheadIndices(plan, 1, 3), isEmpty);
    });

    test('empty plan or non-positive rows yields nothing', () {
      expect(lookAheadIndices(const [], 0, 3), isEmpty);
      expect(lookAheadIndices([row(0, 2)], 0, 0), isEmpty);
    });
  });
}
