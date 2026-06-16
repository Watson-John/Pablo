// face_palette.dart — the shared two-stop HSL gradient used as a face
// placeholder tile (when no real crop is available). Centralized so the four
// People-card variants (cover crop fallback, group, solo, ignored) can't drift
// in their saturation/lightness/hue-shift constants. Pass the row's hue
// (see utils/hue.dart) so the placeholder matches the avatar/cover color.

import 'package:flutter/painting.dart';

LinearGradient faceTileGradient(
  int hue, {
  double satTop = 0.32,
  double lightTop = 0.72,
  int hueShift = 20,
  double satBottom = 0.44,
  double lightBottom = 0.56,
}) {
  final h = hue % 360;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      HSLColor.fromAHSL(1, h.toDouble(), satTop, lightTop).toColor(),
      HSLColor.fromAHSL(
        1,
        ((h + hueShift) % 360).toDouble(),
        satBottom,
        lightBottom,
      ).toColor(),
    ],
  );
}
