// Stage 2 — review & resolve. Exact duplicates first, then visually-similar
// groups behind a similarity slider. Ranked auto-selection keeps the best copy
// per group so thousands of dupes clear with minimal manual checking. Apply
// quarantines the selected copies (never deletes).

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_slider.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'dedup_cluster_card.dart';
import 'dedup_models.dart';

class DedupReviewStage extends StatelessWidget {
  const DedupReviewStage({
    required this.exact,
    required this.similar,
    required this.index,
    required this.threshold,
    required this.rule,
    required this.discards,
    required this.onThreshold,
    required this.onRule,
    required this.onAutoSelect,
    required this.onToggleDiscard,
    required this.onSetKeeper,
    required this.onApply,
    super.key,
  });

  final List<DupCluster> exact;
  final List<DupCluster> similar;
  final Map<String, Photo> index;
  final double threshold;
  final KeeperRule rule;
  final Set<String> discards;
  final ValueChanged<double> onThreshold;
  final ValueChanged<KeeperRule> onRule;
  final void Function({required bool exact, required bool similar}) onAutoSelect;
  final ValueChanged<String> onToggleDiscard;
  final void Function(DupCluster cluster, String keeperId) onSetKeeper;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    // Flatten into a lazy item list so the grid scales to thousands of groups.
    final items = <_Item>[
      _Item.header('Exact duplicates', exact.length,
          'Byte/perceptual-identical — safe to auto-resolve'),
      for (final c in exact) _Item.cluster(c),
      _Item.slider(),
      _Item.header('Similar images', similar.length,
          'Similar scene by visual embedding — review before discarding; '
          'set the threshold'),
      for (final c in similar) _Item.cluster(c),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controlBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(PabloSpacing.xxxl,
                PabloSpacing.xl, PabloSpacing.xxxl, PabloSpacing.xxxl),
            itemCount: items.length,
            itemBuilder: (_, i) => _build(items[i]),
          ),
        ),
        _applyBar(context),
      ],
    );
  }

  Widget _build(_Item it) {
    if (it.cluster != null) {
      return DupClusterCard(
        cluster: it.cluster!,
        index: index,
        discards: discards,
        onToggleDiscard: onToggleDiscard,
        onSetKeeper: onSetKeeper,
      );
    }
    if (it.isSlider) return _sliderRow();
    return Padding(
      padding: const EdgeInsets.only(
          top: PabloSpacing.lg, bottom: PabloSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(it.title!,
              style: PabloTypography.serif(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: PabloSpacing.base),
          Text('${it.count} group(s)',
              style: PabloTypography.mono(
                  fontSize: 11, color: PabloColors.textMuted)),
          const SizedBox(width: PabloSpacing.xl),
          Expanded(
            child: Text(it.subtitle!,
                style: PabloTypography.sans(
                    fontSize: 11.5, color: PabloColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow() => Container(
        margin: const EdgeInsets.symmetric(vertical: PabloSpacing.base),
        padding: const EdgeInsets.all(PabloSpacing.xl),
        decoration: BoxDecoration(
          color: PabloColors.backgroundSurfaceAlt,
          borderRadius: PabloRadius.lgAll,
          border: Border.all(color: PabloColors.borderSubtle),
        ),
        child: Row(
          children: [
            Text('Similarity',
                style: PabloTypography.sans(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: PabloSpacing.lg),
            Text('looser',
                style: PabloTypography.sans(
                    fontSize: 11, color: PabloColors.textMuted)),
            PabloSlider(
              value: threshold,
              min: 0.50,
              max: 0.99,
              width: 280,
              onChanged: onThreshold,
            ),
            Text('stricter',
                style: PabloTypography.sans(
                    fontSize: 11, color: PabloColors.textMuted)),
            const SizedBox(width: PabloSpacing.lg),
            Text('${(threshold * 100).round()}%',
                style: PabloTypography.mono(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _controlBar() => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxxl, vertical: PabloSpacing.lg),
        decoration: const BoxDecoration(
          color: PabloColors.backgroundSurfaceAlt,
          border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
        ),
        child: Row(
          children: [
            Text('Keep',
                style: PabloTypography.sans(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: PabloSpacing.lg),
            for (final r in KeeperRule.values) _ruleChip(r),
            const Spacer(),
            PabloButton(
              label: 'Auto-select duplicates',
              variant: PabloButtonVariant.secondary,
              onPressed: () => onAutoSelect(exact: true, similar: true),
            ),
          ],
        ),
      );

  Widget _ruleChip(KeeperRule r) {
    final on = r == rule;
    return Padding(
      padding: const EdgeInsets.only(right: PabloSpacing.md),
      child: GestureDetector(
        onTap: () => onRule(r),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl, vertical: PabloSpacing.sm),
          decoration: BoxDecoration(
            color: on ? PabloColors.accentSoft : PabloColors.backgroundSurface,
            border: Border.all(
                color: on ? PabloColors.accentPrimary : PabloColors.borderSubtle),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Text(r.label,
              style: PabloTypography.sans(
                  fontSize: 11.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  color: on ? PabloColors.accentActive : PabloColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _applyBar(BuildContext context) {
    final n = discards.length;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.xxxl, vertical: PabloSpacing.xl),
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(top: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            n == 0
                ? 'No photos selected for removal'
                : '$n photo(s) selected — kept copies stay, the rest move to Quarantine',
            style: PabloTypography.sans(
                fontSize: 12.5, color: PabloColors.textSecondary),
          ),
          const Spacer(),
          PabloButton(
            label: 'Quarantine $n photo(s)',
            variant: PabloButtonVariant.danger,
            size: PabloButtonSize.md,
            onPressed: n == 0 ? null : onApply,
          ),
        ],
      ),
    );
  }
}

class _Item {
  _Item.header(this.title, this.count, this.subtitle)
      : cluster = null,
        isSlider = false;
  _Item.cluster(this.cluster)
      : title = null,
        subtitle = null,
        count = 0,
        isSlider = false;
  _Item.slider()
      : title = null,
        subtitle = null,
        count = 0,
        cluster = null,
        isSlider = true;

  final String? title;
  final String? subtitle;
  final int count;
  final DupCluster? cluster;
  final bool isSlider;
}
