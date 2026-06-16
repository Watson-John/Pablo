// decision_buttons.dart — the shared confirm/reject pill button used by both
// the People suggestion strips (people_scroll_view) and the info-panel
// suggestion rows (people_tab). The two surfaces arrange the pair differently
// (equal split vs. expand-the-accept), so the reusable unit is the pill; each
// call site lays out its own Row.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class DecisionPill extends StatelessWidget {
  const DecisionPill({
    required this.label,
    required this.color,
    required this.onTap,
    this.height = 24,
    this.width,
    this.fontSize = 13,
    this.borderRadius,
    super.key,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final double height;

  /// Fixed width, or null to be sized by the parent (e.g. wrapped in Expanded).
  final double? width;
  final double fontSize;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius ?? PabloRadius.pillAll,
          ),
          child: Text(
            label,
            style: PabloTypography.sans(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: PabloColors.textOnAccent,
            ),
          ),
        ),
      ),
    );
  }
}
