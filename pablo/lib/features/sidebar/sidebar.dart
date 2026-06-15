// Sidebar — Map nav + People + Albums + Folders + Timeline + storage footer.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/section_header.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'album_row.dart';
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
    final narrow = st.sidebarWidth < 210;

    final peopleTotal =
        kPeople.fold<int>(0, (s, p) => s + p.count) + 247;
    final folderCount =
        kFolders.fold<int>(0, (s, f) => s + (f.children.isNotEmpty ? f.children.length : 1));

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
                          count: 247,
                          selected: st.selectedItem == 'unnamed',
                          onSelect: () =>
                              st.setSelectedItem('unnamed', NavSection.unnamed),
                        ),
                        for (final p in kPeople)
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

                  // Albums
                  CollapsibleSection(
                    label: 'Albums',
                    icon: PabloIconName.albums,
                    iconColor: PabloColors.sectionAlbums,
                    collapsedCount: '${kAlbums.length}',
                    trailing: PabloIconButton(
                      icon: PabloIconName.plus,
                      size: 20,
                      iconSize: 12,
                      tooltip: 'New Album',
                      color: PabloColors.assignGreen,
                      elevated: true,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final a in kAlbums)
                          AlbumRow(
                            album: a,
                            selected: st.selectedItem == a.id &&
                                st.activeSection == NavSection.albums,
                            onSelect: () =>
                                st.setSelectedItem(a.id, NavSection.albums),
                          ),
                      ],
                    ),
                  ),

                  // Folders
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
                              for (var i = 0; i < kFolders.length; i++)
                                FolderGroup(
                                  folder: kFolders[i],
                                  selectedId:
                                      st.activeSection == NavSection.folders
                                          ? st.selectedItem
                                          : null,
                                  onSelect: (id) =>
                                      st.setSelectedItem(id, NavSection.folders),
                                  defaultOpen: i == 0,
                                ),
                            ]
                          : _flatAlphaLeaves(st),
                    ),
                  ),

                  // Timeline
                  CollapsibleSection(
                    label: 'Timeline',
                    icon: PabloIconName.calendar,
                    iconColor: PabloColors.sectionTimeline,
                    defaultOpen: false,
                    collapsedCount: '2022–2024',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final y in kTimelineYears)
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
    final all = <FolderNode>[];
    void collect(List<FolderNode> list) {
      for (final f in list) {
        if (f.children.isNotEmpty) {
          collect(f.children);
        } else {
          all.add(f);
        }
      }
    }
    collect(kFolders);
    all.sort((a, b) => a.name.compareTo(b.name));
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
                  '570',
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
            color: _hover ? PabloColors.backgroundHover : PabloColors.backgroundSurface,
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
