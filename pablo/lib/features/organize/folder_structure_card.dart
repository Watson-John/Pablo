// folder_structure_card.dart — the "where each photo is filed" stage. Each row
// is one nested folder level (a "/" boundary); drop a token onto the dashed
// add-row to create a new level. Kept visually distinct from the file-name
// stage so the two jobs never blur together.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'pattern_lane_view.dart';
import 'scheme_drag.dart';

class FolderStructureCard extends StatelessWidget {
  const FolderStructureCard({
    required this.scheme,
    required this.onChanged,
    super.key,
  });

  final StorageScheme scheme;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final levels = scheme.folderLevels;
    return SchemeStageCard(
      icon: PabloIconName.folder,
      iconColor: PabloColors.sectionFolders,
      title: 'Folder structure',
      helper: 'Where each photo is filed — each row is one nested folder.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < levels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: PabloSpacing.base),
              child: _LevelRow(
                index: i,
                lane: levels[i],
                onChanged: onChanged,
                onDelete: () {
                  levels.removeAt(i);
                  onChanged();
                },
              ),
            ),
          _AddLevelTarget(
            onAddToken: (t) {
              levels.add(PatternLane([TokenSegment(t)]));
              onChanged();
            },
            onAddEmpty: () {
              levels.add(PatternLane.empty());
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.index,
    required this.lane,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final PatternLane lane;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            'Folder ${index + 1}',
            style: PabloTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PabloColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: PatternLaneView(
            lane: lane,
            onChanged: onChanged,
            placeholder: 'Drag tokens for this folder',
          ),
        ),
        const SizedBox(width: PabloSpacing.sm),
        GestureDetector(
          onTap: onDelete,
          behavior: HitTestBehavior.opaque,
          child: const Tooltip(
            message: 'Remove this folder level',
            child: Padding(
              padding: EdgeInsets.all(PabloSpacing.sm),
              child: PabloIcon(PabloIconName.trash,
                  size: 15, color: PabloColors.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddLevelTarget extends StatelessWidget {
  const _AddLevelTarget({required this.onAddToken, required this.onAddEmpty});

  final ValueChanged<TokenType> onAddToken;
  final VoidCallback onAddEmpty;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TokenType>(
      onAcceptWithDetails: (d) => onAddToken(d.data),
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return GestureDetector(
          onTap: onAddEmpty,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hot ? PabloColors.accentBackground : Colors.transparent,
              border: Border.all(
                color:
                    hot ? PabloColors.accentPrimary : PabloColors.borderStrong,
              ),
              borderRadius: PabloRadius.smAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PabloIcon(PabloIconName.plus,
                    size: 13, color: PabloColors.textMuted),
                const SizedBox(width: PabloSpacing.sm),
                Text(
                  hot ? 'Drop to add a folder level' : 'Add folder level',
                  style: PabloTypography.caption,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
