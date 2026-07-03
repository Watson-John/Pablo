// Sidebar list rows — hidden-folder, smart-collection, and album rows, moved
// out of sidebar.dart.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Album;

import '../../../components/pablo_icon.dart';
import '../../../components/pablo_icon_button.dart';
import '../../../theme/tokens.dart';

/// A hidden-folder row: the folder name + an Unhide action (click the eye).
class HiddenFolderRow extends StatelessWidget {
  const HiddenFolderRow({
    required this.path,
    required this.onUnhide,
    super.key,
  });

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
class SmartRow extends StatelessWidget {
  const SmartRow({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.selected,
    required this.onSelect,
    super.key,
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
class AlbumRow extends StatelessWidget {
  const AlbumRow({
    required this.album,
    required this.leading,
    required this.selected,
    required this.onSelect,
    this.onContextMenu,
    super.key,
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
