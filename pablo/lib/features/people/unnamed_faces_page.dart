// UnnamedFacesPage — 3-tab flow for assigning / ignoring unclustered faces.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_scope.dart';
import '../../components/autocomplete_input.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'face_naming.dart';
import 'face_palette.dart';
import 'face_thumb.dart';
import 'people_controller.dart';
import 'people_scope.dart';

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

  // Unclustered (solo) faces would come from the pipeline; there is no
  // separate solo read-back yet, so this stays empty rather than synthesized.
  final List<UnnamedFace> _solos = const [];

  @override
  void dispose() {
    _bulkCtl.dispose();
    super.dispose();
  }

  Future<void> _assign(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final pc = PeopleScope.read(context);
    // Existing person → assign immediately; a brand-new name confirms first.
    if (!isExistingPerson(pc, trimmed) &&
        !await confirmNewPerson(context, trimmed)) {
      return;
    }
    // Live: promote the cluster into a named person (confirm-all + merge). The
    // clusterUpdated re-query drops it from listClusters; the overlay below
    // shows it as "assigned" until then.
    if (pc.isLive) {
      final clusterId = PeopleController.nativeClusterId(id);
      if (clusterId != null) pc.assignCluster(clusterId, trimmed);
    }
    if (!mounted) return;
    setState(() {
      _names[id] = trimmed;
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
    final pc = PeopleScope.of(context);
    final clusters = pc.unnamedFaces();
    // Live clusters come through listClusters; there's no separate "solo"
    // (unclustered) concept, so that tab is mock-only.
    final solos = pc.isLive ? const <UnnamedFace>[] : _solos;
    FaceRow? coverOf(UnnamedFace f) {
      final cid = PeopleController.nativeClusterId(f.id);
      return cid == null ? null : pc.coverFace(cid);
    }

    final activeClusters = clusters
        .where((f) => !_ignored.contains(f.id) && !_assigned.contains(f.id))
        .toList();
    final assignedClusters =
        clusters.where((f) => _assigned.contains(f.id)).toList();
    final ignoredClusters =
        clusters.where((f) => _ignored.contains(f.id)).toList();
    final activeSolos =
        solos.where((f) => !_ignoredSolo.contains(f.id)).toList();
    final ignoredSolos =
        solos.where((f) => _ignoredSolo.contains(f.id)).toList();
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
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: _TabButton(
                      tab: tabs[i],
                      active: _tab == tabs[i].id,
                      onTap: () => setState(() => _tab = tabs[i].id),
                    ),
                  ),
              ],
            ),
          ),

          // Content — each tab is its own lazy CustomScrollView (cards, and the
          // native texture slots their cover crops hold, build on demand).
          Expanded(
            child: switch (_tab) {
              _UnnamedTab.groups => _GroupsTab(
                  active: activeClusters,
                  done: assignedClusters,
                  names: _names,
                  coverOf: coverOf,
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
  });
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          decoration: BoxDecoration(
            // Conventional underline tab: 2px accent bar under the active tab.
            border: Border(
              bottom: BorderSide(
                color: active ? PabloColors.accentPrimary : Colors.transparent,
                width: 2,
              ),
            ),
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
                      ? PabloColors.accentPrimary
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
                        ? PabloColors.accentBackground
                        : PabloColors.backgroundSurfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${tab.count}',
                    style: PabloTypography.sans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? PabloColors.accentPrimary
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
    required this.coverOf,
    required this.onAssign,
    required this.onIgnore,
  });
  final List<UnnamedFace> active;
  final List<UnnamedFace> done;
  final Map<String, String> names;
  final FaceRow? Function(UnnamedFace) coverOf;
  final void Function(String, String) onAssign;
  final ValueChanged<String> onIgnore;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Grouped by similarity. Type a name below each face — suggestions appear as you type. Click ✕ to ignore.',
              style: PabloTypography.sans(
                fontSize: 12,
                color: PabloColors.textSecondary,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              PabloSpacing.xxl, 0, PabloSpacing.xxl, PabloSpacing.xxl),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 126,
              mainAxisExtent: 152,
              crossAxisSpacing: PabloSpacing.base,
              mainAxisSpacing: PabloSpacing.base,
            ),
            itemCount: active.length + done.length,
            itemBuilder: (context, i) {
              final inActive = i < active.length;
              final f = inActive ? active[i] : done[i - active.length];
              return Align(
                alignment: Alignment.topLeft,
                child: _GroupCard(
                  key: ValueKey(f.id),
                  face: f,
                  done: !inActive,
                  name: names[f.id],
                  cover: coverOf(f),
                  onAssign: inActive ? (n) => onAssign(f.id, n) : (_) {},
                  onIgnore: inActive ? () => onIgnore(f.id) : () {},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({
    super.key,
    required this.face,
    required this.done,
    required this.name,
    required this.cover,
    required this.onAssign,
    required this.onIgnore,
  });
  final UnnamedFace face;
  final bool done;
  final String? name;
  final FaceRow? cover;
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

  /// Open the source photo this face was cropped from in the lightbox. The
  /// ingestion run registered each scanned asset's path, so we resolve the
  /// cover face's assetId → path → Photo and hand it to the lightbox.
  void _openFullImage() {
    final cover = widget.cover;
    if (cover == null) return;
    final path = PeopleScope.read(context).assetPath(cover.assetId);
    if (path == null || photoById(path) == null) return;
    AppScope.of(context).openLightbox(path);
  }

  @override
  Widget build(BuildContext context) {
    final tile = faceTileGradient(widget.face.hue);
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
          // Hug the content (image + name field) instead of stretching to the
          // fixed grid-cell height, which left a gap under the name field.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  if (widget.cover != null)
                    Positioned.fill(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _openFullImage,
                          child: FaceThumb(
                            face: widget.cover!,
                            size: 110,
                            borderRadius: BorderRadius.zero,
                            hue: widget.face.hue,
                            // The card already has an inline name field + click
                            // to open, so don't stack a hover "Name…" on top.
                            showHoverLabel: false,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Container(decoration: BoxDecoration(gradient: tile)),
                    const Center(
                      child: PabloIcon(
                        PabloIconName.person,
                        size: 28,
                        color: PabloColors.tileGlyph,
                      ),
                    ),
                  ],
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
                            color: PabloColors.ignoreRed.withValues(alpha: 0.9),
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
              // Borderless field connected to the image with a single divider,
              // so the card has one outer outline instead of nested boxes.
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: PabloColors.borderSubtle),
                  ),
                ),
                child: AutocompleteInput(
                  controller: _ctl,
                  placeholder: 'Name…',
                  bordered: false,
                  suggestions: [
                    for (final p in PeopleScope.read(context).people()) p.name
                  ],
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
    final toolbar = Container(
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
              fontWeight:
                  selectedIds.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
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
            onPressed: bulkCtl.text.trim().isNotEmpty && selectedIds.isNotEmpty
                ? onBulkAssign
                : null,
            disabled: bulkCtl.text.trim().isEmpty || selectedIds.isEmpty,
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
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(child: toolbar),
        ),
        if (active.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(PabloSpacing.xxxxl),
              child: Center(
                child: Text(
                  'All unclustered faces have been assigned or ignored.',
                  style: PabloTypography.sans(
                    fontSize: 13,
                    color: PabloColors.textMuted,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xxl, 0, PabloSpacing.xxl, PabloSpacing.xxl),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 88,
                mainAxisExtent: 76,
                crossAxisSpacing: PabloSpacing.md,
                mainAxisSpacing: PabloSpacing.md,
              ),
              itemCount: active.length,
              itemBuilder: (context, i) {
                final f = active[i];
                return _SoloCard(
                  key: ValueKey(f.id),
                  face: f,
                  selected: selectedIds.contains(f.id),
                  onTap: (multi) => onToggleSelect(f.id, multi),
                  onIgnore: () => onIgnoreSolo(f.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SoloCard extends StatelessWidget {
  const _SoloCard({
    super.key,
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
    final tile = faceTileGradient(face.hue, hueShift: 15, satBottom: 0.42);
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
    final header = Row(
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
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(child: header),
        ),
        if (total == 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(PabloSpacing.xxxxl),
              child: Center(
                child: Text(
                  'No ignored faces yet.',
                  style: PabloTypography.sans(
                    fontSize: 13,
                    color: PabloColors.textMuted,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xxl, 0, PabloSpacing.xxl, PabloSpacing.xxl),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisExtent: 116,
                crossAxisSpacing: PabloSpacing.base,
                mainAxisSpacing: PabloSpacing.base,
              ),
              itemCount: total,
              itemBuilder: (context, i) {
                final inClusters = i < ignoredClusters.length;
                final f = inClusters
                    ? ignoredClusters[i]
                    : ignoredSolos[i - ignoredClusters.length];
                return Align(
                  alignment: Alignment.topLeft,
                  child: _IgnoredCard(
                    key: ValueKey(f.id),
                    face: f,
                    onRestore: () => inClusters
                        ? onRestoreCluster(f.id)
                        : onRestoreSolo(f.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _IgnoredCard extends StatelessWidget {
  const _IgnoredCard({super.key, required this.face, required this.onRestore});
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
                  gradient: faceTileGradient(face.hue,
                      satTop: 0.18, hueShift: 15, satBottom: 0.22),
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
