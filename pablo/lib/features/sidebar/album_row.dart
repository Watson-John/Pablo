import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class AlbumRow extends StatefulWidget {
  const AlbumRow({
    required this.album,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final Album album;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<AlbumRow> createState() => _AlbumRowState();
}

class _AlbumRowState extends State<AlbumRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? PabloColors.selectionBackground
        : _hover
            ? PabloColors.backgroundSidebarHover
            : Colors.transparent;
    final iconColor = widget.selected
        ? PabloColors.selectionPrimary
        : PabloColors.textMuted;
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
          padding: const EdgeInsets.only(
            left: PabloSpacing.xxxl,
            right: PabloSpacing.xl,
          ),
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              PabloIcon(PabloIconName.albums, size: 14, color: iconColor),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  widget.album.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                '${widget.album.count}',
                style: PabloTypography.mono(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
