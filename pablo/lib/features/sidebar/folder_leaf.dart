import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';

class FolderLeaf extends StatefulWidget {
  const FolderLeaf({
    required this.folder,
    required this.selected,
    required this.onSelect,
    this.depth = 0,
    super.key,
  });

  final FolderNode folder;
  final bool selected;
  final VoidCallback onSelect;
  final int depth;

  @override
  State<FolderLeaf> createState() => _FolderLeafState();
}

class _FolderLeafState extends State<FolderLeaf> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? PabloColors.selectionBackground
        : _hover
            ? PabloColors.backgroundSidebarHover
            : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: PabloDurations.hover,
          margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
          padding: EdgeInsets.only(
            left: 46.0 + widget.depth * 14,
            right: PabloSpacing.xl,
          ),
          height: 28,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.folder.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.folder.count > 0)
                Text(
                  '${widget.folder.count}',
                  style: PabloTypography.mono(fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
