// gallery_scroll.dart — pure scroll-offset math for jumping the gallery to a
// section or a specific photo (Show in Pablo, and sidebar folder clicks).
//
// The layout it mirrors (see section_scroll_view.dart):
//   per section: [pinned header: headerExtent] [SliverPadding top: padTop]
//                [rows: each SizedBox(rowHeight) + Padding(bottom: gap)]
//                [SliverPadding bottom: padBottom]
//   empty section: [header] [emptyExtent]
// Grid mode has fixed per-row heights (packRows), so the offset is exact.
// Masonry heights are variable — the view estimates, jumps, then corrects with
// Scrollable.ensureVisible on the keyed target tile.

/// A request to bring a section (and optionally one photo in it) into view.
class GalleryScrollRequest {
  const GalleryScrollRequest(this.sectionId, {this.photoId});
  final String sectionId;
  final String? photoId;
}

/// Full scroll extent (header + content) of one grid-mode section.
double gridSectionExtent(
  List<double> rowHeights, {
  required double gap,
  required double headerExtent,
  required double padTop,
  required double padBottom,
}) {
  if (rowHeights.isEmpty) return headerExtent; // caller adds emptyExtent
  var content = padTop + padBottom;
  for (final h in rowHeights) {
    content += h + gap;
  }
  return headerExtent + content;
}

/// Offset (px from the top of the scroll view) that places the target row's
/// top just below the pinned header. [sectionExtentsBefore] are the full
/// extents of every section before the target; [targetRowHeights] the target
/// section's row heights; [targetRowIndex] the row that holds the photo.
/// Caller clamps to the scrollable's maxScrollExtent.
double gridTargetOffset({
  required List<double> sectionExtentsBefore,
  required double headerExtent,
  required double padTop,
  required List<double> targetRowHeights,
  required double gap,
  required int targetRowIndex,
}) {
  var offset = 0.0;
  for (final e in sectionExtentsBefore) {
    offset += e;
  }
  // Into the target section: header + top padding + rows above the target.
  offset += headerExtent + padTop;
  for (var i = 0; i < targetRowIndex && i < targetRowHeights.length; i++) {
    offset += targetRowHeights[i] + gap;
  }
  // Pull up by one header height so the row clears the sticky header that will
  // pin at the top; never scroll negative.
  offset -= headerExtent;
  return offset < 0 ? 0 : offset;
}

/// The index of the row containing photo [photoIndex], given row start indices
/// and counts (JRow.start / JRow.count). Returns 0 when not found.
int rowIndexForPhoto(
  List<({int start, int count})> rows,
  int photoIndex,
) {
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (photoIndex >= r.start && photoIndex < r.start + r.count) return i;
  }
  return 0;
}

/// Simulate SliverMasonryGrid.count's shortest-column packing for [tileHeights]
/// across [cols] columns with [gap] main-axis spacing. Returns the y-top of
/// each tile within the section content, and the section content height. This
/// is exact given the same tile heights the view lays out — the only wobble is
/// aspect ratios still streaming in, which is why masonry scroll is corrected
/// with ensureVisible after the jump.
({List<double> tops, double contentHeight}) masonryLayout(
  List<double> tileHeights,
  int cols,
  double gap,
) {
  final colHeights = List<double>.filled(cols < 1 ? 1 : cols, 0);
  final tops = <double>[];
  for (final h in tileHeights) {
    var min = 0;
    for (var c = 1; c < colHeights.length; c++) {
      if (colHeights[c] < colHeights[min]) min = c;
    }
    tops.add(colHeights[min]);
    colHeights[min] += h + gap;
  }
  var maxH = 0.0;
  for (final c in colHeights) {
    if (c > maxH) maxH = c;
  }
  // Drop the trailing gap of the tallest column.
  return (tops: tops, contentHeight: maxH > 0 ? maxH - gap : 0);
}
