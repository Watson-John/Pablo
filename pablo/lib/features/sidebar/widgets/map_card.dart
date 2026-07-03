// Map nav card for the sidebar — moved out of sidebar.dart (was _MapCard).

import 'package:flutter/material.dart';

import '../../../components/hover_surface.dart';
import '../../../components/pablo_icon.dart';
import '../../../theme/tokens.dart';

/// Map nav as a standalone bordered card matching the section-header chrome
/// (non-collapsible). Icon is teal at rest, azure when the Map view is active.
class SidebarMapCard extends StatelessWidget {
  const SidebarMapCard({required this.active, required this.onTap, super.key});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        PabloSpacing.base,
        PabloSpacing.sm,
        PabloSpacing.base,
        PabloSpacing.md,
      ),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.mdAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: HoverSurface(
        onTap: onTap,
        builder: (context, hovered) {
          final headerBg = active
              ? PabloColors.backgroundSelected
              : hovered
                  ? PabloColors.backgroundSidebarHover
                  : PabloColors.backgroundSidebar;
          return AnimatedContainer(
            duration: PabloDurations.hover,
            height: PabloSizing.controlMd,
            padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
            color: headerBg,
            child: Row(
              children: [
                PabloIcon(
                  PabloIconName.map,
                  size: 14,
                  filled: true, // design navMap = location_on (filled)
                  color: active
                      ? PabloColors.accentActive
                      : PabloColors.sectionMap,
                ),
                const SizedBox(width: PabloSpacing.base),
                Expanded(
                  child: Text(
                    'Map',
                    style: PabloTypography.serif(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '0',
                  style: PabloTypography.mono(
                    fontSize: 10,
                    color: PabloColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
