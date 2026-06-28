// scheme_options_panel.dart — the scheme's processing options. The ones that
// change the rendered path/name (date source, counter base, night-owl) are live
// in Phase A; the file-moving options (smart-copy, RAW pairing, verify, move)
// are shown disabled until Pablo can actually write files (Phase B).

import 'package:flutter/material.dart';

import '../../components/pablo_checkbox.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_radio.dart';
import '../../components/section_header.dart';
import '../../data/scheme_options.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';

class SchemeOptionsPanel extends StatelessWidget {
  const SchemeOptionsPanel({
    required this.scheme,
    required this.onChanged,
    super.key,
  });

  final StorageScheme scheme;
  final VoidCallback onChanged;

  SchemeOptions get _o => scheme.options;
  void _set(SchemeOptions next) {
    scheme.options = next;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsibleSection(
      label: 'Options',
      icon: PabloIconName.settings,
      iconColor: PabloColors.textSecondary,
      defaultOpen: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Date comes from'),
            PabloRadio<DateSource>(
              label: 'Capture date (EXIF), then file date',
              value: DateSource.originalFirst,
              groupValue: _o.dateSource,
              onChanged: (v) => _set(_o.copyWith(dateSource: v)),
            ),
            PabloRadio<DateSource>(
              label: 'File date only',
              value: DateSource.fileTimeOnly,
              groupValue: _o.dateSource,
              onChanged: (v) => _set(_o.copyWith(dateSource: v)),
            ),
            const SizedBox(height: PabloSpacing.lg),
            Row(
              children: [
                Text('Counter starts at', style: PabloTypography.label),
                const SizedBox(width: PabloSpacing.xl),
                _NumberField(
                  value: _o.counterBase,
                  onChanged: (n) => _set(_o.copyWith(counterBase: n)),
                ),
              ],
            ),
            const SizedBox(height: PabloSpacing.lg),
            PabloCheckbox(
              label: 'Group late-night shots with the previous day',
              value: _o.nightOwl.enabled,
              onChanged: (on) => _set(_o.copyWith(
                nightOwl: on
                    ? const NightOwl(thresholdHour: 5, offsetHours: 5)
                    : const NightOwl(),
              )),
            ),
            Padding(
              padding: const EdgeInsets.only(left: PabloSpacing.xxxxl),
              child: Text(
                'Shots before 5am file under the day the night started.',
                style: PabloTypography.caption,
              ),
            ),
            const SizedBox(height: PabloSpacing.lg),
            const _PhaseBNote(),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
        child: Text(t, style: PabloTypography.label),
      );
}

/// The file-moving options, shown disabled until the ingest/reorganize pipeline
/// can write files (Phase B). Listed so the breadth is visible.
class _PhaseBNote extends StatelessWidget {
  const _PhaseBNote();

  @override
  Widget build(BuildContext context) {
    const rows = [
      'Skip files already filed (smart copy)',
      'Keep RAW + JPEG together',
      'Verify each copy',
      'Move instead of copy',
    ];
    return Opacity(
      opacity: 0.5,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('When filing photos (coming soon)',
                style: PabloTypography.sectionLabelUpper),
            const SizedBox(height: PabloSpacing.sm),
            for (final r in rows)
              PabloCheckbox(label: r, value: false, onChanged: (_) {}),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctl =
      TextEditingController(text: '${widget.value}');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.base, vertical: PabloSpacing.sm),
        decoration: BoxDecoration(
          color: PabloColors.backgroundSurface,
          border: Border.all(color: PabloColors.borderSubtle),
          borderRadius: PabloRadius.smAll,
        ),
        child: TextField(
          controller: _ctl,
          keyboardType: TextInputType.number,
          onChanged: (t) {
            final n = int.tryParse(t.trim());
            if (n != null) widget.onChanged(n);
          },
          style: PabloTypography.mono(fontSize: 12, color: PabloColors.textPrimary),
          cursorColor: PabloColors.accentPrimary,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
