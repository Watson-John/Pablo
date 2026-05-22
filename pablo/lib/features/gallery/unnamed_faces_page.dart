// UnnamedFacesPage — 3-tab flow for assigning / ignoring unclustered faces.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/autocomplete_input.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

enum _UnnamedTab { groups, unclustered, ignored }

class UnnamedFacesPage extends StatefulWidget {
  const UnnamedFacesPage({super.key});

  @override
  State<UnnamedFacesPage> createState() => _UnnamedFacesPageState();
}

class _UnnamedFacesPageState extends State<UnnamedFacesPage> {
  _UnnamedTab _tab = _UnnamedTab.groups;
  final Map<String, String> _names = {};
  final Set<String> _assigned = {};
  final Set<String> _ignored = {};
  final Set<String> _ignoredSolo = {};
  final Set<String> _selectedSolos = {};
  final TextEditingController _bulkCtl = TextEditingController();

  late final List<UnnamedFace> _solos = List.generate(22, (i) {
    final hue = (i * 37 + 180) % 360;
    return UnnamedFace(id: 'solo-$i', hue: hue, count: 1);
  });

  @override
  void dispose() {
    _bulkCtl.dispose();
    super.dispose();
  }

  void _assign(String id, String name) {
    if (name.trim().isEmpty) return;
    setState(() {
      _names[id] = name;
      _assigned.add(id);
    });
  }

  void _toggleIgnore(String id) {
    setState(() {
      if (_ignored.contains(id)) {
        _ignored.remove(id);
      } else {
        _ignored.add(id);
      }
    });
  }

  void _toggleIgnoreSolo(String id) {
    setState(() {
      if (_ignoredSolo.contains(id)) {
        _ignoredSolo.remove(id);
      } else {
        _ignoredSolo.add(id);
      }
    });
  }

  void _toggleSelectSolo(String id, bool multi) {
    setState(() {
      if (!multi) {
        if (_selectedSolos.contains(id) && _selectedSolos.length == 1) {
          _selectedSolos.clear();
        } else {
          _selectedSolos
            ..clear()
            ..add(id);
        }
      } else {
        if (_selectedSolos.contains(id)) {
          _selectedSolos.remove(id);
        } else {
          _selectedSolos.add(id);
        }
      }
    });
  }

  void _bulkAssign() {
    final name = _bulkCtl.text.trim();
    if (name.isEmpty || _selectedSolos.isEmpty) return;
    setState(() {
      for (final id in _selectedSolos) {
        _names[id] = name;
        _assigned.add(id);
      }
      _selectedSolos.clear();
      _bulkCtl.clear();
    });
  }

