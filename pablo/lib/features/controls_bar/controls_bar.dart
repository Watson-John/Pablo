// Controls bar — rotate/star/add/clock + zoom slider + segmented info tabs.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/pablo_slider.dart';
import '../../theme/tokens.dart';

class ControlsBar extends StatelessWidget {
  const ControlsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);

    Widget elevatedIcon(PabloIconName icon, String tip, Color tint) =>
        PabloIconButton(
          icon: icon,
          size: 28,
          iconSize: 14,
          tooltip: tip,
          color: tint,
          elevated: true,
        );

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: const Border(top: BorderSide(color: PabloColors.borderSubtle)),
        boxShadow: PabloShadows.controlsBar,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final ultraCompact = w < 460;
          return Row(
            children: [
              elevatedIcon(
                PabloIconName.rotateLeft,
                'Rotate Left',
                PabloColors.controlsIconWarm,
              ),
              const SizedBox(width: PabloSpacing.sm),
              elevatedIcon(
                PabloIconName.rotateRight,
                'Rotate Right',
                PabloColors.controlsIconWarm,
              ),
              const _MicroDivider(),
              elevatedIcon(PabloIconName.star, 'Star', PabloColors.amber),
              const SizedBox(width: PabloSpacing.sm),
              elevatedIcon(
                PabloIconName.plus,
                'Add to Album',
                PabloColors.assignGreen,
              ),
              if (!ultraCompact) ...[
                const _MicroDivider(),
                elevatedIcon(
                  PabloIconName.clock,
                  'Edit Date',
                  PabloColors.controlsTabBackground,
                ),
              ],
              const Spacer(),
              _GridModeToggle(mode: st.gridMode, onChange: st.setGridMode),
              const _MicroDivider(),
              GestureDetector(
                onTap: () => st.setThumbSize(
                    (st.thumbSize - 20).clamp(60, 512).toDouble()),
                child: const PabloIcon(
                  PabloIconName.zoomOut,
                  size: 14,
                  color: PabloColors.textMuted,
                ),
              ),
              const SizedBox(width: PabloSpacing.md),
              ThumbSlider(
                value: st.thumbSize,
                defaultValue: 200,
                min: 60,
                max: 512,
                onChanged: st.setThumbSize,
                width: ultraCompact ? 60 : 100,
              ),
              const SizedBox(width: PabloSpacing.md),
              GestureDetector(
                onTap: () => st.setThumbSize(
                    (st.thumbSize + 20).clamp(60, 512).toDouble()),
                child: const PabloIcon(
                  PabloIconName.zoomIn,
                  size: 14,
                  color: PabloColors.textMuted,
                ),
              ),
              const _MicroDivider(),
              _InspectorToggle(
                open: st.infoPanelTab != null,
                showLabel: !ultraCompact,
                // The Inspector panel owns its own Info/People/Tags tab bar, so
                // this is a plain open/close toggle; opening lands on Info.
                onTap: () =>
                    st.setInfoPanelTab(st.infoPanelTab == null ? 'info' : null),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MicroDivider extends StatelessWidget {
  const _MicroDivider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm),
        color: PabloColors.borderSubtle,
      );
}

/// Grid ⇄ Masonry layout toggle — two standalone rounded-square chips
/// (blue = active, gray = inactive), matching the toolbar mock.
class _GridModeToggle extends StatelessWidget {
  const _GridModeToggle({required this.mode, required this.onChange});
  final String mode;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarToggle(
          icon: PabloIconName.grid,
          tooltip: 'Grid',
          active: mode == GridMode.grid,
          onTap: () => onChange(GridMode.grid),
        ),
        const SizedBox(width: PabloSpacing.sm),
        _ToolbarToggle(
          icon: PabloIconName.masonry,
          tooltip: 'Masonry',
          active: mode == GridMode.masonry,
          onTap: () => onChange(GridMode.masonry),
        ),
      ],
    );
  }
}

/// Open/close toggle for the right-side Inspector panel. A single rounded chip
/// (blue when open) with an optional label — the panel owns its own tab bar.
class _InspectorToggle extends StatelessWidget {
  const _InspectorToggle({
    required this.open,
    required this.onTap,
    this.showLabel = true,
  });
  final bool open;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ToolbarToggle(
      icon: PabloIconName.panelRight,
      tooltip: 'Inspector',
      label: showLabel ? 'Inspector' : null,
      active: open,
      onTap: onTap,
    );
  }
}

/// Shared rounded-square toolbar control. Active = filled azure with white
/// content; inactive = sunken warm well with muted content. Optional [label]
/// turns the square into a pill-ish chip (used by the Inspector toggle).
class _ToolbarToggle extends StatefulWidget {
  const _ToolbarToggle({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.label,
  });
  final PabloIconName icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final String? label;

  @override
  State<_ToolbarToggle> createState() => _ToolbarToggleState();
}

class _ToolbarToggleState extends State<_ToolbarToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (widget.active) {
      bg = _hover
          ? PabloColors.selectionPrimaryHover
          : PabloColors.selectionPrimary;
    } else {
      bg = _hover ? PabloColors.borderStrong : PabloColors.backgroundSurfaceAlt;
    }
    final fg = widget.active
        ? PabloColors.textOnAccent
        : PabloColors.textSecondary;
    final hasLabel = widget.label != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: PabloDurations.hover,
            height: 28,
            padding: EdgeInsets.symmetric(
              horizontal: hasLabel ? PabloSpacing.xl : PabloSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: PabloRadius.smAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PabloIcon(widget.icon, size: 15, color: fg),
                if (hasLabel) ...[
                  const SizedBox(width: PabloSpacing.sm + 1),
                  Text(
                    widget.label!,
                    style: PabloTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
