// preset_gallery.dart — one-tap starting templates (the DIM recipes, minus
// location). Tapping a card loads a fresh copy into the builder to customize.

import 'package:flutter/material.dart';

import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'scheme_presets.dart';

class PresetGallery extends StatelessWidget {
  const PresetGallery({required this.onPick, super.key});

  final ValueChanged<StorageScheme> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Start from a preset', style: PabloTypography.sectionLabelUpper),
        const SizedBox(height: PabloSpacing.base),
        Wrap(
          spacing: PabloSpacing.base,
          runSpacing: PabloSpacing.base,
          children: [
            for (final preset in buildPresetSchemes())
              _PresetCard(preset: preset, onPick: () => onPick(preset.clone())),
          ],
        ),
      ],
    );
  }
}

class _PresetCard extends StatefulWidget {
  const _PresetCard({required this.preset, required this.onPick});
  final StorageScheme preset;
  final VoidCallback onPick;

  @override
  State<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends State<_PresetCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPick,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.fast,
          width: 188,
          padding: const EdgeInsets.all(PabloSpacing.lg),
          decoration: BoxDecoration(
            color: _hover
                ? PabloColors.accentBackground
                : PabloColors.backgroundSurface,
            border: Border.all(
              color:
                  _hover ? PabloColors.accentPrimary : PabloColors.borderStrong,
            ),
            borderRadius: PabloRadius.smAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.preset.name,
                style: PabloTypography.sans(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PabloSpacing.xs),
              Text(
                _folderSummary(widget.preset),
                style: PabloTypography.mono(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _laneSummary(PatternLane lane) => lane.segments
    .map((s) =>
        s is LiteralSegment ? '“${s.text}”' : (s as TokenSegment).spec.label)
    .join(' + ');

String _folderSummary(StorageScheme s) => s.folderLevels.isEmpty
    ? '(no folders)'
    : s.folderLevels.map(_laneSummary).join('  ›  ');
