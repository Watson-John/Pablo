// A small Settings dialog (Tools → Options…) — currently the non-destructive
// "Edit save" mode: where "Save Edits" persists. Default = catalog-only.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Engine;

import '../../backend/native_backend.dart';
import '../../components/dialog_option.dart';
import '../../data/app_config.dart';
import '../../theme/tokens.dart';

Future<void> showEditSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _EditSettingsDialog(),
  );
}

class _EditSettingsDialog extends StatefulWidget {
  const _EditSettingsDialog();
  @override
  State<_EditSettingsDialog> createState() => _EditSettingsDialogState();
}

class _EditSettingsDialogState extends State<_EditSettingsDialog> {
  late String _mode = AppConfig.load().editSaveMode;

  void _set(String mode) {
    setState(() => _mode = mode);
    AppConfig.load().copyWith(editSaveMode: mode).save();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PabloColors.backgroundSurface,
      title: Text('Settings',
          style: PabloTypography.serif(fontSize: 16, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit save',
              style: PabloTypography.sans(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: PabloSpacing.sm),
          Text(
            'How "Save Edits" stores an edit. In every mode a pristine '
            'original survives and Revert restores it.',
            style: PabloTypography.sans(
                fontSize: 11.5, color: PabloColors.textSecondary),
          ),
          const SizedBox(height: PabloSpacing.lg),
          DialogOptionTile(
            label: 'Catalog only (recommended)',
            detail:
                'Edits live in the app database; the original file is never '
                'touched. Instant revert.',
            selected: _mode == EditSaveMode.catalog,
            onTap: () => _set(EditSaveMode.catalog),
          ),
          const SizedBox(height: PabloSpacing.base),
          DialogOptionTile(
            label: 'Layered TIFF beside the photo',
            detail:
                'Also writes a self-contained .pablo.tif (edited render + the '
                'untouched original + the edit spec). Portable and reversible '
                'from the file itself; larger and slower.',
            selected: _mode == EditSaveMode.layeredTiff,
            onTap: () => _set(EditSaveMode.layeredTiff),
          ),
          const SizedBox(height: PabloSpacing.base),
          DialogOptionTile(
            label: 'Overwrite the photo (backup kept)',
            detail: 'Picasa-style: writes your edits into the original file '
                'so every app sees them. The untouched original is kept in a '
                'hidden .pablo-originals folder next to it; Revert restores '
                'it. Re-encodes JPEGs.',
            selected: _mode == EditSaveMode.overwriteBackup,
            onTap: () => _set(EditSaveMode.overwriteBackup),
          ),
          const SizedBox(height: PabloSpacing.xxl),
          _FaceModelDiagnostics(
              engine: NativeBackendScope.maybeOf(context)?.engine),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Face-recognition diagnostics: the active model profile (model_registry.h)
/// and, when model switches have stranded old face rows, a one-click cleanup
/// that prunes unconfirmed stale rows so the next scan repopulates them.
class _FaceModelDiagnostics extends StatefulWidget {
  const _FaceModelDiagnostics({required this.engine});
  final Engine? engine;

  @override
  State<_FaceModelDiagnostics> createState() => _FaceModelDiagnosticsState();
}

class _FaceModelDiagnosticsState extends State<_FaceModelDiagnostics> {
  late final String _modelId = widget.engine?.faceModelId ?? '';
  late int _stale = widget.engine == null ? 0 : widget.engine!.faceStaleCount;

  @override
  Widget build(BuildContext context) {
    if (_modelId.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Face recognition',
            style: PabloTypography.sans(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: PabloSpacing.sm),
        Text(
          'Model: $_modelId'
          '${_stale > 0 ? '  ·  $_stale faces from an older model' : ''}',
          style: PabloTypography.mono(
              fontSize: 10.5, color: PabloColors.textMuted),
        ),
        if (_stale > 0) ...[
          const SizedBox(height: PabloSpacing.base),
          TextButton(
            onPressed: () {
              final removed = widget.engine!.pruneStaleFaces();
              setState(() => _stale = widget.engine!.faceStaleCount);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                  content: Text('Removed $removed outdated face entries — '
                      'the next face scan re-detects them with the current '
                      'model. Named faces keep their names.')));
            },
            child: const Text('Rebuild face index'),
          ),
        ],
      ],
    );
  }
}
