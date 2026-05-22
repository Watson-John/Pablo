// Generic sidebar row primitive — icon + label + optional count/badge.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

class NavItem extends StatefulWidget {
  const NavItem({
    required this.label,
    this.icon,
    this.count,
    this.badge,
    this.active = false,
    this.onPressed,
    this.leading,
    this.indent = PabloSpacing.xl,
    this.trailing,
    this.fontSize = 13,
    super.key,
  });

  final String label;
  final PabloIconName? icon;
  final String? count;
  final Widget? badge;
  final bool active;
  final VoidCallback? onPressed;

  /// Optional leading widget that replaces the icon (e.g. avatar).
  final Widget? leading;
  final double indent;
  final Widget? trailing;
  final double fontSize;

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? PabloColors.selectionBackground
        : _hover
            ? PabloColors.backgroundSidebarHover
            : Colors.transparent;
    final iconColor = widget.active
        ? PabloColors.selectionPrimary
        : PabloColors.textMuted;
    final textWeight = widget.active ? FontWeight.w600 : FontWeight.w500;

    final leading = widget.leading ??
        (widget.icon != null
            ? PabloIcon(widget.icon!, size: 16, color: iconColor)
            : null);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: PabloDurations.hover,
          margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
          padding: EdgeInsets.only(
            left: widget.indent,
            right: PabloSpacing.xl,
          ),
          height: widget.fontSize >= 13 ? 32 : 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: PabloSpacing.base),
              ],
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: widget.fontSize,
                    fontWeight: textWeight,
                  ),
                ),
              ),
              if (widget.badge != null) ...[
                widget.badge!,
                const SizedBox(width: PabloSpacing.sm),
              ],
              if (widget.count != null)
                Text(
                  widget.count!,
                  style: PabloTypography.mono(
                    fontSize: 11,
                    color: PabloColors.textMuted,
                  ),
                ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
