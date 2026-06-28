// filename_card.dart — the "what each photo is called" stage. One lane builds
// the name; the extension is pinned (kept automatically, never edited) and a
// case option controls how the rendered name is cased.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../components/pablo_radio.dart';
import '../../data/scheme_options.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'pattern_lane_view.dart';
import 'scheme_drag.dart';

class FilenameCard extends StatelessWidget {
  const FilenameCard({
    required this.scheme,
    required this.onChanged,
    super.key,
  });

  final StorageScheme scheme;
  final VoidCallback onChanged;

  void _setCase(FilenameCase c) {
    scheme.options = scheme.options.copyWith(filenameCase: c);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SchemeStageCard(
      icon: PabloIconName.tag,
      title: 'File name',
      helper: 'What each photo is called — the extension is kept automatically.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PatternLaneView(
                  lane: scheme.filename,
                  onChanged: onChanged,
                  placeholder: 'Drag tokens for the name',
                ),
              ),
              const SizedBox(width: PabloSpacing.sm),
              const _ExtensionPin(),
            ],
          ),
          const SizedBox(height: PabloSpacing.lg),
          Row(
            children: [
              Text('Case', style: PabloTypography.label),
              const SizedBox(width: PabloSpacing.xl),
              PabloRadio<FilenameCase>(
                label: 'As typed',
                value: FilenameCase.asIs,
                groupValue: scheme.options.filenameCase,
                onChanged: _setCase,
              ),
              const SizedBox(width: PabloSpacing.lg),
              PabloRadio<FilenameCase>(
                label: 'lower',
                value: FilenameCase.lower,
                groupValue: scheme.options.filenameCase,
                onChanged: _setCase,
              ),
              const SizedBox(width: PabloSpacing.lg),
              PabloRadio<FilenameCase>(
                label: 'UPPER',
                value: FilenameCase.upper,
                groupValue: scheme.options.filenameCase,
                onChanged: _setCase,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The locked extension affix, shown so it's clear the extension isn't part of
/// the editable name.
class _ExtensionPin extends StatelessWidget {
  const _ExtensionPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.base, vertical: PabloSpacing.sm + 1),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PabloIcon(PabloIconName.lock,
              size: 11, color: PabloColors.textFaint),
          const SizedBox(width: PabloSpacing.xs),
          Text('.ext',
              style: PabloTypography.mono(
                  fontSize: 12, color: PabloColors.textMuted)),
        ],
      ),
    );
  }
}
