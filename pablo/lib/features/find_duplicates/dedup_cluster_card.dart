// One duplicate cluster: the keeper (green, "KEEP") plus the other copies, each
// tappable to toggle quarantine. "Keep this" promotes a different copy.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'dedup_models.dart';

class DupClusterCard extends StatelessWidget {
  const DupClusterCard({
    required this.cluster,
    required this.index,
    required this.discards,
    required this.onToggleDiscard,
    required this.onSetKeeper,
    super.key,
  });

  final DupCluster cluster;
  final Map<String, Photo> index;
  final Set<String> discards;
  final ValueChanged<String> onToggleDiscard;
  final void Function(DupCluster cluster, String keeperId) onSetKeeper;

  @override
  Widget build(BuildContext context) {
    final removing =
        cluster.discards.where((id) => discards.contains(id)).length;
    return Container(
      margin: const EdgeInsets.only(bottom: PabloSpacing.lg),
      padding: const EdgeInsets.all(PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.panelAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                cluster.kind == DupKind.exact
                    ? 'Exact copy'
                    : '${(cluster.score * 100).round()}% similar',
                style: PabloTypography.sans(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: PabloSpacing.base),
              Text('· ${cluster.photoIds.length} photos',
                  style: PabloTypography.sans(
                      fontSize: 12, color: PabloColors.textMuted)),
              const Spacer(),
              if (removing > 0)
                Text('$removing to remove',
                    style: PabloTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PabloColors.error)),
            ],
          ),
          const SizedBox(height: PabloSpacing.lg),
          Wrap(
            spacing: PabloSpacing.lg,
            runSpacing: PabloSpacing.lg,
            children: [
              for (final id in cluster.photoIds)
                if (index[id] != null)
                  _Tile(
                    photo: index[id]!,
                    isKeeper: id == cluster.keeperId,
                    discarded: discards.contains(id),
                    onTap: () => onToggleDiscard(id),
                    onKeep: () => onSetKeeper(cluster, id),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.photo,
    required this.isKeeper,
    required this.discarded,
    required this.onTap,
    required this.onKeep,
  });

  final Photo photo;
  final bool isKeeper;
  final bool discarded;
  final VoidCallback onTap;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final border = isKeeper
        ? PabloColors.success
        : (discarded ? PabloColors.error : PabloColors.borderSubtle);
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: isKeeper ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 104,
              decoration: BoxDecoration(
                gradient: photo.gradient,
                border: Border.all(color: border, width: 2),
                borderRadius: PabloRadius.lgAll,
              ),
              child: Stack(
                children: [
                  if (isKeeper) _badge('KEEP', PabloColors.success),
                  if (discarded && !isKeeper)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: PabloColors.error.withValues(alpha: 0.45),
                          borderRadius: PabloRadius.lgAll,
                        ),
                        child: const Center(
                          child: Text('✕ remove',
                              style: TextStyle(
                                  color: PabloColors.textOnAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: PabloSpacing.xs),
          if (!isKeeper)
            GestureDetector(
              onTap: onKeep,
              behavior: HitTestBehavior.opaque,
              child: Text('Keep this',
                  style: PabloTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PabloColors.accentPrimary)),
            )
          else
            Text('best copy',
                style: PabloTypography.sans(
                    fontSize: 11, color: PabloColors.textMuted)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Positioned(
        top: 4,
        left: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.base, vertical: PabloSpacing.xs),
          decoration: BoxDecoration(
            color: color,
            borderRadius: PabloRadius.smAll,
          ),
          child: Text(text,
              style: const TextStyle(
                  color: PabloColors.textOnAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 9)),
        ),
      );
}
