// collage_layouts.dart — pure normalized-cell math for the collage compositor
// (Picasa parity §10 CCollageUI). No native/FFI imports so the geometry is
// unit-testable in the VM: given a photo count + template + spacing, return the
// per-cell rects in [0,1] canvas space that collage_controller feeds to
// Engine.createCollage.

import 'dart:math';
import 'dart:ui' show Rect;

/// A collage arrangement template.
enum CollageTemplate {
  grid, // near-square uniform grid
  featureLeft, // one large cell on the left, the rest stacked on the right
}

extension CollageTemplateLabel on CollageTemplate {
  String get label => switch (this) {
        CollageTemplate.grid => 'Grid',
        CollageTemplate.featureLeft => 'Feature + column',
      };
}

/// Near-square column count for [n] cells in a uniform grid.
int gridColumns(int n) => n <= 0 ? 1 : sqrt(n).ceil();

/// Normalized cell rects (in [0,1]²) for [count] photos under [template].
/// [spacing] is the gap between cells as a fraction of the canvas (also the
/// outer margin). Never returns overlapping rects.
List<Rect> collageCells(
  int count,
  CollageTemplate template, {
  double spacing = 0.02,
}) {
  if (count <= 0) return const [];
  final gap = spacing.clamp(0.0, 0.2).toDouble();
  if (template == CollageTemplate.featureLeft && count >= 2) {
    return _featureLeft(count, gap);
  }
  return _grid(count, gap);
}

List<Rect> _grid(int count, double gap) {
  final cols = gridColumns(count);
  final rows = (count / cols).ceil();
  final cellW = (1 - gap * (cols + 1)) / cols;
  final cellH = (1 - gap * (rows + 1)) / rows;
  final out = <Rect>[];
  for (var i = 0; i < count; i++) {
    final r = i ~/ cols;
    final c = i % cols;
    out.add(Rect.fromLTWH(
      gap + c * (cellW + gap),
      gap + r * (cellH + gap),
      cellW,
      cellH,
    ));
  }
  return out;
}

// One tall feature cell filling the left half; the remaining n-1 photos stack
// in a single column on the right.
List<Rect> _featureLeft(int count, double gap) {
  final out = <Rect>[];
  const leftW = 0.6;
  final featW = leftW - gap * 1.5;
  out.add(Rect.fromLTWH(gap, gap, featW - gap / 2, 1 - gap * 2));

  final rightCount = count - 1;
  final colX = leftW + gap / 2;
  final colW = 1 - colX - gap;
  final cellH = (1 - gap * (rightCount + 1)) / rightCount;
  for (var i = 0; i < rightCount; i++) {
    out.add(Rect.fromLTWH(colX, gap + i * (cellH + gap), colW, cellH));
  }
  return out;
}
