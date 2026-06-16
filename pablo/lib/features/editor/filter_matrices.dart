// Color filter matrices approximating the design's CSS `filter` strings.
// Used by the photo editor's filter row + lightbox preview.

import 'dart:ui';

class FilterDef {
  const FilterDef(
      {required this.id, required this.label, required this.filter});
  final String id;
  final String label;
  final ColorFilter? filter;
}

List<FilterDef> get kEditorFilters => [
      const FilterDef(id: 'none', label: 'Original', filter: null),
      FilterDef(id: 'vivid', label: 'Vivid', filter: _saturate(1.6, 1.12)),
      FilterDef(id: 'cool', label: 'Cool', filter: _hueShift(-25, 1.1, 1.02)),
      FilterDef(id: 'warm', label: 'Warm', filter: _hueShift(18, 1.2, 1.04)),
      const FilterDef(id: 'bw', label: 'B&W', filter: _bw),
      FilterDef(id: 'fade', label: 'Fade', filter: _saturate(0.7, 0.82, 1.1)),
      FilterDef(
          id: 'dramatic', label: 'Dramatic', filter: _saturate(1.25, 1.45)),
      const FilterDef(id: 'noir', label: 'Noir', filter: _noir),
      FilterDef(
          id: 'matte', label: 'Matte', filter: _saturate(0.6, 0.88, 1.06)),
      const FilterDef(id: 'film', label: 'Film', filter: _film),
      const FilterDef(id: 'golden', label: 'Golden', filter: _golden),
      FilterDef(id: 'lush', label: 'Lush', filter: _saturate(1.3, 1.05)),
    ];

ColorFilter _saturate(double s, [double c = 1.0, double b = 1.0]) {
  final lr = 0.2126, lg = 0.7152, lb = 0.0722;
  // saturate scales chromatic, contrast scales around 0.5, brightness scales linearly.
  final r1 = (1 - s) * lr + s, g1 = (1 - s) * lg, b1 = (1 - s) * lb;
  final r2 = (1 - s) * lr, g2 = (1 - s) * lg + s, b2 = (1 - s) * lb;
  final r3 = (1 - s) * lr, g3 = (1 - s) * lg, b3 = (1 - s) * lb + s;
  return ColorFilter.matrix(<double>[
    r1 * c * b,
    g1 * c * b,
    b1 * c * b,
    0,
    128 * (1 - c) * b,
    r2 * c * b,
    g2 * c * b,
    b2 * c * b,
    0,
    128 * (1 - c) * b,
    r3 * c * b,
    g3 * c * b,
    b3 * c * b,
    0,
    128 * (1 - c) * b,
    0,
    0,
    0,
    1,
    0,
  ]);
}

ColorFilter _hueShift(double degrees, double sat, double bright) {
  // Approximation: blend saturate with a slight channel rotation.
  final s = sat;
  final lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final r1 = (1 - s) * lr + s, g1 = (1 - s) * lg, b1 = (1 - s) * lb;
  final r2 = (1 - s) * lr, g2 = (1 - s) * lg + s, b2 = (1 - s) * lb;
  final r3 = (1 - s) * lr, g3 = (1 - s) * lg, b3 = (1 - s) * lb + s;
  // Slight bias toward red (warm) or blue (cool).
  final warmBias = degrees > 0 ? degrees / 180.0 : 0.0;
  final coolBias = degrees < 0 ? -degrees / 180.0 : 0.0;
  return ColorFilter.matrix(<double>[
    r1 * bright + warmBias * 20,
    g1 * bright,
    b1 * bright,
    0,
    0,
    r2 * bright,
    g2 * bright,
    b2 * bright,
    0,
    0,
    r3 * bright,
    g3 * bright,
    b3 * bright + coolBias * 20,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}

const ColorFilter _bw = ColorFilter.matrix(<double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

const ColorFilter _noir = ColorFilter.matrix(<double>[
  0.2976,
  1.0013,
  0.1011,
  0,
  -32,
  0.2976,
  1.0013,
  0.1011,
  0,
  -32,
  0.2976,
  1.0013,
  0.1011,
  0,
  -32,
  0,
  0,
  0,
  1,
  0,
]);

const ColorFilter _film = ColorFilter.matrix(<double>[
  0.39,
  0.769,
  0.189,
  0,
  -10,
  0.349,
  0.686,
  0.168,
  0,
  -10,
  0.272,
  0.534,
  0.131,
  0,
  -10,
  0,
  0,
  0,
  1,
  0,
]);

const ColorFilter _golden = ColorFilter.matrix(<double>[
  0.42,
  0.85,
  0.20,
  0,
  10,
  0.38,
  0.77,
  0.18,
  0,
  10,
  0.30,
  0.60,
  0.14,
  0,
  5,
  0,
  0,
  0,
  1,
  0,
]);
