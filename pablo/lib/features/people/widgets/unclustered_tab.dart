// Unclustered tab of the Unnamed Faces page — bulk-assign toolbar + solo face
// grid; extracted from unnamed_faces_page.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/autocomplete_input.dart';
import '../../../components/pablo_button.dart';
import '../../../components/pablo_icon.dart';
import '../../../data/models.dart';
import '../../../theme/tokens.dart';
import '../face_palette.dart';

class UnclusteredTab extends StatelessWidget {
  const UnclusteredTab({
    super.key,
    required this.active,
    required this.selectedIds,
    required this.bulkCtl,
    required this.onToggleSelect,
    required this.onBulkAssign,
    required this.onBulkIgnore,
    required this.onIgnoreSolo,
  });
  final List<UnnamedFace> active;
  final Set<String> selectedIds;
  final TextEditingController bulkCtl;
  final void Function(String, bool) onToggleSelect;
  final VoidCallback onBulkAssign;
  final VoidCallback onBulkIgnore;
  final ValueChanged<String> onIgnoreSolo;

  @override
  Widget build(BuildContext context) {
    final toolbar = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.lg,
        vertical: PabloSpacing.base,
      ),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.lgAll,
      ),
      child: Row(
        children: [
          Text(
            selectedIds.isNotEmpty
                ? '${selectedIds.length} selected'
                : 'Click to select · Ctrl+click multi',
            style: PabloTypography.sans(
              fontSize: 12,
              fontWeight:
                  selectedIds.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
              color: selectedIds.isNotEmpty
                  ? PabloColors.accentPrimary
                  : PabloColors.textMuted,
            ),
          ),
          const SizedBox(width: PabloSpacing.base),
          Expanded(
            child: AutocompleteInput(
              controller: bulkCtl,
              placeholder: 'Assign name…',
              onSubmit: (_) => onBulkAssign(),
            ),
          ),
          const SizedBox(width: PabloSpacing.base),
          PabloButton(
            label: '✓ Assign',
            variant: PabloButtonVariant.success,
            size: PabloButtonSize.xs,
            onPressed: bulkCtl.text.trim().isNotEmpty && selectedIds.isNotEmpty
                ? onBulkAssign
                : null,
            disabled: bulkCtl.text.trim().isEmpty || selectedIds.isEmpty,
          ),
          const SizedBox(width: PabloSpacing.sm),
          PabloButton(
            label: 'Ignore',
            variant: PabloButtonVariant.danger,
            size: PabloButtonSize.xs,
            onPressed: selectedIds.isNotEmpty ? onBulkIgnore : null,
            disabled: selectedIds.isEmpty,
          ),
        ],
      ),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(child: toolbar),
        ),
        if (active.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(PabloSpacing.xxxxl),
              child: Center(
                child: Text(
                  'All unclustered faces have been assigned or ignored.',
                  style: PabloTypography.sans(
                    fontSize: 13,
                    color: PabloColors.textMuted,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xxl, 0, PabloSpacing.xxl, PabloSpacing.xxl),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 88,
                mainAxisExtent: 76,
                crossAxisSpacing: PabloSpacing.md,
                mainAxisSpacing: PabloSpacing.md,
              ),
              itemCount: active.length,
              itemBuilder: (context, i) {
                final f = active[i];
                return SoloCard(
                  key: ValueKey(f.id),
                  face: f,
                  selected: selectedIds.contains(f.id),
                  onTap: (multi) => onToggleSelect(f.id, multi),
                  onIgnore: () => onIgnoreSolo(f.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class SoloCard extends StatelessWidget {
  const SoloCard({
    super.key,
    required this.face,
    required this.selected,
    required this.onTap,
    required this.onIgnore,
  });
  final UnnamedFace face;
  final bool selected;
  final void Function(bool multi) onTap;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final tile = faceTileGradient(face.hue, hueShift: 15, satBottom: 0.42);
    return SizedBox(
      width: 76,
      height: 76,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            // Toggle multi via shift/ctrl modifiers — for simplicity treat any
            // tap as the basic select; user can still ctrl/cmd in keyboard apps.
            onTap(HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isShiftPressed);
          },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: tile,
                  borderRadius: PabloRadius.lgAll,
                  border: Border.all(
                    color: selected
                        ? PabloColors.accentPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: PabloIcon(
                    PabloIconName.person,
                    size: 22,
                    color: PabloColors.tileGlyph,
                  ),
                ),
              ),
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: onIgnore,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: PabloColors.ignoreRed.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '✕',
                      style: TextStyle(
                        color: PabloColors.textOnAccent,
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
