// Sidebar — Map nav + People + Albums + Folders + Timeline + storage footer.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/nav_item.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/section_header.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'album_row.dart';
import 'folder_group.dart';
import 'folder_leaf.dart';
import 'person_row.dart';
import 'timeline_tree_node.dart';
import 'unnamed_faces_row.dart';

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
                  // Map
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 0,
                      right: 0,
                      top: PabloSpacing.md,
                      bottom: PabloSpacing.sm,
                    ),
                    child: NavItem(
                      icon: PabloIconName.map,
                      label: 'Map',
                      count: '570',
                      active: st.activeSection == NavSection.map,
                      indent: PabloSpacing.xl,
                      onPressed: () => st.setSelectedItem('map', NavSection.map),
                    ),
                  ),
                  Container(
                    height: 1,
                    color: PabloColors.borderSubtle,
                    margin: const EdgeInsets.only(bottom: PabloSpacing.sm),
                  ),

                  // People
                  CollapsibleSection(
                    label: 'People',
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

          // Storage footer
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xxl,
              vertical: PabloSpacing.lg,
            ),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PabloColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Text(
                  '1,247 photos',
                  style: PabloTypography.sans(
                    fontSize: 11,
                    color: PabloColors.textMuted,
                  ),
                ),
                const SizedBox(width: PabloSpacing.md),
                Text(
                  '·',
                  style: PabloTypography.sans(
                    fontSize: 11,
                    color: PabloColors.borderSubtle,
                  ),
                ),
                const SizedBox(width: PabloSpacing.md),
                Text(
                  '14.2 GB',
                  style: PabloTypography.sans(
                    fontSize: 11,
                    color: PabloColors.textMuted,
                  ),
                ),
              ],
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
