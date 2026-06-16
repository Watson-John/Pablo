// Sidebar section — a bordered, collapsible card (Pablo v4 / Pablo DS). A 36px
// header carries a wayfinding-colored icon, a serif label, an item count (when
// collapsed) and optional trailing controls; a right-side chevron rotates open.
// The divider under the header shows only while expanded.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    required this.label,
    required this.child,
    this.icon,
    this.iconColor,
    this.defaultOpen = true,
    this.collapsedCount,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;

  /// Wayfinding icon shown at the left of the header (e.g. People/Albums).
  final PabloIconName? icon;

  /// Color for [icon] — the section's wayfinding hue. Azure stays reserved for
  /// active/selected row state, so this is the resting color.
  final Color? iconColor;

  final bool defaultOpen;
  final String? collapsedCount;
  final Widget? trailing;

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(PabloSpacing.base, PabloSpacing.sm,
          PabloSpacing.base, PabloSpacing.md),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.mdAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: PabloColors.backgroundSidebar,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                height: PabloSizing.controlMd, // 36
                padding:
                    const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          _open ? PabloColors.borderStrong : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      PabloIcon(
                        widget.icon!,
                        size: 14,
                        // Nav section icons are always the filled glyph (design
                        // navPeople/navAlbums/navFolders/navCalendar).
                        filled: true,
                        color: widget.iconColor ?? PabloColors.textPrimary,
                      ),
                      const SizedBox(width: PabloSpacing.base),
                    ],
                    Expanded(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: PabloTypography.serif(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!_open && widget.collapsedCount != null) ...[
                      Text(
                        widget.collapsedCount!,
                        style: PabloTypography.mono(
                          fontSize: 10,
                          color: PabloColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: PabloSpacing.sm),
                    ],
                    if (widget.trailing != null) widget.trailing!,
                    const SizedBox(width: PabloSpacing.sm),
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: PabloDurations.expand,
                      child: const PabloIcon(
                        PabloIconName.chevRight,
                        size: 9,
                        strokeWidth: 2.75,
                        color: PabloColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(
                top: PabloSpacing.sm,
                bottom: PabloSpacing.md,
              ),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