  void _bulkIgnore() {
    setState(() {
      _ignoredSolo.addAll(_selectedSolos);
      _selectedSolos.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeClusters = kUnnamedFaces
        .where((f) => !_ignored.contains(f.id) && !_assigned.contains(f.id))
        .toList();
    final assignedClusters =
        kUnnamedFaces.where((f) => _assigned.contains(f.id)).toList();
    final ignoredClusters =
        kUnnamedFaces.where((f) => _ignored.contains(f.id)).toList();
    final activeSolos =
        _solos.where((f) => !_ignoredSolo.contains(f.id)).toList();
    final ignoredSolos =
        _solos.where((f) => _ignoredSolo.contains(f.id)).toList();
    final totalIgnored = ignoredClusters.length + ignoredSolos.length;

    final tabs = [
      _Tab(_UnnamedTab.groups, 'Face Groups',
          activeClusters.length + assignedClusters.length),
      _Tab(_UnnamedTab.unclustered, 'Unclustered', activeSolos.length),
      _Tab(_UnnamedTab.ignored, 'Ignored', totalIgnored),
    ];

    return Container(
      color: PabloColors.backgroundSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xxl,
              vertical: PabloSpacing.lg,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unnamed Faces',
                    style: PabloTypography.serif(fontSize: 16)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(
                  children: [
                    TextSpan(
                      text: '${assignedClusters.length} assigned',
                      style: PabloTypography.sans(
                        fontSize: 12,
                        color: PabloColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' · ${activeClusters.length} groups · ${activeSolos.length} unclustered',
                      style: PabloTypography.sans(
                        fontSize: 12,
                        color: PabloColors.textMuted,
                      ),
                    ),
                  ],
                )),
              ],
            ),
          ),

          // Tab bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl,
              vertical: PabloSpacing.md,
            ),
            decoration: const BoxDecoration(
              color: PabloColors.backgroundSurfaceAlt,
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: PabloRadius.pillAll,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: PabloColors.borderSubtle),
                      borderRadius: PabloRadius.pillAll,
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          _TabButton(
                            tab: tabs[i],
                            active: _tab == tabs[i].id,
                            onTap: () => setState(() => _tab = tabs[i].id),
                            showDivider: i > 0,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(PabloSpacing.xxl),
              child: switch (_tab) {
                _UnnamedTab.groups => _GroupsTab(
                    active: activeClusters,
                    done: assignedClusters,
                    names: _names,
                    onAssign: _assign,
                    onIgnore: _toggleIgnore,
                  ),
                _UnnamedTab.unclustered => _UnclusteredTab(
                    active: activeSolos,
                    selectedIds: _selectedSolos,
                    bulkCtl: _bulkCtl,
                    onToggleSelect: _toggleSelectSolo,
                    onBulkAssign: _bulkAssign,
                    onBulkIgnore: _bulkIgnore,
                    onIgnoreSolo: _toggleIgnoreSolo,
                  ),
                _UnnamedTab.ignored => _IgnoredTab(
                    ignoredClusters: ignoredClusters,
                    ignoredSolos: ignoredSolos,
                    onRestoreCluster: _toggleIgnore,
                    onRestoreSolo: _toggleIgnoreSolo,
                    onRestoreAll: () {
                      setState(() {
                        _ignored.clear();
                        _ignoredSolo.clear();
                      });
                    },
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab(this.id, this.label, this.count);
  final _UnnamedTab id;
  final String label;
  final int count;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.showDivider,
  });
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxl - 2,
            vertical: PabloSpacing.md,
          ),
          decoration: BoxDecoration(
            color: active ? PabloColors.accentPrimary : Colors.transparent,
            border: showDivider
                ? const Border(
                    left: BorderSide(color: PabloColors.borderSubtle),
                  )
                : null,
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
                      ? PabloColors.textOnAccent
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
                        ? Colors.white.withValues(alpha: 0.3)
                        : PabloColors.backgroundHover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${tab.count}',
                    style: PabloTypography.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? PabloColors.textOnAccent
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

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({
    required this.active,
    required this.done,
    required this.names,
    required this.onAssign,
    required this.onIgnore,
  });
  final List<UnnamedFace> active;
  final List<UnnamedFace> done;
  final Map<String, String> names;
  final void Function(String, String) onAssign;
  final ValueChanged<String> onIgnore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grouped by similarity. Type a name below each face — suggestions appear as you type. Click ✕ to ignore.',
          style: PabloTypography.sans(
            fontSize: 12,
            color: PabloColors.textSecondary,
          ),
        ),
        const SizedBox(height: PabloSpacing.xl),
        Wrap(
          spacing: PabloSpacing.base,
          runSpacing: PabloSpacing.base,
          children: [
            ...active.map((f) => _GroupCard(
                  face: f,
                  done: false,
                  name: names[f.id],
                  onAssign: (n) => onAssign(f.id, n),
                  onIgnore: () => onIgnore(f.id),
                )),
            ...done.map((f) => _GroupCard(
                  face: f,
                  done: true,
                  name: names[f.id],
                  onAssign: (_) {},
                  onIgnore: () {},
                )),
          ],
        ),
      ],
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    required this.face,
    required this.done,
    required this.name,
    required this.onAssign,
    required this.onIgnore,
  });
  final UnnamedFace face;
  final bool done;
  final String? name;
  final ValueChanged<String> onAssign;
  final VoidCallback onIgnore;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.name ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, widget.face.hue.toDouble(), 0.32, 0.72).toColor(),
        HSLColor.fromAHSL(1, (widget.face.hue + 20).toDouble(), 0.44, 0.56)
            .toColor(),
      ],
    );
    return SizedBox(
      width: 110,
      child: Container(
        decoration: BoxDecoration(
          color: widget.done
              ? PabloColors.successBackground
              : PabloColors.backgroundSurface,
          border: Border.all(
            color: widget.done
                ? PabloColors.successBorder
                : PabloColors.borderSubtle,
          ),
          borderRadius: PabloRadius.lgAll,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Container(decoration: BoxDecoration(gradient: tile)),
                  const Center(
                    child: PabloIcon(
                      PabloIconName.person,
                      size: 28,
                      color: PabloColors.tileGlyph,
                    ),
                  ),
                  if (widget.done)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PabloSpacing.md,
                          vertical: 3,
                        ),
                        color: PabloColors.success,
                        child: Text(
                          widget.name ?? '',
                          textAlign: TextAlign.center,
                          style: PabloTypography.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: PabloColors.textOnAccent,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: widget.onIgnore,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: PabloColors.ignoreRed
                                .withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '✕',
                            style: TextStyle(
                              color: PabloColors.textOnAccent,
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.done)
              Padding(
                padding: const EdgeInsets.all(2),
                child: AutocompleteInput(
                  controller: _ctl,
                  placeholder: 'Name…',
                  onSubmit: (v) => widget.onAssign(v),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnclusteredTab extends StatelessWidget {
  const _UnclusteredTab({
    required this.active,
    required this.selectedIds,
    required this.bulkCtl,
    required this.onToggleSelect,
    required this.onBulkAssign,
    required this.onBulkIgnore,
    required this.onIgnoreSolo,
  });
  final List<UnnamedFace> active;
  final Set<String> selectedIds;
  final TextEditingController bulkCtl;
  final void Function(String, bool) onToggleSelect;
  final VoidCallback onBulkAssign;
  final VoidCallback onBulkIgnore;
  final ValueChanged<String> onIgnoreSolo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.lg,
            vertical: PabloSpacing.base,
          ),
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurfaceAlt,
            border: Border.all(color: PabloColors.borderSubtle),
            borderRadius: PabloRadius.lgAll,
          ),
          child: Row(
            children: [
              Text(
                selectedIds.isNotEmpty
                    ? '${selectedIds.length} selected'
                    : 'Click to select · Ctrl+click multi',
                style: PabloTypography.sans(
                  fontSize: 12,
                  fontWeight: selectedIds.isNotEmpty
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: selectedIds.isNotEmpty
                      ? PabloColors.accentPrimary
                      : PabloColors.textMuted,
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: AutocompleteInput(
                  controller: bulkCtl,
                  placeholder: 'Assign name…',
                  onSubmit: (_) => onBulkAssign(),
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              PabloButton(
                label: '✓ Assign',
                variant: PabloButtonVariant.success,
                size: PabloButtonSize.xs,
                onPressed:
                    bulkCtl.text.trim().isNotEmpty && selectedIds.isNotEmpty
                        ? onBulkAssign
                        : null,
                disabled:
                    bulkCtl.text.trim().isEmpty || selectedIds.isEmpty,
              ),
              const SizedBox(width: PabloSpacing.sm),
              PabloButton(
                label: 'Ignore',
                variant: PabloButtonVariant.danger,
                size: PabloButtonSize.xs,
                onPressed: selectedIds.isNotEmpty ? onBulkIgnore : null,
                disabled: selectedIds.isEmpty,
              ),
            ],
          ),
        ),
        const SizedBox(height: PabloSpacing.xl),
        if (active.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'All unclustered faces have been assigned or ignored.',
                style: PabloTypography.sans(
                  fontSize: 13,
                  color: PabloColors.textMuted,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          )
        else
          Wrap(
            spacing: PabloSpacing.md,
            runSpacing: PabloSpacing.md,
            children: active.map((f) {
              final sel = selectedIds.contains(f.id);
              return _SoloCard(
                face: f,
                selected: sel,
                onTap: (multi) => onToggleSelect(f.id, multi),
                onIgnore: () => onIgnoreSolo(f.id),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _SoloCard extends StatelessWidget {
  const _SoloCard({
    required this.face,
    required this.selected,
    required this.onTap,
    required this.onIgnore,
  });
  final UnnamedFace face;
  final bool selected;
  final void Function(bool multi) onTap;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tile = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, face.hue.toDouble(), 0.32, 0.72).toColor(),
        HSLColor.fromAHSL(1, (face.hue + 15).toDouble(), 0.42, 0.56).toColor(),
      ],
    );
    return SizedBox(
      width: 76,
      height: 76,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Toggle multi via shift/ctrl modifiers — for simplicity treat any
            // tap as the basic select; user can still ctrl/cmd in keyboard apps.
            onTap(HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isShiftPressed);
          },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: tile,
                  borderRadius: PabloRadius.lgAll,
                  border: Border.all(
                    color: selected
                        ? PabloColors.accentPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: PabloIcon(
                    PabloIconName.person,
                    size: 22,
                    color: PabloColors.tileGlyph,
                  ),
                ),
              ),
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: onIgnore,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PabloColors.ignoreRed.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '✕',
                      style: TextStyle(
                        color: PabloColors.textOnAccent,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

class _IgnoredTab extends StatelessWidget {
  const _IgnoredTab({
    required this.ignoredClusters,
    required this.ignoredSolos,
    required this.onRestoreCluster,
    required this.onRestoreSolo,
    required this.onRestoreAll,
  });
  final List<UnnamedFace> ignoredClusters;
  final List<UnnamedFace> ignoredSolos;
  final ValueChanged<String> onRestoreCluster;
  final ValueChanged<String> onRestoreSolo;
  final VoidCallback onRestoreAll;

  @override
  Widget build(BuildContext context) {
    final total = ignoredClusters.length + ignoredSolos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ignored faces are excluded from your library.',
                style: PabloTypography.sans(
                  fontSize: 12,
                  color: PabloColors.textSecondary,
                ),
              ),
            ),
            if (total > 0)
              PabloButton(
                label: 'Restore All',
                size: PabloButtonSize.xs,
                onPressed: onRestoreAll,
              ),
          ],
        ),
        const SizedBox(height: PabloSpacing.xl),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                'No ignored faces yet.',
                style: PabloTypography.sans(
                  fontSize: 13,
                  color: PabloColors.textMuted,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          )
        else
          Wrap(
            spacing: PabloSpacing.base,
            runSpacing: PabloSpacing.base,
            children: [
              ...ignoredClusters.map((f) => _IgnoredCard(
                    face: f,
                    onRestore: () => onRestoreCluster(f.id),
                  )),
              ...ignoredSolos.map((f) => _IgnoredCard(
                    face: f,
                    onRestore: () => onRestoreSolo(f.id),
                  )),
            ],
          ),
      ],
    );
  }
}

class _IgnoredCard extends StatelessWidget {
  const _IgnoredCard({required this.face, required this.onRestore});
  final UnnamedFace face;
  final VoidCallback onRestore;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Opacity(
        opacity: 0.4,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      HSLColor.fromAHSL(1, face.hue.toDouble(), 0.18, 0.72)
                          .toColor(),
                      HSLColor.fromAHSL(1, (face.hue + 15).toDouble(), 0.22, 0.56)
                          .toColor(),
                    ],
                  ),
                  borderRadius: PabloRadius.lgAll,
                  border: Border.all(color: PabloColors.borderSubtle),
                ),
                child: const Center(
                  child: PabloIcon(
                    PabloIconName.person,
                    size: 24,
                    color: PabloColors.tileGlyphFaded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            GestureDetector(
              onTap: onRestore,
              child: Text(
                'Restore',
                style: PabloTypography.sans(
                  fontSize: 11,
                  color: PabloColors.accentPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
