// Small action buttons for the photo edit panel (Auto-Fix toggle, copper text
// link, "+ Add text" pill) — extracted from photo_edit_panel.dart.

import 'package:flutter/material.dart';

import '../../../components/pablo_icon.dart';
import '../../../theme/tokens.dart';

/// One-click "Auto-Fix" toggle (auto-levels). Copper-filled when active.
class AutoFixButton extends StatelessWidget {
  const AutoFixButton({required this.active, required this.onTap, super.key});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.control,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                active ? PabloColors.accentPrimary : PabloColors.backgroundSurfaceAlt,
            border: Border.all(
              color: active ? PabloColors.accentPrimary : PabloColors.borderStrong,
            ),
            borderRadius: PabloRadius.pillAll,
            boxShadow: active ? null : PabloShadows.sm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PabloIcon(
                PabloIconName.sparkle,
                size: 15,
                color:
                    active ? PabloColors.textOnAccent : PabloColors.accentPrimary,
              ),
              const SizedBox(width: PabloSpacing.base),
              Text(
                active ? 'Auto-Fix On' : 'Auto-Fix',
                style: PabloTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      active ? PabloColors.textOnAccent : PabloColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain copper text link.
class LinkButton extends StatelessWidget {
  const LinkButton({required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Text(
          label,
          style: PabloTypography.sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: PabloColors.accentPrimary,
          ),
        ),
      ),
    );
  }
}

/// "+ Add text" button for the Text section.
class AddTextButton extends StatelessWidget {
  const AddTextButton({required this.onTap, super.key});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurfaceAlt,
            border: Border.all(color: PabloColors.borderStrong),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const PabloIcon(PabloIconName.plus,
                  size: 12, strokeWidth: 2, color: PabloColors.accentPrimary),
              const SizedBox(width: PabloSpacing.sm),
              Text('Add text',
                  style: PabloTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PabloColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
