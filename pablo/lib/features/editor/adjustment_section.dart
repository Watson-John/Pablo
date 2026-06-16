import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';

/// A collapsible adjustment group (Light / Color / Detail) in the editor.
/// Pablo v4: a bordered card — header carries a wayfinding icon + serif label
/// + rotating chevron; the body is seamless below it when open.
class AdjustmentSection extends StatelessWidget {
  const AdjustmentSection({
    required this.label,
    required this.icon,
    required this.open,
    required this.onToggle,
    required this.children,
    super.key,
  });

  final String label;
  final PabloIconName icon;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PabloSpacing.xl,
                vertical: 7,
              ),
              margin: EdgeInsets.only(bottom: open ? 0 : PabloSpacing.lg),
              decoration: BoxDecoration(
                color: PabloColors.backgroundSidebar,
                border: Border.all(color: PabloColors.borderStrong),
                borderRadius: open
                    ? const BorderRadius.vertical(
                        top: Radius.circular(PabloRadius.md))
                    : PabloRadius.mdAll,
              ),
              child: Row(
                children: [
                  PabloIcon(icon, size: 15, color: PabloColors.textSecondary),
                  const SizedBox(width: PabloSpacing.base),
                  Expanded(
                    child: Text(
                      label,
                      style: PabloTypography.serif(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: PabloDurations.fast,
                    child: const PabloIcon(
                      PabloIconName.chevRight,
                      size: 10,
                      strokeWidth: 2.5,
                      color: PabloColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.only(bottom: PabloSpacing.lg),
            padding: const EdgeInsets.fromLTRB(PabloSpacing.lg, PabloSpacing.lg,
                PabloSpacing.lg, PabloSpacing.sm),
            decoration: const BoxDecoration(
              color: PabloColors.backgroundSurface,
              border: Border(
                left: BorderSide(color: PabloColors.borderStrong),
                right: BorderSide(color: PabloColors.borderStrong),
                bottom: BorderSide(color: PabloColors.borderStrong),
              ),
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(PabloRadius.md)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
      ],
    );
  }
}
