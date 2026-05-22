// Gradient avatar circle with single initial. Hue parameter drives an OKLCH-ish
// gradient (we use HSL to keep it pure Flutter).

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PabloAvatar extends StatelessWidget {
  const PabloAvatar({
    required this.name,
    this.hue = 200,
    this.size = 32,
    super.key,
  });

  final String name;
  final int hue;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final top = HSLColor.fromAHSL(1, hue.toDouble() % 360, 0.36, 0.72).toColor();
    final bottom =
        HSLColor.fromAHSL(1, (hue + 15) % 360, 0.42, 0.55).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: Text(
        initial,
        style: PabloTypography.sans(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          color: PabloColors.avatarInitial,
        ),
      ),
    );
  }
}
