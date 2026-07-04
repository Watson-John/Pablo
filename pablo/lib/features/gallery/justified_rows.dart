// justified_rows.dart — pure justified-gallery row packing (Google-Photos /
// Flickr "justified layout"). No Flutter imports → unit-testable.
//
// Given each photo's aspect ratio (w/h), pack photos into rows that all share a
// target height: grow a row at [targetH] until the tiles + gaps fill the
// available width, then scale the row's height so the widths fill it exactly
// (justify). The last row is left ragged at [targetH]. Tile widths are always
// aspect × rowHeight, so images keep their true shape and are never cropped.

const double _kMinAspect = 0.2; // guard corrupt headers / extreme panoramas
const double _kMaxAspect = 5.0;

class JRow {
  const JRow({
    required this.start,
    required this.count,
    required this.height,
    required this.widths,
  });

  /// Index of this row's first photo in the section list.
  final int start;
  final int count;
  final double height;
  final List<double> widths;
}

/// Pack [aspects] into justified rows. [availWidth] is the content width (gaps
/// included), [targetH] the desired row height, [gap] the spacing between tiles.
List<JRow> packRows({
  required List<double> aspects,
  required double availWidth,
  required double targetH,
  required double gap,
}) {
  final rows = <JRow>[];
  final n = aspects.length;
  if (n == 0 || availWidth <= 0 || targetH <= 0) return rows;

  var i = 0;
  while (i < n) {
    var sumAsp = 0.0;
    var j = i;
    while (j < n) {
      sumAsp += aspects[j].clamp(_kMinAspect, _kMaxAspect).toDouble();
      j++;
      final gaps = gap * (j - i - 1);
      if (sumAsp * targetH + gaps >= availWidth) break;
    }
    final count = j - i;
    final gaps = gap * (count - 1);
    final isLast = j >= n;
    // Row height that would make the tiles fill availWidth exactly.
    final natural = sumAsp > 0 ? (availWidth - gaps) / sumAsp : targetH;
    // Justify full rows to fill the width; leave the last row ragged at target
    // height. Clamp so a sparse last-ish row can't balloon or collapse.
    var height = isLast
        ? targetH
        : natural.clamp(0.7 * targetH, 1.4 * targetH).toDouble();
    // Never overflow the row's width: a ragged last row (or the min-height
    // clamp on a dense row) can otherwise make the tiles sum wider than
    // availWidth, which shows as a RenderFlex overflow at narrow widths. When
    // that would happen, fall back to the exact-fit height (degrade gracefully
    // to a shorter row rather than overflowing). The +epsilon absorbs float
    // jitter so an exactly-filled row isn't needlessly rescaled.
    if (natural > 0 && sumAsp * height + gaps > availWidth + 0.01) {
      height = natural;
    }
    if (height < 1) height = 1;
    final widths = [
      for (var k = i; k < j; k++)
        aspects[k].clamp(_kMinAspect, _kMaxAspect).toDouble() * height,
    ];
    rows.add(JRow(start: i, count: count, height: height, widths: widths));
    i = j;
  }
  return rows;
}

/// Photo indices in the [rows] rows immediately AFTER [fromRow] in [plan] — the
/// look-ahead window the gallery hands to the speculative thumbnail prefetcher.
/// Pure (no Flutter), so it is unit-tested directly. Out-of-range rows are
/// skipped; an empty plan or non-positive [rows] yields no indices.
List<int> lookAheadIndices(List<JRow> plan, int fromRow, int rows) {
  final out = <int>[];
  if (plan.isEmpty || rows <= 0) return out;
  final last = plan.length - 1;
  for (var r = fromRow + 1; r <= fromRow + rows && r <= last; r++) {
    if (r < 0) continue;
    final row = plan[r];
    for (var k = 0; k < row.count; k++) {
      out.add(row.start + k);
    }
  }
  return out;
}
