// Small text pills. Two presets matching the design:
//   PabloBadge.count(...)   — muted count pill (used in sidebar / gallery).
//   PabloBadge.warning(...) — orange "?" pill for low-confidence suggestions.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PabloBadge extends StatelessWidget {
  const PabloBadge({
    required this.text,
    this.color = PabloColors.textMuted,
    this.background = PabloColors.backgroundHover,
    this.fontFamily = PabloBadgeFont.mono,
    this.borderColor,
    this.fontSize = 10,
    this.fontWeight = FontWeight.w600,
    super.key,
  });

  factory PabloBadge.count(String text) => PabloBadge(
        text: text,
        color: PabloColors.warningText,
        background: PabloColors.warningBackground,
        fontFamily: PabloBadgeFont.mono,
      );

  factory PabloBadge.warning() => const PabloBadge(
        text: '?',
        color: PabloColors.textOnAccent,
        background: PabloColors.warning,
        fontFamily: PabloBadgeFont.sans,
        borderColor: PabloColors.warningBadgeBorder,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      );

  final String text;
  final Color color;
  final Color background;
  final PabloBadgeFont fontFamily;
  final Color? borderColor;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.md - 1,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1.5)
            : null,
      ),
      child: Text(
        text,
        style: fontFamily == PabloBadgeFont.mono
            ? PabloTypography.mono(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
              )
            : PabloTypography.sans(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
              ),
      ),
    );
  }
}

enum PabloBadgeFont { mono, sans }
