import 'package:flutter/material.dart';

import '../../components/hover_surface.dart';
import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'folder_leaf.dart';

class FolderGroup extends StatefulWidget {
  const FolderGroup({
    required this.folder,
    required this.selectedId,
    required this.onSelect,
    this.defaultOpen = false,
    this.onDropPaths,
    this.onContextMenu,
    super.key,
  });

  final FolderNode folder;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool defaultOpen;

  /// When set, this group and its child leaves accept photos dragged from the
  /// gallery; the callback gets the target folder's directory id + the paths.
  final void Function(String destDir, List<String> paths)? onDropPaths;

  /// Right-click handler (folder id + global position) — opens the hide menu.
  final void Function(String folderId, Offset position)? onContextMenu;

  @override
  State<FolderGroup> createState() => _FolderGroupState();
}

class _FolderGroupState extends State<FolderGroup> {
  late bool _open = widget.defaultOpen;

  bool get _hasSelectedChild =>
      widget.folder.children.any((c) => c.id == widget.selectedId);

  @override
  void didUpdateWidget(covariant FolderGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasSelectedChild && !_open) {
      setState(() => _open = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onDropPaths == null)
          _header(false)
        else
          DragTarget<List<String>>(
            onWillAcceptWithDetails: (d) => d.data.isNotEmpty,
            onAcceptWithDetails: (d) =>
                widget.onDropPaths!(widget.folder.id, d.data),
            builder: (context, candidate, rejected) =>
                _header(candidate.isNotEmpty),
          ),
        if (_open)
          ...widget.folder.children.map(
            (child) => FolderLeaf(
              folder: child,
              selected: widget.selectedId == child.id,
              onSelect: () => widget.onSelect(child.id),
              onDropPaths: widget.onDropPaths == null
                  ? null
                  : (paths) => widget.onDropPaths!(child.id, paths),
              onContextMenu: widget.onContextMenu == null
                  ? null
                  : (pos) => widget.onContextMenu!(child.id, pos),
            ),
          ),
      ],
    );
  }

  Widget _header(bool dropHot) {
    return HoverSurface(
      onTap: () => setState(() => _open = !_open),
      onSecondaryTapDown: widget.onContextMenu == null
          ? null
          : (pos) => widget.onContextMenu!(widget.folder.id, pos),
      builder: (context, hovered) => AnimatedContainer(
        duration: PabloDurations.hover,
        margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
        padding: const EdgeInsets.only(
          left: PabloSpacing.xxl,
          right: PabloSpacing.xl,
        ),
        height: 28,
        decoration: BoxDecoration(
          color: dropHot
              ? PabloColors.accentBackground
              : hovered
                  ? PabloColors.backgroundSidebarHover
                  : Colors.transparent,
          borderRadius: PabloRadius.mdAll,
          border:
              dropHot ? Border.all(color: PabloColors.accentPrimary) : null,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: _open ? 0.25 : 0,
              duration: PabloDurations.expand,
              child: const PabloIcon(
                PabloIconName.chevRight,
                size: 12,
                strokeWidth: 2.5,
                color: PabloColors.textPrimary,
              ),
            ),
            const SizedBox(width: PabloSpacing.md),
            PabloIcon(
              _open ? PabloIconName.folderOpen : PabloIconName.folder,
              size: 14,
              color: PabloColors.textMuted,
            ),
            const SizedBox(width: PabloSpacing.md),
            Expanded(
              child: Text(
                widget.folder.name,
                overflow: TextOverflow.ellipsis,
                style: PabloTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
