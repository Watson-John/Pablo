// Tab model + underline tab button for the Unnamed Faces page; extracted
// from unnamed_faces_page.dart.

import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

enum UnnamedTabId { groups, unclustered, ignored }

class UnnamedTab {
  const UnnamedTab(this.id, this.label, this.count);
  final UnnamedTabId id;
  final String label;
  final int count;
}

class UnnamedTabButton extends StatelessWidget {
  const UnnamedTabButton({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
  });
  final UnnamedTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          decoration: BoxDecoration(
            // Conventional underline tab: 2px accent bar under the active tab.
            border: Border(
              bottom: BorderSide(
                color: active ? PabloColors.accentPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: PabloTypography.sans(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active
                      ? PabloColors.accentPrimary
                      : PabloColors.textSecondary,
                ),
              ),
              if (tab.count > 0) ...[
                const SizedBox(width: PabloSpacing.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PabloSpacing.md,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? PabloColors.accentBackground
                        : PabloColors.backgroundSurfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${tab.count}',
                    style: PabloTypography.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? PabloColors.accentPrimary
                          : PabloColors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
