// Sidebar — Map nav + People + Albums + Folders + Timeline + storage footer.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Album;

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/section_header.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../people/people_scope.dart';
import 'folder_group.dart';
import 'folder_leaf.dart';
import '../people/person_row.dart';
import 'timeline_tree_node.dart';
import '../people/unnamed_faces_row.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final pc = PeopleScope.of(context);
    final narrow = st.sidebarWidth < 210;

    final people = pc.people();
    final unnamedCount = pc.unnamedFaceCount();
    final peopleTotal = pc.peopleTotal();
    final lib = Library.instance;
    final folders = lib.folderTree;
    final folderCount = lib.folderSections.length;
    final timelineYears = lib.timelineYears;
    final timelineRange = timelineYears.isEmpty
        ? '—'
        : (timelineYears.first.label == timelineYears.last.label
            ? timelineYears.first.label
            : '${timelineYears.last.label}–${timelineYears.first.label}');

    return Container(
      width: st.sidebarWidth,
      decoration: BoxDecoration(
        color: PabloColors.backgroundSidebar,
        boxShadow: PabloShadows.sidebar,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: PabloSpacing.base),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: PabloSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Map (standalone nav card)
                  _MapCard(
                    active: st.activeSection == NavSection.map,
                    onTap: () => st.setSelectedItem('map', NavSection.map),
                  ),
                  Container(
                    height: 1,
                    color: PabloColors.borderSubtle,
                    margin: const EdgeInsets.fromLTRB(
                      PabloSpacing.xl,
                      PabloSpacing.sm,
                      PabloSpacing.xl,
                      PabloSpacing.md,
                    ),
                  ),

                  // People
                  CollapsibleSection(
                    label: 'People',
                    icon: PabloIconName.people,
                    iconColor: PabloColors.sectionPeople,
                    collapsedCount: '$peopleTotal',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        UnnamedFacesRow(
                          count: unnamedCount,
                          selected: st.selectedItem == 'unnamed',
                          onSelect: () =>
                              st.setSelectedItem('unnamed', NavSection.unnamed),
                        ),
                        for (final p in people)
                          PersonRow(
                            person: p,
                            narrow: narrow,
                            selected: st.selectedItem == p.id &&
                                st.activeSection == NavSection.people,
                            onSelect: () =>
                                st.setSelectedItem(p.id, NavSection.people),
                          ),
                      ],
                    ),
                  ),

                  // Albums — user-created collections from the catalog.
                  CollapsibleSection(
                    label: 'Albums',
                    icon: PabloIconName.albums,
                    iconColor: PabloColors.sectionAlbums,
                    collapsedCount: '${st.albums.length}',
                    trailing: PabloIconButton(
                      icon: PabloIconName.plus,
                      size: 20,
                      iconSize: 12,
                      tooltip: 'New Album',
                      color: PabloColors.assignGreen,
                      elevated: true,
                      onPressed: () => _newAlbum(context),
                    ),
                    child: st.albums.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(
                              PabloSpacing.xxxl,
                              PabloSpacing.sm,
                              PabloSpacing.xl,
                              PabloSpacing.sm,
                            ),
                            child: Text(
                              'No albums yet',
                              style: PabloTypography.sans(
                                fontSize: 11.5,
                                color: PabloColors.textMuted,
                              ).copyWith(fontStyle: FontStyle.italic),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final a in st.albums)
                                _AlbumRow(
                                  album: a,
                                  selected:
                                      st.selectedItem == 'album:${a.id}' &&
                                          st.activeSection == NavSection.albums,
                                  onSelect: () => st.setSelectedItem(
                                      'album:${a.id}', NavSection.albums),
                                ),
                            ],
                          ),
                  ),

                  // Folders — the real directory tree under the import root.
                  CollapsibleSection(
                    label: 'Folders',
                    icon: PabloIconName.folder,
                    iconColor: PabloColors.sectionFolders,
                    collapsedCount: '$folderCount',
                    trailing: _FolderSortToggle(
                      sort: st.folderSort,
                      onToggle: () => st.setFolderSort(
                        st.folderSort == FolderSort.tree
                            ? FolderSort.alpha
                            : FolderSort.tree,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: st.folderSort == FolderSort.tree
                          ? [
                              for (var i = 0; i < folders.length; i++)
                                FolderGroup(
                                  folder: folders[i],
                                  selectedId:
                                      st.activeSection == NavSection.folders
                                          ? st.selectedItem
                                          : null,
                                  onSelect: (id) => st.setSelectedItem(
                                      id, NavSection.folders),
                                  defaultOpen: i == 0,
                                ),
                            ]
                          : _flatAlphaLeaves(st),
                    ),
                  ),

                  // Timeline — grouped by each file's modified date.
                  CollapsibleSection(
                    label: 'Timeline',
                    icon: PabloIconName.calendar,
                    iconColor: PabloColors.sectionTimeline,
                    defaultOpen: false,
                    collapsedCount: timelineRange,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final y in timelineYears)
                          TimelineTreeNode(
                            node: y,
                            selectedId: st.activeSection == NavSection.timeline
                                ? st.selectedItem
                                : null,
                            onSelect: (id) =>
                                st.setSelectedItem(id, NavSection.timeline),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _flatAlphaLeaves(dynamic st) {
    final all = Library.instance.folderSections.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final f in all)
        FolderLeaf(
          folder: f,
          selected:
              st.activeSection == NavSection.folders && st.selectedItem == f.id,
          onSelect: () => st.setSelectedItem(f.id, NavSection.folders),
        ),
    ];
  }

  // Prompt for a name, create the album natively, reload, and select it.
  Future<void> _newAlbum(BuildContext context) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) return;
    final st = AppScope.of(context);
    final name = await _promptName(context);
    if (!context.mounted) return;
    if (name == null || name.trim().isEmpty) return;
    final id = backend.engine.createAlbum(name.trim());
    st.reloadAlbums(backend.engine);
    if (id != 0) st.setSelectedItem('album:$id', NavSection.albums);
  }

  Future<String?> _promptName(BuildContext context) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Album'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Album name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// A selectable album row in the sidebar (name + member count).
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.selected,
    required this.onSelect,
  });

  final Album album;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PabloColors.selectionBackground : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PabloSpacing.xxxl,
            PabloSpacing.sm,
            PabloSpacing.xl,
            PabloSpacing.sm,
          ),
          child: Row(
            children: [
              PabloIcon(
                PabloIconName.albums,
                size: 13,
                color: selected
                    ? PabloColors.selectionPrimary
                    : PabloColors.sectionAlbums,
              ),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  album.name.isEmpty ? 'Untitled album' : album.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? PabloColors.selectionPrimary
                        : PabloColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${album.count}',
                style: PabloTypography.mono(
                  fontSize: 10.5,
                  color: PabloColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Map nav as a standalone bordered card matching the section-header chrome
/// (non-collapsible). Icon is teal at rest, azure when the Map view is active.
class _MapCard extends StatefulWidget {
  const _MapCard({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;
  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final headerBg = widget.active
        ? PabloColors.backgroundSelected
        : _hover
            ? PabloColors.backgroundSidebarHover
            : PabloColors.backgroundSidebar;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        PabloSpacing.base,
        PabloSpacing.sm,
        PabloSpacing.base,
        PabloSpacing.md,
      ),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.mdAll,
      ),
      clipBehavior: Clip.antiAlias,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PabloDurations.hover,
            height: PabloSizing.controlMd,
            padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
            color: headerBg,
            child: Row(
              children: [
                PabloIcon(
                  PabloIconName.map,
                  size: 14,
                  filled: true, // design navMap = location_on (filled)
                  color: widget.active
                      ? PabloColors.accentActive
                      : PabloColors.sectionMap,
                ),
                const SizedBox(width: PabloSpacing.base),
                Expanded(
                  child: Text(
                    'Map',
                    style: PabloTypography.serif(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '0',
                  style: PabloTypography.mono(
                    fontSize: 10,
                    color: PabloColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderSortToggle extends StatefulWidget {
  const _FolderSortToggle({required this.sort, required this.onToggle});
  final String sort;
  final VoidCallback onToggle;
  @override
  State<_FolderSortToggle> createState() => _FolderSortToggleState();
}

class _FolderSortToggleState extends State<_FolderSortToggle> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final label = widget.sort == FolderSort.tree ? 'A→Z' : 'Tree';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: PabloDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.md,
            vertical: PabloSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: _hover
                ? PabloColors.backgroundHover
                : PabloColors.backgroundSurface,
            border: Border.all(color: PabloColors.borderSubtle),
            borderRadius: PabloRadius.smAll,
            boxShadow: PabloShadows.sm,
          ),
          child: Text(
            label,
            style: PabloTypography.sans(
              fontSize: 11,
              color: PabloColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
