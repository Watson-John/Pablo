// token_palette.dart — the grouped tray of draggable tokens. The user drags
// these into the folder-structure and file-name stages. Groups mirror
// [TokenGroup]; location tokens are absent in v1 (no reverse-geocoder).

import 'package:flutter/material.dart';

import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'scheme_drag.dart';

const Map<TokenGroup, String> _groupLabels = {
  TokenGroup.date: 'Date & time',
  TokenGroup.camera: 'Camera',
  TokenGroup.file: 'File',
  TokenGroup.counter: 'Counter',
  TokenGroup.prompt: 'Event',
};

class TokenPalette extends StatelessWidget {
  const TokenPalette({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tokens', style: PabloTypography.sectionLabelUpper),
          const SizedBox(height: PabloSpacing.md),
          for (final group in TokenGroup.values) ...[
            _GroupBlock(group: group),
            const SizedBox(height: PabloSpacing.lg),
          ],
          Text(
            'Drag a token into a folder level or the file name. '
            'Use the “text” field to add fixed words or separators.',
            style: PabloTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({required this.group});
  final TokenGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
          child: Text(
            _groupLabels[group] ?? group.name,
            style: PabloTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PabloColors.textSecondary,
            ),
          ),
        ),
        Wrap(
          spacing: PabloSpacing.sm,
          runSpacing: PabloSpacing.sm,
          children: [
            for (final spec in TokenSpec.inGroup(group))
              TokenPaletteChip(spec: spec),
          ],
        ),
      ],
    );
  }
}
