// Sidebar — Map nav + People + Albums + Folders + Timeline + storage footer.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Album;

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../components/context_menu.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/section_header.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../../utils/reveal_in_file_manager.dart';
import '../gallery/native_asset_texture.dart';
import '../organize/reorganize_controller.dart';
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
    final backend = NativeBackendScope.maybeOf(context);
    final hiddenDirs = backend?.engine.hiddenFolders() ?? const <String>[];
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

                  // Smart collections — seeded virtual views over the catalog.
                  CollapsibleSection(
                    label: 'Collections',
                    icon: PabloIconName.library,
                    iconColor: PabloColors.sectionMap,
                    collapsedCount: '${photosFor('smart:all').length}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SmartRow(
                          label: 'All Photos',
                          icon: PabloIconName.grid,
                          iconColor: PabloColors.sectionFolders,
                          count: photosFor('smart:all').length,
                          selected: st.activeSection == NavSection.smart &&
                              st.selectedItem == 'smart:all',
                          onSelect: () => st.setSelectedItem(
                              'smart:all', NavSection.smart),
                        ),
                        _SmartRow(
                          label: 'Recently Added',
                          icon: PabloIconName.clock,
                          iconColor: PabloColors.sectionTimeline,
                          count: photosFor('smart:recent').length,
                          selected: st.activeSection == NavSection.smart &&
                              st.selectedItem == 'smart:recent',
                          onSelect: () => st.setSelectedItem(
                              'smart:recent', NavSection.smart),
                        ),
                        _SmartRow(
                          label: 'Starred',
                          icon: PabloIconName.starFill,
                          iconColor: PabloColors.amber,
                          count: photosFor('smart:starred').length,
                          selected: st.activeSection == NavSection.smart &&
                              st.selectedItem == 'smart:starred',
                          onSelect: () => st.setSelectedItem(
                              'smart:starred', NavSection.smart),
                        ),
                      ],
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
                                  leading: _albumLeading(context, a),
                                  selected:
                                      st.selectedItem == 'album:${a.id}' &&
                                          st.activeSection == NavSection.albums,
                                  onSelect: () => st.setSelectedItem(
                                      'album:${a.id}', NavSection.albums),
                                  onContextMenu: (pos) =>
                                      _albumContextMenu(context, a, pos),
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
                                  onDropPaths: (destDir, paths) =>
                                      reorganizeMove(context, st, paths, destDir),
                                  onContextMenu: (id, pos) =>
                                      _folderContextMenu(context, id, pos),
                                ),
                            ]
                          : _flatAlphaLeaves(context, st),
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

                  // Hidden — folders the user has hidden, surfaced here so they
                  // can be found and restored. Omitted entirely when empty.
                  if (hiddenDirs.isNotEmpty)
                    CollapsibleSection(
                      label: 'Hidden',
                      icon: PabloIconName.folder,
                      iconColor: PabloColors.textMuted,
                      defaultOpen: false,
                      collapsedCount: '${hiddenDirs.length}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final path in hiddenDirs)
                            _HiddenFolderRow(
                              path: path,
                              onUnhide: () {
                                backend!.engine.setFolderHidden(path, false);
                                hydrateHidden(
                                    backend.engine.hiddenAssets().toSet());
                                st.libraryChanged();
                              },
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

  List<Widget> _flatAlphaLeaves(BuildContext context, PabloAppState st) {
    final all = Library.instance.folderSections.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final f in all)
        FolderLeaf(
          folder: f,
          selected:
              st.activeSection == NavSection.folders && st.selectedItem == f.id,
          onSelect: () => st.setSelectedItem(f.id, NavSection.folders),
          onDropPaths: (paths) => reorganizeMove(context, st, paths, f.id),
          onContextMenu: (pos) => _folderContextMenu(context, f.id, pos),
        ),
    ];
  }

  // Right-click a folder. Filesystem actions (Reveal) work with or without
  // the native backend; Hide/Show needs it (the rule persists in the catalog)
  // and is simply omitted when it's absent.
  void _folderContextMenu(BuildContext context, String folderId, Offset pos) {
    final backend = NativeBackendScope.maybeOf(context);
    final st = AppScope.of(context);
    final hidden =
        backend?.engine.hiddenFolders().contains(folderId) ?? false;
    PabloContextMenu.show(
      context,
      position: pos,
      items: [
        ContextMenuItem(
          label: revealActionLabel(),
          iconCharacter: '📂',
          onPressed: () => revealInFileManager(folderId, isDirectory: true),
        ),
        if (backend != null)
          ContextMenuItem(
            label: hidden ? 'Show folder' : 'Hide folder',
            iconCharacter: hidden ? '◉' : '⊘',
            onPressed: () {
              backend.engine.setFolderHidden(folderId, !hidden);
              hydrateHidden(backend.engine.hiddenAssets().toSet());
              st.libraryChanged();
            },
          ),
      ],
    );
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

  // Album cover thumbnail (when set + backend present), else the album glyph.
  Widget _albumLeading(BuildContext context, Album a) {
    const glyph = PabloIcon(
      PabloIconName.albums,
      size: 13,
      color: PabloColors.sectionAlbums,
    );
    if (a.coverAssetId == 0) return glyph;
    final path = pathForAssetId(a.coverAssetId);
    final backend = NativeBackendScope.maybeOf(context);
    if (path == null || backend == null) return glyph;
    return ClipRRect(
      borderRadius: PabloRadius.smAll,
      child: SizedBox(
        width: 18,
        height: 18,
        child: NativeAssetTexture(
          engine: backend.engine,
          events: backend.events,
          assetId: a.coverAssetId,
          path: path,
          targetW: 36,
          targetH: 36,
          fallback: glyph,
        ),
      ),
    );
  }

  // Right-click an album → Rename / Delete.
  void _albumContextMenu(BuildContext context, Album a, Offset pos) {
    PabloContextMenu.show(
      context,
      position: pos,
      items: [
        ContextMenuItem(
          label: 'Rename…',
          iconCharacter: '✏️',
          onPressed: () => _renameAlbum(context, a),
        ),
        ContextMenuItem(
          label: 'Delete',
          iconCharacter: '🗑',
          destructive: true,
          onPressed: () => _deleteAlbum(context, a),
        ),
      ],
    );
  }

  Future<void> _renameAlbum(BuildContext context, Album a) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) return;
    final st = AppScope.of(context);
    final name = await _promptName(context, initial: a.name);
    if (!context.mounted) return;
    if (name == null || name.trim().isEmpty) return;
    backend.engine.renameAlbum(a.id, name.trim());
    st.reloadAlbums(backend.engine);
  }

  Future<void> _deleteAlbum(BuildContext context, Album a) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) return;
    final st = AppScope.of(context);
    final label = a.name.isEmpty ? 'Untitled album' : a.name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete album '$label'?"),
        content: const Text('The album is removed. Your photos are not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    backend.engine.deleteAlbum(a.id);
    // If the deleted album was selected, fall back to a default folder so the
    // grid doesn't render a now-dangling album id.
    if (st.selectedItem == 'album:${a.id}') {
      final first = Library.instance.firstPhotoFolderId;
      if (first != null) st.setSelectedItem(first, NavSection.folders);
    }
    st.reloadAlbums(backend.engine);
  }

  Future<String?> _promptName(BuildContext context, {String? initial}) {
    final ctl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? 'New Album' : 'Rename Album'),
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
            child: Text(initial == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// A hidden-folder row: the folder name + an Unhide action (click the eye).
class _HiddenFolderRow extends StatelessWidget {
  const _HiddenFolderRow({required this.path, required this.onUnhide});

  final String path;
  final VoidCallback onUnhide;

  @override
  Widget build(BuildContext context) {
    final name = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PabloSpacing.xxxl,
        PabloSpacing.sm,
        PabloSpacing.xl,
        PabloSpacing.sm,
      ),
      child: Row(
        children: [
          const PabloIcon(
            PabloIconName.folder,
            size: 13,
            color: PabloColors.textMuted,
          ),
          const SizedBox(width: PabloSpacing.base),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: PabloTypography.sans(
                fontSize: 12,
                color: PabloColors.textMuted,
              ),
            ),
          ),
          PabloIconButton(
            icon: PabloIconName.unlock,
            size: 20,
            iconSize: 12,
            tooltip: 'Unhide folder',
            onPressed: onUnhide,
          ),
        ],
      ),
    );
  }
}

/// A selectable smart-collection row in the sidebar (icon + label + count).
class _SmartRow extends StatelessWidget {
  const _SmartRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final PabloIconName icon;
  final Color iconColor;
  final int count;
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
                icon,
                size: 13,
                color: selected ? PabloColors.selectionPrimary : iconColor,
              ),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  label,
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
                '$count',
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

/// A selectable album row in the sidebar (cover/glyph + name + member count).
/// Right-click opens the rename/delete menu.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.leading,
    required this.selected,
    required this.onSelect,
    this.onContextMenu,
  });

  final Album album;
  final Widget leading;
  final bool selected;
  final VoidCallback onSelect;
  final void Function(Offset position)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PabloColors.selectionBackground : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PabloSpacing.xxxl,
            PabloSpacing.sm,
            PabloSpacing.xl,
            PabloSpacing.sm,
          ),
          child: Row(
            children: [
              leading,
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
