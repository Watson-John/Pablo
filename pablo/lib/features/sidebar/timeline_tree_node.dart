import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class TimelineTreeNode extends StatefulWidget {
  const TimelineTreeNode({
    required this.node,
    required this.selectedId,
    required this.onSelect,
    this.depth = 0,
    super.key,
  });

  final TimelineNode node;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final int depth;

  @override
  State<TimelineTreeNode> createState() => _TimelineTreeNodeState();
}

class _TimelineTreeNodeState extends State<TimelineTreeNode> {
  bool _open = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    final selected = widget.selectedId == widget.node.id;

    Color bg;
    if (selected) {
      bg = PabloColors.selectionBackground;
    } else if (_hover) {
      bg = PabloColors.backgroundSidebarHover;
    } else {
      bg = Colors.transparent;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (hasChildren) {
                setState(() => _open = !_open);
              } else {
                widget.onSelect(widget.node.id);
              }
            },
            child: AnimatedContainer(
              duration: PabloDurations.hover,
              margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
              padding: EdgeInsets.only(
                left: PabloSpacing.xxl +
                    widget.depth * 14 +
                    (hasChildren ? 0 : 14),
                right: PabloSpacing.xl,
              ),
              height: 28,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: PabloRadius.mdAll,
              ),
              child: Row(
                children: [
                  if (hasChildren) ...[
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: PabloDurations.expand,
                      child: const PabloIcon(
                        PabloIconName.chevRight,
                        size: 10,
                        color: PabloColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: PabloSpacing.sm + 1),
                  ],
                  Expanded(
                    child: Text(
                      widget.node.label,
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(
                        fontSize: 12.5,
                        fontWeight: selected || widget.depth == 0
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.depth == 0
                            ? PabloColors.textSecondary
                            : PabloColors.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.node.count > 0)
                    Text(
                      '${widget.node.count}',
                      style: PabloTypography.mono(fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_open && hasChildren)
          ...widget.node.children.map(
            (c) => TimelineTreeNode(
              node: c,
              selectedId: widget.selectedId,
              onSelect: widget.onSelect,
              depth: widget.depth + 1,
            ),
          ),
      ],
    );
  }
}
