// Btn — pill-shaped button with primary/secondary/ghost/success/danger
// variants in xs/sm/md sizes. Driven entirely by tokens.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

enum PabloButtonVariant { primary, secondary, ghost, success, danger }

enum PabloButtonSize { xs, sm, md }

class PabloButton extends StatefulWidget {
  const PabloButton({
    required this.label,
    this.onPressed,
    this.variant = PabloButtonVariant.secondary,
    this.size = PabloButtonSize.sm,
    this.icon,
    this.iconSize,
    this.disabled = false,
    this.tooltip,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final PabloButtonVariant variant;
  final PabloButtonSize size;
  final PabloIconName? icon;
  final double? iconSize;
  final bool disabled;
  final String? tooltip;
  final bool expand;

  @override
  State<PabloButton> createState() => _PabloButtonState();
}

class _PabloButtonState extends State<PabloButton> {
  bool _hover = false;
  bool _pressed = false;

  _Variant get _v {
    switch (widget.variant) {
      case PabloButtonVariant.primary:
        return const _Variant(
          bg: PabloColors.accentPrimary,
          bgHover: PabloColors.accentHover,
          bgPressed: PabloColors.accentActive,
          fg: PabloColors.textOnAccent,
          border: Colors.transparent,
        );
      case PabloButtonVariant.secondary:
        return const _Variant(
          bg: PabloColors.backgroundSurface,
          bgHover: PabloColors.backgroundHover,
          bgPressed: PabloColors.backgroundActive,
          fg: PabloColors.textPrimary,
          border: PabloColors.borderSubtle,
        );
      case PabloButtonVariant.ghost:
        return const _Variant(
          bg: Colors.transparent,
          bgHover: PabloColors.backgroundHover,
          bgPressed: PabloColors.backgroundActive,
          fg: PabloColors.textSecondary,
          border: Colors.transparent,
        );
      case PabloButtonVariant.success:
        return const _Variant(
          bg: PabloColors.assignGreen,
          bgHover: PabloColors.assignGreenHover,
          bgPressed: PabloColors.assignGreenActive,
          fg: PabloColors.textOnAccent,
          border: Colors.transparent,
        );
      case PabloButtonVariant.danger:
        return const _Variant(
          bg: PabloColors.ignoreRed,
          bgHover: PabloColors.ignoreRedHover,
          bgPressed: PabloColors.ignoreRedActive,
          fg: PabloColors.textOnAccent,
          border: Colors.transparent,
        );
    }
  }

  _SizeSpec get _s {
    switch (widget.size) {
      case PabloButtonSize.xs:
        return const _SizeSpec(
            height: 24, paddingH: PabloSpacing.base, fontSize: 11);
      case PabloButtonSize.sm:
        return const _SizeSpec(
            height: 30, paddingH: PabloSpacing.lg, fontSize: 12);
      case PabloButtonSize.md:
        return const _SizeSpec(
            height: 34, paddingH: PabloSpacing.xxl + 2, fontSize: 13);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final s = _s;
    final disabled = widget.disabled || widget.onPressed == null;
    final bg = disabled
        ? v.bg
        : _pressed
            ? v.bgPressed
            : _hover
                ? v.bgHover
                : v.bg;
    final fg = disabled ? PabloColors.textMuted : v.fg;

    Widget child = AnimatedContainer(
      duration: PabloDurations.control,
      height: s.height,
      padding: EdgeInsets.symmetric(horizontal: s.paddingH),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: PabloRadius.pillAll,
        border: widget.variant == PabloButtonVariant.secondary
            ? Border.all(color: v.border)
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            widget.expand ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (widget.icon != null) ...[
            PabloIcon(
              widget.icon!,
              size: widget.iconSize ?? s.fontSize + 1,
              color: fg,
            ),
            const SizedBox(width: PabloSpacing.sm + 1),
          ],
          Text(
            widget.label,
            style: PabloTypography.sans(
              fontSize: s.fontSize,
              fontWeight: FontWeight.w500,
              color: fg,
              height: 1.0,
            ),
          ),
        ],
      ),
    );

    if (widget.expand) {
      child = SizedBox(width: double.infinity, child: child);
    }
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: disabled ? null : widget.onPressed,
          child: child,
        ),
      ),
    );
  }
}

class _Variant {
  const _Variant({
    required this.bg,
    required this.bgHover,
    required this.bgPressed,
    required this.fg,
    required this.border,
  });
  final Color bg;
  final Color bgHover;
  final Color bgPressed;
  final Color fg;
  final Color border;
}

class _SizeSpec {
  const _SizeSpec({
    required this.height,
    required this.paddingH,
    required this.fontSize,
  });
  final double height;
  final double paddingH;
  final double fontSize;
}
