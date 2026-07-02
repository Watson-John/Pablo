// world_geometry.dart — equirectangular projection helpers + a compact,
// simplified world landmass outline for the real (world-wide) photo map.
//
// The outlines are deliberately coarse (a few dozen points per continent) —
// enough to make the map recognizable as Earth and place markers in the right
// place, without bundling a heavyweight vector dataset or a new dependency. The
// projection is plain equirectangular (Plate Carrée): x ∝ longitude, y ∝
// latitude, which keeps marker math trivial and matches how the coordinates are
// stored.

import 'dart:ui' show Offset;

/// Project (lat, lon) into normalized [0,1] map space (x → right, y → down).
/// Longitude −180..180 maps to x 0..1; latitude 90..−90 maps to y 0..1.
Offset projectNorm(double lat, double lon) {
  final x = (lon + 180.0) / 360.0;
  final y = (90.0 - lat) / 180.0;
  return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
}

/// Inverse of [projectNorm]: normalized map space back to (lat, lon).
/// Returns [lat, lon].
List<double> unprojectNorm(double nx, double ny) {
  final lon = nx * 360.0 - 180.0;
  final lat = 90.0 - ny * 180.0;
  return [lat, lon];
}

/// Simplified continent polygons, each a closed ring of [lon, lat] points.
/// Coarse by design — see the file header.
const List<List<List<double>>> kWorldOutline = [
  // North America
  [
    [-168, 65], [-162, 70], [-140, 70], [-128, 70], [-115, 69], [-95, 72],
    [-82, 73], [-73, 68], [-64, 60], [-56, 53], [-66, 45], [-70, 43],
    [-74, 40], [-76, 35], [-81, 31], [-80, 25], [-90, 29], [-97, 26],
    [-97, 22], [-105, 20], [-106, 23], [-110, 24], [-114, 28], [-117, 32],
    [-124, 40], [-124, 48], [-130, 54], [-140, 59], [-152, 58], [-158, 56],
    [-165, 60], [-168, 65],
  ],
  // Greenland
  [
    [-45, 60], [-42, 66], [-38, 70], [-30, 74], [-25, 78], [-30, 82],
    [-45, 83], [-58, 82], [-68, 80], [-58, 74], [-53, 68], [-50, 62],
    [-45, 60],
  ],
  // South America
  [
    [-81, 6], [-77, 8], [-72, 11], [-64, 10], [-60, 6], [-52, 5],
    [-50, 0], [-44, -2], [-38, -7], [-35, -12], [-39, -18], [-48, -25],
    [-53, -34], [-58, -38], [-62, -40], [-65, -45], [-69, -51], [-74, -52],
    [-72, -45], [-73, -38], [-71, -30], [-71, -20], [-76, -14], [-80, -6],
    [-81, 0], [-81, 6],
  ],
  // Africa
  [
    [-17, 15], [-16, 21], [-10, 30], [0, 36], [10, 37], [20, 33],
    [25, 32], [32, 31], [34, 28], [38, 18], [43, 11], [51, 12],
    [43, 5], [41, -2], [40, -10], [35, -18], [33, -26], [26, -34],
    [18, -34], [12, -18], [9, -2], [8, 4], [-4, 5], [-10, 6],
    [-13, 9], [-17, 15],
  ],
  // Europe
  [
    [-10, 43], [-9, 38], [-5, 36], [3, 42], [8, 44], [12, 45],
    [18, 40], [24, 40], [28, 41], [30, 46], [38, 46], [40, 55],
    [30, 60], [24, 66], [20, 70], [10, 64], [5, 61], [8, 58],
    [4, 52], [-2, 49], [-5, 48], [-9, 44], [-10, 43],
  ],
  // Asia
  [
    [26, 41], [40, 42], [48, 40], [50, 30], [57, 25], [60, 25],
    [67, 25], [70, 21], [73, 16], [78, 8], [80, 13], [90, 22],
    [92, 21], [98, 8], [104, 1], [110, 20], [122, 31], [122, 40],
    [128, 42], [130, 43], [135, 48], [142, 54], [160, 61], [170, 68],
    [180, 69], [170, 72], [140, 73], [110, 74], [90, 76], [70, 73],
    [60, 71], [55, 68], [65, 60], [60, 54], [50, 46], [40, 46],
    [30, 46], [28, 41], [26, 41],
  ],
  // Australia
  [
    [114, -22], [122, -18], [130, -12], [137, -12], [142, -11], [146, -18],
    [150, -24], [153, -28], [151, -34], [146, -38], [140, -38], [136, -35],
    [129, -32], [122, -34], [115, -34], [113, -26], [114, -22],
  ],
];
