import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildPabloTheme() {
  final base = ThemeData.light(useMaterial3: false);
  return base.copyWith(
    scaffoldBackgroundColor: PabloColors.backgroundShell,
    canvasColor: PabloColors.backgroundShell,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: PabloColors.backgroundHover,
    focusColor: PabloColors.accentBackground,
    dividerColor: PabloColors.borderSubtle,
    textTheme: base.textTheme.apply(
      bodyColor: PabloColors.textPrimary,
      displayColor: PabloColors.textPrimary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: PabloColors.textPrimary,
        borderRadius: PabloRadius.mdAll,
      ),
      textStyle: PabloTypography.sans(
        fontSize: 11.5,
        color: PabloColors.textOnAccent,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.base,
        vertical: PabloSpacing.sm,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
  );
}
