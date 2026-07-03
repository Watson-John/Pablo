// Tree/A→Z sort toggle chip for the Folders section header — moved out of
// sidebar.dart (was _FolderSortToggle).

import 'package:flutter/material.dart';

import '../../../app/app_state.dart';
import '../../../components/hover_surface.dart';
import '../../../theme/tokens.dart';

class FolderSortToggle extends StatelessWidget {
  const FolderSortToggle({
    required this.sort,
    required this.onToggle,
    super.key,
  });

  final String sort;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = sort == FolderSort.tree ? 'A→Z' : 'Tree';
    return HoverSurface(
      onTap: onToggle,
      builder: (context, hovered) => AnimatedContainer(
        duration: PabloDurations.hover,
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.md,
          vertical: PabloSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: hovered
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
    );
  }
}
