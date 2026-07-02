// export_dialog.dart — "Export to Folder…" (Picasa parity §10 CExportPrefsDialog):
// pick a destination folder, a size preset, JPEG quality, and an optional text
// watermark, then batch-export the tray (or the current photo) through the
// native render pipeline. Follows set_location_dialog.dart's showDialog shape
// and persists the chosen options in AppConfig for next time.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_checkbox.dart';
import '../../components/pablo_slider.dart';
import '../../components/pablo_text_field.dart';
import '../../data/app_config.dart';
import '../../theme/tokens.dart';
import 'export_controller.dart';

/// Long-edge presets. 0 = "Original size".
const _sizePresets = <(String, int)>[
  ('Original size', 0),
  ('Large (2048 px)', 2048),
  ('Medium (1600 px)', 1600),
  ('Small (1024 px)', 1024),
  ('Tiny (800 px)', 800),
];

/// Shows the export dialog for [count] photos. Returns the confirmed
/// [ExportSettings] (with a chosen folder) or null if cancelled.
Future<ExportSettings?> showExportDialog(
  BuildContext context, {
  required int count,
}) {
  return showDialog<ExportSettings>(
    context: context,
    builder: (_) => ExportDialog(count: count),
  );
}

/// The export options dialog. Public + [visibleForTesting] so widget tests can
/// pump it with an injected [initialConfig] (avoiding a read of the machine's
/// persisted AppConfig).
@visibleForTesting
class ExportDialog extends StatefulWidget {
  const ExportDialog({required this.count, this.initialConfig, super.key});
  final int count;
  final AppConfig? initialConfig;

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  late String _folder;
  late int _maxDim;
  late double _quality;
  late bool _watermark;
  late final TextEditingController _wmCtl;
  late double _wmOpacity;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig ?? AppConfig.load();
    _folder = cfg.exportFolder;
    _maxDim = cfg.exportMaxDim;
    _quality = cfg.exportQuality.toDouble();
    _wmCtl = TextEditingController(text: cfg.exportWatermarkText);
    _watermark = cfg.exportWatermarkText.isNotEmpty;
    _wmOpacity = cfg.exportWatermarkOpacity.toDouble();
  }

  @override
  void dispose() {
    _wmCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Export Here');
    if (dir == null || dir.isEmpty || !mounted) return;
    setState(() => _folder = dir);
  }

  void _confirm() {
    final wmText = _watermark ? _wmCtl.text.trim() : '';
    final settings = ExportSettings(
      folder: _folder,
      maxDim: _maxDim,
      quality: _quality.round(),
      watermarkText: wmText,
      watermarkOpacityPct: _wmOpacity.round(),
    );
    // Remember the choices for next time (fire-and-forget; dialog closes now).
    // Skipped under an injected config (widget tests) to stay filesystem-free.
    if (widget.initialConfig == null) {
      AppConfig.load()
          .copyWith(
            exportFolder: _folder,
            exportMaxDim: _maxDim,
            exportQuality: _quality.round(),
            exportWatermarkText: wmText,
            exportWatermarkOpacity: _wmOpacity.round(),
          )
          .save();
    }
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final canExport = _folder.isNotEmpty && n > 0;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                n == 1 ? 'Export photo' : 'Export $n photos',
                style: PabloTypography.sans(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Write flattened JPEG copies (edits baked in) to a folder.',
                style: PabloTypography.sans(
                    fontSize: 12, color: PabloColors.textMuted),
              ),
              const SizedBox(height: PabloSpacing.lg),
              _label('Destination folder'),
              const SizedBox(height: PabloSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _folder.isEmpty ? 'No folder chosen' : _folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(
                        fontSize: 12,
                        color: _folder.isEmpty
                            ? PabloColors.textMuted
                            : PabloColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  PabloButton(
                    label: 'Choose…',
                    variant: PabloButtonVariant.secondary,
                    onPressed: _pickFolder,
                  ),
                ],
              ),
              const SizedBox(height: PabloSpacing.lg),
              _label('Size'),
              const SizedBox(height: PabloSpacing.sm),
              _sizeSelect(),
              const SizedBox(height: PabloSpacing.lg),
              Row(
                children: [
                  _label('JPEG quality'),
                  const Spacer(),
                  Text('${_quality.round()}',
                      style: PabloTypography.mono(fontSize: 11)),
                ],
              ),
              const SizedBox(height: PabloSpacing.sm),
              PabloSlider(
                value: _quality,
                min: 40,
                max: 100,
                onChanged: (v) => setState(() => _quality = v),
              ),
              const SizedBox(height: PabloSpacing.lg),
              PabloCheckbox(
                label: 'Add text watermark',
                value: _watermark,
                onChanged: (v) => setState(() => _watermark = v),
              ),
              if (_watermark) ...[
                const SizedBox(height: PabloSpacing.sm),
                PabloTextField(
                  controller: _wmCtl,
                  placeholder: 'Watermark text',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: PabloSpacing.base),
                Row(
                  children: [
                    _label('Opacity'),
                    const Spacer(),
                    Text('${_wmOpacity.round()}%',
                        style: PabloTypography.mono(fontSize: 11)),
                  ],
                ),
                const SizedBox(height: PabloSpacing.sm),
                PabloSlider(
                  value: _wmOpacity,
                  onChanged: (v) => setState(() => _wmOpacity = v),
                ),
                Text(
                  'White text, bottom-right corner.',
                  style: PabloTypography.sans(
                      fontSize: 11, color: PabloColors.textMuted),
                ),
              ],
              const SizedBox(height: PabloSpacing.xl),
              Row(
                children: [
                  const Spacer(),
                  PabloButton(
                    label: 'Cancel',
                    variant: PabloButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  PabloButton(
                    label: 'Export',
                    onPressed: canExport ? _confirm : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: PabloTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: PabloColors.textSecondary),
      );

  Widget _sizeSelect() {
    return Container(
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.mdAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.base, vertical: 1),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _sizePresets.any((p) => p.$2 == _maxDim) ? _maxDim : 0,
          isDense: true,
          isExpanded: true,
          style: PabloTypography.sans(fontSize: 12),
          onChanged: (v) => setState(() => _maxDim = v ?? 0),
          items: _sizePresets
              .map((p) => DropdownMenuItem(value: p.$2, child: Text(p.$1)))
              .toList(),
        ),
      ),
    );
  }
}
