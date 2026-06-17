// Stage 1 — choose what to scan for duplicates: the current selection, a set of
// folders, or the entire library.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../components/pablo_button.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'dedup_models.dart';

class DedupScopeStage extends StatelessWidget {
  const DedupScopeStage({
    required this.scope,
    required this.folderIds,
    required this.busy,
    required this.onScope,
    required this.onToggleFolder,
    required this.onScan,
    super.key,
  });

  final DedupScopeKind scope;
  final Set<String> folderIds;
  final bool busy;
  final ValueChanged<DedupScopeKind> onScope;
  final ValueChanged<String> onToggleFolder;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final selCount = AppScope.read(context).selectedPhotos.length;
    final canScan = !busy &&
        (scope != DedupScopeKind.selection || selCount > 0) &&
        (scope != DedupScopeKind.folders || folderIds.isNotEmpty);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(PabloSpacing.xxxxl),
          children: [
            Text('Where should we look for duplicates?',
                style: PabloTypography.serif(
                    fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: PabloSpacing.base),
            Text(
              'Exact copies are found instantly; visually-similar photos '
              '(scans, re-exports, different exposure) are matched with AI.',
              style: PabloTypography.sans(
                  fontSize: 13, color: PabloColors.textSecondary),
            ),
            const SizedBox(height: PabloSpacing.xxxl),
            _option(DedupScopeKind.selection, 'Current selection',
                selCount > 0 ? '$selCount photo(s) selected' : 'No photos selected'),
            _option(DedupScopeKind.folders, 'Specific folders',
                'Pick one or more folders below'),
            _option(DedupScopeKind.library, 'Entire library',
                'Every photo Pablo manages'),
            if (scope == DedupScopeKind.folders) _folderPicker(),
            const SizedBox(height: PabloSpacing.xxxl),
            Align(
              alignment: Alignment.centerRight,
              child: PabloButton(
                label: busy ? 'Scanning…' : 'Find Duplicates',
                variant: PabloButtonVariant.primary,
                size: PabloButtonSize.md,
                onPressed: canScan ? onScan : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(DedupScopeKind kind, String title, String subtitle) {
    final selected = scope == kind;
    return Padding(
      padding: const EdgeInsets.only(bottom: PabloSpacing.lg),
      child: GestureDetector(
        onTap: () => onScope(kind),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          decoration: BoxDecoration(
            color: selected
                ? PabloColors.selectionBackground
                : PabloColors.backgroundSurface,
            border: Border.all(
              color: selected
                  ? PabloColors.selectionPrimary
                  : PabloColors.borderSubtle,
            ),
            borderRadius: PabloRadius.panelAll,
          ),
          child: Row(
            children: [
              _dot(selected),
              const SizedBox(width: PabloSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: PabloTypography.sans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: PabloSpacing.xs),
                    Text(subtitle,
                        style: PabloTypography.sans(
                            fontSize: 12, color: PabloColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(bool on) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: on ? PabloColors.selectionPrimary : PabloColors.borderStrong,
            width: 2,
          ),
          color: on ? PabloColors.selectionPrimary : Colors.transparent,
        ),
        child: on
            ? const Center(
                child: Text('✓',
                    style: TextStyle(color: PabloColors.textOnAccent, fontSize: 10)))
            : null,
      );

  Widget _folderPicker() {
    final leaves = <FolderNode>[];
    void walk(FolderNode n) {
      if (n.isGroup) {
        for (final c in n.children) {
          walk(c);
        }
      } else {
        leaves.add(n);
      }
    }
    for (final f in Library.instance.folderTree) {
      walk(f);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: PabloSpacing.lg),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.lgAll,
      ),
      child: ListView(
        padding: const EdgeInsets.all(PabloSpacing.base),
        shrinkWrap: true,
        children: [
          for (final f in leaves)
            _folderRow(f, folderIds.contains(f.id)),
        ],
      ),
    );
  }

  Widget _folderRow(FolderNode f, bool checked) => GestureDetector(
        onTap: () => onToggleFolder(f.id),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.base, vertical: PabloSpacing.md),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: checked
                      ? PabloColors.selectionPrimary
                      : Colors.transparent,
                  border: Border.all(
                      color: checked
                          ? PabloColors.selectionPrimary
                          : PabloColors.borderStrong),
                  borderRadius: PabloRadius.smAll,
                ),
                child: checked
                    ? const Center(
                        child: Text('✓',
                            style: TextStyle(
                                color: PabloColors.textOnAccent, fontSize: 10)))
                    : null,
              ),
              const SizedBox(width: PabloSpacing.lg),
              Expanded(
                  child: Text(f.name,
                      style: PabloTypography.sans(fontSize: 12.5))),
              Text('${f.count}',
                  style: PabloTypography.mono(
                      fontSize: 11, color: PabloColors.textMuted)),
            ],
          ),
        ),
      );
}
