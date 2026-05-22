// Controls bar — rotate/star/add/clock + zoom slider + segmented info tabs.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
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
          final iconOnlyTabs = w < 580;
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
              GestureDetector(
                onTap: () => st.setThumbSize(
                    (st.thumbSize - 20).clamp(60, 260).toDouble()),
                child: const PabloIcon(
                  PabloIconName.zoomOut,
                  size: 14,
                  color: PabloColors.textMuted,
                ),
              ),
              const SizedBox(width: PabloSpacing.md),
              ThumbSlider(
                value: st.thumbSize,
                defaultValue: 130,
                onChanged: st.setThumbSize,
                width: ultraCompact ? 60 : 100,
              ),
              const SizedBox(width: PabloSpacing.md),
              GestureDetector(
                onTap: () => st.setThumbSize(
                    (st.thumbSize + 20).clamp(60, 260).toDouble()),
                child: const PabloIcon(
                  PabloIconName.zoomIn,
                  size: 14,
                  color: PabloColors.textMuted,
                ),
              ),
              const _MicroDivider(),
              _InfoPanelTabs(
                active: st.infoPanelTab,
                onChange: st.setInfoPanelTab,
                iconOnly: iconOnlyTabs,
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

class _InfoPanelTabs extends StatelessWidget {
  const _InfoPanelTabs({
    required this.active,
    required this.onChange,
    this.iconOnly = false,
  });
  final String? active;
  final ValueChanged<String?> onChange;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('people', 'People', PabloIconName.personFill),
      ('tags', 'Tags', PabloIconName.tagFill),
      ('info', 'Info', PabloIconName.infoFill),
    ];
    return ClipRRect(
      borderRadius: PabloRadius.pillAll,
      child: Container(
        color: PabloColors.controlsTabBackground,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 16,
                  color: PabloColors.controlsTabDivider,
                ),
              _TabChip(
                id: tabs[i].$1,
                label: tabs[i].$2,
                icon: tabs[i].$3,
                active: active == tabs[i].$1,
                iconOnly: iconOnly,
                onTap: () => onChange(active == tabs[i].$1 ? null : tabs[i].$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    required this.id,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.iconOnly = false,
  });
  final String id;
  final String label;
  final PabloIconName icon;
  final bool active;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? PabloColors.whiteAlpha(0.9)
        : _hover
            ? PabloColors.controlsTabHover
            : Colors.transparent;
    final fg = widget.active
        ? PabloColors.controlsTabActiveFg
        : PabloColors.whiteAlpha(0.85);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.hover,
          color: bg,
          padding: EdgeInsets.symmetric(
            horizontal: widget.iconOnly ? PabloSpacing.lg : PabloSpacing.xl,
            vertical: 7,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PabloIcon(widget.icon, size: 15, color: fg),
              if (!widget.iconOnly) ...[
                const SizedBox(width: PabloSpacing.sm + 1),
                Text(
                  widget.label,
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
    );
  }
}
