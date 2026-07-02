// batch_rename_modal.dart — the token-based batch-rename dialog. Reuses the
// storage-scheme lane editor (PatternLaneView + TokenPalette) and renderScheme,
// shows a live old → new preview with conflict badges, and applies via the
// shared reorganizeRename pipeline (catalog-aware + undo).

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../data/library.dart' show photoById;
import '../../data/photo_meta_reader.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'batch_rename.dart';
import 'pattern_lane_view.dart';
import 'reorganize_controller.dart';
import 'token_palette.dart';

/// Open the batch-rename dialog for [ids] (photo ids == file paths).
Future<void> showBatchRenameModal(
    BuildContext context, PabloAppState st, List<String> ids) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BatchRenameModal(st: st, ids: ids),
  );
}

class _BatchRenameModal extends StatefulWidget {
  const _BatchRenameModal({required this.st, required this.ids});
  final PabloAppState st;
  final List<String> ids;

  @override
  State<_BatchRenameModal> createState() => _BatchRenameModalState();
}

class _BatchRenameModalState extends State<_BatchRenameModal> {
  final PatternLane _lane = PatternLane.empty();
  final _counterCtl = TextEditingController(text: '1');

  static const int _previewCap = 50;

  @override
  void dispose() {
    _counterCtl.dispose();
    super.dispose();
  }

  int get _startCounter => int.tryParse(_counterCtl.text.trim()) ?? 1;

  List<RenamePreview> _plan() => planRename(
        paths: widget.ids,
        metaOf: photoMetaForPath,
        lane: _lane,
        startCounter: _startCounter,
      );

  Future<void> _apply() async {
    final moves = movesFrom(_plan());
    Navigator.of(context).pop();
    if (moves.isEmpty) return;
    await reorganizeRename(context, widget.st, moves,
        label: 'Rename ${moves.length} photos');
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan();
    final applyCount = plan.where((r) => !r.isIdentity).length;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      shape: RoundedRectangleBorder(borderRadius: PabloRadius.panelAll),
      child: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PabloSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Batch Rename ${widget.ids.length} Photos',
                  style: PabloTypography.sans(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: PabloSpacing.lg),
              const TokenPalette(),
              const SizedBox(height: PabloSpacing.base),
              PatternLaneView(
                lane: _lane,
                placeholder: 'Drag tokens to build the new name',
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: PabloSpacing.base),
              Row(
                children: [
                  Text('Counter starts at',
                      style: PabloTypography.sans(fontSize: 12)),
                  const SizedBox(width: PabloSpacing.base),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _counterCtl,
                      keyboardType: TextInputType.number,
                      style: PabloTypography.mono(fontSize: 12),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PabloSpacing.lg),
              Text('Preview', style: PabloTypography.caption),
              const SizedBox(height: PabloSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: _PreviewList(plan: plan.take(_previewCap).toList()),
              ),
              const SizedBox(height: PabloSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  TextButton(
                    onPressed: applyCount == 0 ? null : _apply,
                    child: Text(applyCount == 0
                        ? 'No changes'
                        : 'Rename $applyCount'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({required this.plan});
  final List<RenamePreview> plan;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: plan.length,
      itemBuilder: (context, i) {
        final row = plan[i];
        final photo = photoById(row.from);
        final muted = row.isIdentity;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: PabloSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(photo?.label ?? row.oldName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PabloTypography.sans(
                        fontSize: 11.5, color: PabloColors.textMuted)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: PabloSpacing.base),
                child: Text('→', style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Text(row.newName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PabloTypography.sans(
                        fontSize: 11.5,
                        color: muted
                            ? PabloColors.textMuted
                            : PabloColors.textPrimary)),
              ),
              if (row.conflictResolved)
                Padding(
                  padding: const EdgeInsets.only(left: PabloSpacing.sm),
                  child: Text('renumbered',
                      style: PabloTypography.caption
                          .copyWith(color: PabloColors.warning)),
                ),
            ],
          ),
        );
      },
    );
  }
}
