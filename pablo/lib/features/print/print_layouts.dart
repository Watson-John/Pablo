// print_layouts.dart — pure page-layout math for printing (Picasa parity §10:
// layouts + contact sheet). No pdf/printing imports here so the geometry is
// unit-testable in the plain VM: given a layout and a photo count, it returns
// the per-page list of normalized cell rects (0..1 of the printable area) plus
// whether each cell shows a filename caption. print_service turns these into a
// pw.Document.

import 'dart:math';

/// A print layout choice.
enum PrintLayout {
  full, // one photo per page, centered
  twoUp, // 2 per page (stacked)
  fourUp, // 2x2 grid
  contactSheet, // dense N x M grid with filename captions
}

extension PrintLayoutLabel on PrintLayout {
  String get label => switch (this) {
        PrintLayout.full => 'Full page (1 per page)',
        PrintLayout.twoUp => '2 per page',
        PrintLayout.fourUp => '4 per page',
        PrintLayout.contactSheet => 'Contact sheet',
      };

  /// Photos per page for the fixed layouts; contact sheet is computed from its
  /// column count.
  int get perPage => switch (this) {
        PrintLayout.full => 1,
        PrintLayout.twoUp => 2,
        PrintLayout.fourUp => 4,
        PrintLayout.contactSheet => 0, // see contactColumns/contactRows
      };
}

/// A normalized cell on a page: rect in [0,1] of the printable area, the index
/// into the source photo list, and whether to caption it.
class PrintCell {
  const PrintCell({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.caption,
  });

  final int index;
  final double left;
  final double top;
  final double width;
  final double height;
  final bool caption;
}

/// Contact-sheet grid dimensions for [count] photos: a near-square grid capped
/// at [maxColumns] columns.
({int columns, int rows}) contactGrid(int count, {int maxColumns = 5}) {
  if (count <= 0) return (columns: 1, rows: 1);
  final columns = min(maxColumns, max(1, sqrt(count).ceil()));
  final rows = (count / columns).ceil();
  return (columns: columns, rows: rows);
}

/// Split [count] photos into pages of normalized cells for [layout].
///
/// [gap] is the inter-cell margin as a fraction of the printable area.
/// [contactColumns]/[contactRows] size the contact-sheet grid per page
/// (defaults: 5 columns, 6 rows = 30 per page).
List<List<PrintCell>> layoutPages(
  int count,
  PrintLayout layout, {
  double gap = 0.03,
  int contactColumns = 5,
  int contactRows = 6,
}) {
  if (count <= 0) return const [];
  final (cols, rows, caption) = switch (layout) {
    PrintLayout.full => (1, 1, false),
    PrintLayout.twoUp => (1, 2, false),
    PrintLayout.fourUp => (2, 2, false),
    PrintLayout.contactSheet => (contactColumns, contactRows, true),
  };
  final perPage = cols * rows;
  final pages = <List<PrintCell>>[];
  final cellW = (1 - gap * (cols + 1)) / cols;
  final cellH = (1 - gap * (rows + 1)) / rows;

  var index = 0;
  while (index < count) {
    final cells = <PrintCell>[];
    for (var slot = 0; slot < perPage && index < count; slot++, index++) {
      final r = slot ~/ cols;
      final c = slot % cols;
      cells.add(PrintCell(
        index: index,
        left: gap + c * (cellW + gap),
        top: gap + r * (cellH + gap),
        width: cellW,
        height: cellH,
        caption: caption,
      ));
    }
    pages.add(cells);
  }
  return pages;
}

/// The full-resolution long-edge (px) to render each source at for [layout] —
/// n-up prints want a crisp ~2480 px, contact-sheet cells only ~1024 px.
int renderDimFor(PrintLayout layout) =>
    layout == PrintLayout.contactSheet ? 1024 : 2480;
