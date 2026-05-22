import 'package:flutter/material.dart';

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
    super.key,
  });

  final FolderNode folder;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool defaultOpen;

  @override
  State<FolderGroup> createState() => _FolderGroupState();
}

class _FolderGroupState extends State<FolderGroup> {
  late bool _open = widget.defaultOpen;
  bool _hover = false;

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
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: AnimatedContainer(
              duration: PabloDurations.hover,
              margin:
                  const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
              padding: const EdgeInsets.only(
                left: PabloSpacing.xxl,
                right: PabloSpacing.xl,
              ),
              height: 28,
              decoration: BoxDecoration(
                color: _hover
                    ? PabloColors.backgroundSidebarHover
                    : Colors.transparent,
                borderRadius: PabloRadius.mdAll,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: PabloDurations.expand,
                    child: const PabloIcon(
                      PabloIconName.chevRight,
                      size: 12,
                      color: PabloColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: PabloSpacing.md),
                  PabloIcon(
                    _open ? PabloIconName.folderOpen : PabloIconName.folder,
                    size: 14,
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
          ),
        ),
        if (_open)
          ...widget.folder.children.map(
            (child) => FolderLeaf(
              folder: child,
              selected: widget.selectedId == child.id,
              onSelect: () => widget.onSelect(child.id),
            ),
          ),
      ],
    );
  }
}
