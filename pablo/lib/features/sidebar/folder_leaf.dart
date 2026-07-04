import 'package:flutter/material.dart';

import '../../components/hover_surface.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class FolderLeaf extends StatelessWidget {
  const FolderLeaf({
    required this.folder,
    required this.selected,
    required this.onSelect,
    this.depth = 0,
    this.onDropPaths,
    this.onContextMenu,
    super.key,
  });

  final FolderNode folder;
  final bool selected;
  final VoidCallback onSelect;
  final int depth;

  /// When set, the row accepts photos dragged from the gallery and reports their
  /// paths so they can be moved into this folder (in-app reorganize).
  final void Function(List<String> paths)? onDropPaths;

  /// Right-click handler (global position) — opens the folder hide menu.
  final void Function(Offset position)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    if (onDropPaths == null) return _row(false);
    return DragTarget<List<String>>(
      onWillAcceptWithDetails: (d) => d.data.isNotEmpty,
      onAcceptWithDetails: (d) => onDropPaths!(d.data),
      builder: (context, candidate, rejected) => _row(candidate.isNotEmpty),
    );
  }

  Widget _row(bool dropHot) {
    return HoverSurface(
      onTap: onSelect,
      onSecondaryTapDown: onContextMenu,
      builder: (context, hovered) {
        final bg = dropHot
            ? PabloColors.accentBackground
            : selected
                ? PabloColors.selectionBackground
                : hovered
                    ? PabloColors.backgroundSidebarHover
                    : Colors.transparent;
        return AnimatedContainer(
          duration: PabloDurations.hover,
          margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
          padding: EdgeInsets.only(
            left: 46.0 + depth * 14,
            right: PabloSpacing.xl,
          ),
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
            border:
                dropHot ? Border.all(color: PabloColors.accentPrimary) : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  folder.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (folder.count > 0)
                Text(
                  '${folder.count}',
                  style: PabloTypography.mono(fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}
