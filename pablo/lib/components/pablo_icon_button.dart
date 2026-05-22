// Round IconBtn — single-icon button with hover state and optional active tint.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

class PabloIconButton extends StatefulWidget {
  const PabloIconButton({
    required this.icon,
    this.onPressed,
    this.size = 30,
    this.iconSize = 16,
    this.tooltip,
    this.active = false,
    this.color,
    this.background,
    this.elevated = false,
    super.key,
  });

  final PabloIconName icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool active;
  final Color? color;
  final Color? background;

  /// When true, paints the icon button on a raised surface (for the controls bar).
  final bool elevated;

  @override
  State<PabloIconButton> createState() => _PabloIconButtonState();
}

class _PabloIconButtonState extends State<PabloIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.color ??
        (widget.active ? PabloColors.accentPrimary : PabloColors.textSecondary);

    Color bg;
    if (widget.background != null) {
      bg = widget.background!;
    } else if (widget.elevated) {
      bg = PabloColors.backgroundSurface;
    } else if (widget.active) {
      bg = PabloColors.accentBackground;
    } else if (_hover) {
      bg = PabloColors.backgroundHover;
    } else {
      bg = Colors.transparent;
    }

    Widget btn = AnimatedContainer(
      duration: PabloDurations.hover,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: widget.elevated ? PabloShadows.floatingButton : null,
        border: widget.elevated
            ? Border.all(color: PabloColors.borderSubtle)
            : null,
      ),
      child: Center(
        child: PabloIcon(widget.icon, size: widget.iconSize, color: iconColor),
      ),
    );

    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: btn,
      ),
    );
  }
}
