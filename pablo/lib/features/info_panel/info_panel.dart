// PhotoInfoPanel — the right-side Inspector (Pablo v4). Header + in-panel tab
// bar (Info / People / Tags) + content; widens into a Manage-details form.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'info_tab.dart';
import 'manage_details.dart';
import '../people/people_tab.dart';
import 'tags_tab.dart';

class PhotoInfoPanel extends StatefulWidget {
  const PhotoInfoPanel({
    required this.photo,
    required this.activeTab,
    required this.onClose,
    required this.onTabChange,
    super.key,
  });

  final Photo? photo;
  final String activeTab; // 'people' | 'tags' | 'info'
  final VoidCallback onClose;
  final ValueChanged<String> onTabChange;

  @override
  State<PhotoInfoPanel> createState() => _PhotoInfoPanelState();
}

class _PhotoInfoPanelState extends State<PhotoInfoPanel> {
  bool _manage = false;

  @override
  void didUpdateWidget(covariant PhotoInfoPanel old) {
    super.didUpdateWidget(old);
    // Leaving the photo (or closing) drops manage mode.
    if (old.photo?.id != widget.photo?.id) _manage = false;
  }

  static const _tabs = [
    ('info', 'Info'),
    ('people', 'People'),
    ('tags', 'Tags'),
  ];

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final tab = widget.activeTab;
    return AnimatedContainer(
      duration: PabloDurations.base,
      curve: PabloEasing.standard,
      width: _manage ? 480 : PabloSizing.railInspector,
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(left: BorderSide(color: PabloColors.borderSubtle)),
        boxShadow: PabloShadows.infoPanel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(PabloSpacing.xl + 2,
                PabloSpacing.lg, PabloSpacing.xl + 2, PabloSpacing.base),
            child: Row(
              children: [
                if (_manage) ...[
                  _HeaderIconButton(
                    icon: PabloIconName.arrowLeft,
                    tooltip: 'Back',
                    onTap: () => setState(() => _manage = false),
                    color: PabloColors.textSecondary,
                  ),
                  const SizedBox(width: PabloSpacing.md),
                ],
                Expanded(
                  child: Text(
                    _manage ? 'Manage Details' : 'Inspector',
                    style: PabloTypography.serif(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _HeaderIconButton(
                  icon: PabloIconName.close,
                  tooltip: 'Close',
                  onTap: widget.onClose,
                  color: PabloColors.textMuted,
                ),
              ],
            ),
          ),

          // Tab bar (hidden in manage mode)
          if (!_manage)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: PabloSpacing.xl + 2),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: PabloColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  for (final t in _tabs)
                    _InspectorTab(
                      label: t.$2,
                      active: tab == t.$1,
                      onTap: () => widget.onTabChange(t.$1),
                    ),
                ],
              ),
            ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(PabloSpacing.xl + 2,
                  PabloSpacing.sm, PabloSpacing.xl + 2, PabloSpacing.xxxxl),
              child: photo == null
                  ? _NoPhoto(noun: tab)
                  : _manage
                      ? ManageDetails(
                          photo: photo,
                          onSave: () => setState(() => _manage = false),
                          onCancel: () => setState(() => _manage = false),
                        )
                      : switch (tab) {
                          'people' => PeopleTab(photoId: photo.id),
                          'tags' => TagsTab(photoId: photo.id),
                          _ => InfoTab(
                              photo: photo,
                              onManage: () => setState(() => _manage = true),
                              onGoToTab: widget.onTabChange,
                            ),
                        },
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorTab extends StatefulWidget {
  const _InspectorTab({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  State<_InspectorTab> createState() => _InspectorTabState();
}

class _InspectorTabState extends State<_InspectorTab> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? PabloColors.accentPrimary
        : _hover
            ? PabloColors.textPrimary
            : PabloColors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    0, PabloSpacing.base, 0, PabloSpacing.lg),
                child: Text(
                  widget.label,
                  style: PabloTypography.sans(
                    fontSize: 13,
                    fontWeight:
                        widget.active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              if (widget.active)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 2,
                    decoration: const BoxDecoration(
                      color: PabloColors.accentPrimary,
                      borderRadius: PabloRadius.xsAll,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });
  final PabloIconName icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? PabloColors.backgroundHover : Colors.transparent,
              borderRadius: PabloRadius.smAll,
            ),
            child: PabloIcon(widget.icon, size: 15, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto({required this.noun});
  final String noun;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Opacity(
              opacity: 0.3,
              child: const PabloIcon(
                PabloIconName.camera,
                size: 32,
                color: PabloColors.textMuted,
              ),
            ),
            const SizedBox(height: PabloSpacing.xl),
            Text(
              'Click a photo\nto inspect its $noun',
              textAlign: TextAlign.center,
              style: PabloTypography.sans(
                fontSize: 12,
                color: PabloColors.textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
