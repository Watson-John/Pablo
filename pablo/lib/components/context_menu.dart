// Popup context menu (used by right-click on photos, sidebar +, etc.).
// Built on Overlay so it can appear above any content.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'pablo_icon.dart';

class ContextMenuItem {
  ContextMenuItem({
    required this.label,
    this.icon,
    this.iconCharacter,
    this.shortcut,
    this.onPressed,
    this.destructive = false,
    this.checked,
  });

  ContextMenuItem.separator()
      : label = '',
        icon = null,
        iconCharacter = null,
        shortcut = null,
        onPressed = null,
        destructive = false,
        checked = null,
        isSeparator = true;

  bool isSeparator = false;
  final String label;
  final PabloIconName? icon;
  final String? iconCharacter;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool? checked;
}

class PabloContextMenu extends StatelessWidget {
  const PabloContextMenu({required this.items, super.key});

  final List<ContextMenuItem> items;

  static OverlayEntry show(
    BuildContext context, {
    required Offset position,
    required List<ContextMenuItem> items,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) {
      return _MenuOverlay(
        position: position,
        items: items,
        onDismiss: () => entry.remove(),
      );
    });
    Overlay.of(context).insert(entry);
    return entry;
  }

  @override
  Widget build(BuildContext context) {
    return _MenuSurface(items: items);
  }
}

class _MenuOverlay extends StatelessWidget {
  const _MenuOverlay({
    required this.position,
    required this.items,
    required this.onDismiss,
  });
  final Offset position;
  final List<ContextMenuItem> items;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const w = 220.0;
    final h = items.length * 30.0;
    final x = (position.dx + w > size.width) ? size.width - w - 8 : position.dx;
    final y = (position.dy + h > size.height) ? size.height - h - 8 : position.dy;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
          ),
        ),
        Positioned(
          left: x,
          top: y,
          child: _MenuSurface(items: items, onDismiss: onDismiss),
        ),
      ],
    );
  }
}

class _MenuSurface extends StatelessWidget {
  const _MenuSurface({required this.items, this.onDismiss});
  final List<ContextMenuItem> items;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.all(PabloSpacing.sm),
        decoration: BoxDecoration(
          color: PabloColors.backgroundSurface,
          border: Border.all(color: PabloColors.borderSubtle),
          borderRadius: PabloRadius.lgAll,
          boxShadow: PabloShadows.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.map((it) {
            if (it.isSeparator) {
              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: PabloSpacing.base,
                  vertical: PabloSpacing.sm,
                ),
                height: 1,
                color: PabloColors.borderSubtle,
              );
            }
            return _MenuRow(item: it, onDismiss: onDismiss);
          }).toList(),
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, this.onDismiss});
  final ContextMenuItem item;
  final VoidCallback? onDismiss;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.item.destructive
        ? PabloColors.error
        : PabloColors.textPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.item.onPressed?.call();
          widget.onDismiss?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xl,
            vertical: PabloSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _hover ? PabloColors.backgroundHover : Colors.transparent,
            borderRadius: PabloRadius.smAll,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Center(
                  child: widget.item.icon != null
                      ? PabloIcon(widget.item.icon!, size: 14, color: color)
                      : widget.item.iconCharacter != null
                          ? Text(
                              widget.item.iconCharacter!,
                              style: PabloTypography.sans(
                                fontSize: 14,
                                color: color,
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: PabloSpacing.lg),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: PabloTypography.sans(
                    fontSize: 13,
                    color: color,
                    fontWeight: widget.item.destructive
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.item.checked == true)
                const Text(
                  '✓',
                  style: TextStyle(
                    color: PabloColors.accentPrimary,
                    fontSize: 12,
                  ),
                ),
              if (widget.item.shortcut != null) ...[
                const SizedBox(width: PabloSpacing.xxl),
                Text(
                  widget.item.shortcut!,
                  style: PabloTypography.mono(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
