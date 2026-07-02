// collage_dialog.dart — choose a collage template, spacing, background, and
// canvas size before compositing. Small themed chooser (set_location_dialog
// shape); returns the chosen options or null on cancel.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_slider.dart';
import '../../theme/tokens.dart';
import 'collage_layouts.dart';

/// Confirmed collage options.
class CollageOptions {
  const CollageOptions({
    required this.template,
    required this.spacing,
    required this.canvas,
    required this.bgRgb,
  });
  final CollageTemplate template;
  final double spacing;
  final int canvas; // square canvas edge in px
  final int bgRgb;
}

const _canvasPresets = <(String, int)>[
  ('2048 px', 2048),
  ('4096 px', 4096),
];

const _bgSwatches = <(String, int)>[
  ('White', 0xFFFFFF),
  ('Black', 0x000000),
  ('Warm', 0xF3EDE6),
];

Future<CollageOptions?> showCollageDialog(
  BuildContext context, {
  required int count,
}) {
  return showDialog<CollageOptions>(
    context: context,
    builder: (_) => _CollageDialog(count: count),
  );
}

class _CollageDialog extends StatefulWidget {
  const _CollageDialog({required this.count});
  final int count;

  @override
  State<_CollageDialog> createState() => _CollageDialogState();
}

class _CollageDialogState extends State<_CollageDialog> {
  CollageTemplate _template = CollageTemplate.grid;
  double _spacing = 2; // percent of canvas
  int _canvas = 2048;
  int _bg = 0xFFFFFF;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create collage · ${widget.count} photos',
                  style: PabloTypography.sans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: PabloSpacing.lg),
              _label('Layout'),
              const SizedBox(height: PabloSpacing.sm),
              for (final t in CollageTemplate.values) _templateOption(t),
              const SizedBox(height: PabloSpacing.lg),
              Row(children: [
                _label('Spacing'),
                const Spacer(),
                Text('${_spacing.round()}%',
                    style: PabloTypography.mono(fontSize: 11)),
              ]),
              PabloSlider(
                value: _spacing,
                max: 10,
                onChanged: (v) => setState(() => _spacing = v),
              ),
              const SizedBox(height: PabloSpacing.lg),
              _label('Canvas'),
              const SizedBox(height: PabloSpacing.sm),
              Row(
                children: [
                  for (final p in _canvasPresets)
                    Padding(
                      padding: const EdgeInsets.only(right: PabloSpacing.base),
                      child: PabloButton(
                        label: p.$1,
                        variant: _canvas == p.$2
                            ? PabloButtonVariant.primary
                            : PabloButtonVariant.secondary,
                        onPressed: () => setState(() => _canvas = p.$2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: PabloSpacing.lg),
              _label('Background'),
              const SizedBox(height: PabloSpacing.sm),
              Row(
                children: [
                  for (final s in _bgSwatches) _bgOption(s.$1, s.$2),
                ],
              ),
              const SizedBox(height: PabloSpacing.xl),
              Row(children: [
                const Spacer(),
                PabloButton(
                  label: 'Cancel',
                  variant: PabloButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: PabloSpacing.base),
                PabloButton(
                  label: 'Create',
                  onPressed: () => Navigator.of(context).pop(CollageOptions(
                    template: _template,
                    spacing: _spacing / 100,
                    canvas: _canvas,
                    bgRgb: _bg,
                  )),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: PabloTypography.sans(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: PabloColors.textSecondary));

  Widget _templateOption(CollageTemplate t) {
    final selected = _template == t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _template = t),
        child: Container(
          margin: const EdgeInsets.only(bottom: PabloSpacing.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.lg, vertical: PabloSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? PabloColors.selectionBackground
                : PabloColors.backgroundSurface,
            border: Border.all(
                color: selected
                    ? PabloColors.selectionPrimary
                    : PabloColors.borderSubtle),
            borderRadius: PabloRadius.mdAll,
          ),
          child: Text(t.label, style: PabloTypography.sans(fontSize: 12.5)),
        ),
      ),
    );
  }

  Widget _bgOption(String name, int rgb) {
    final selected = _bg == rgb;
    return Padding(
      padding: const EdgeInsets.only(right: PabloSpacing.base),
      child: Tooltip(
        message: name,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _bg = rgb),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(0xFF000000 | rgb),
                borderRadius: PabloRadius.smAll,
                border: Border.all(
                  color: selected
                      ? PabloColors.selectionPrimary
                      : PabloColors.borderStrong,
                  width: selected ? 2.5 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
