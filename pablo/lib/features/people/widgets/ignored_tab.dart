// Ignored tab of the Unnamed Faces page — faded grid of ignored faces with
// restore actions; extracted from unnamed_faces_page.dart.

import 'package:flutter/material.dart';

import '../../../components/pablo_button.dart';
import '../../../components/pablo_icon.dart';
import '../../../data/models.dart';
import '../../../theme/tokens.dart';
import '../face_palette.dart';

class IgnoredTab extends StatelessWidget {
  const IgnoredTab({
    super.key,
    required this.ignoredClusters,
    required this.ignoredSolos,
    required this.onRestoreCluster,
    required this.onRestoreSolo,
    required this.onRestoreAll,
  });
  final List<UnnamedFace> ignoredClusters;
  final List<UnnamedFace> ignoredSolos;
  final ValueChanged<String> onRestoreCluster;
  final ValueChanged<String> onRestoreSolo;
  final VoidCallback onRestoreAll;

  @override
  Widget build(BuildContext context) {
    final total = ignoredClusters.length + ignoredSolos.length;
    final header = Row(
      children: [
        Expanded(
          child: Text(
            'Ignored faces are excluded from your library.',
            style: PabloTypography.sans(
              fontSize: 12,
              color: PabloColors.textSecondary,
            ),
          ),
        ),
        if (total > 0)
          PabloButton(
            label: 'Restore All',
            size: PabloButtonSize.xs,
            onPressed: onRestoreAll,
          ),
      ],
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(child: header),
        ),
        if (total == 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(PabloSpacing.xxxxl),
              child: Center(
                child: Text(
                  'No ignored faces yet.',
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
                maxCrossAxisExtent: 96,
                mainAxisExtent: 116,
                crossAxisSpacing: PabloSpacing.base,
                mainAxisSpacing: PabloSpacing.base,
              ),
              itemCount: total,
              itemBuilder: (context, i) {
                final inClusters = i < ignoredClusters.length;
                final f = inClusters
                    ? ignoredClusters[i]
                    : ignoredSolos[i - ignoredClusters.length];
                return Align(
                  alignment: Alignment.topLeft,
                  child: IgnoredCard(
                    key: ValueKey(f.id),
                    face: f,
                    onRestore: () => inClusters
                        ? onRestoreCluster(f.id)
                        : onRestoreSolo(f.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class IgnoredCard extends StatelessWidget {
  const IgnoredCard({super.key, required this.face, required this.onRestore});
  final UnnamedFace face;
  final VoidCallback onRestore;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Opacity(
        opacity: 0.4,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: faceTileGradient(face.hue,
                      satTop: 0.18, hueShift: 15, satBottom: 0.22),
                  borderRadius: PabloRadius.lgAll,
                  border: Border.all(color: PabloColors.borderSubtle),
                ),
                child: const Center(
                  child: PabloIcon(
                    PabloIconName.person,
                    size: 24,
                    color: PabloColors.tileGlyphFaded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            GestureDetector(
              onTap: onRestore,
              child: Text(
                'Restore',
                style: PabloTypography.sans(
                  fontSize: 11,
                  color: PabloColors.accentPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
