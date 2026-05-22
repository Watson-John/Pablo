// Sidebar section header — uppercase label with chevron, optional trailing
// controls and an item count shown when collapsed.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

class CollapsibleSection extends StatefulWidget {
  const CollapsibleSection({
    required this.label,
    required this.child,
    this.defaultOpen = true,
    this.collapsedCount,
    this.trailing,
    super.key,
  });

  final String label;
  final Widget child;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: PabloColors.backgroundSidebar,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: PabloSpacing.xxl,
                vertical: PabloSpacing.base,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: PabloColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: PabloDurations.expand,
                    child: const PabloIcon(
                      PabloIconName.chevRight,
                      size: 9,
                      color: PabloColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: PabloSpacing.md),
                  Expanded(
                    child: Text(
                      widget.label.toUpperCase(),
                      style: PabloTypography.sectionLabelUpper,
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
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Container(
            padding: const EdgeInsets.only(
              top: PabloSpacing.sm,
              bottom: PabloSpacing.md,
            ),
            color: PabloColors.backgroundSurface,
            child: widget.child,
          ),
      ],
    );
  }
}
