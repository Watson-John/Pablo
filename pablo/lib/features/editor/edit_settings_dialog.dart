// A small Settings dialog (Tools → Options…) — currently the non-destructive
// "Edit save" mode: where "Save Edits" persists. Default = catalog-only.

import 'package:flutter/material.dart';

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
            'How "Save Edits" stores a non-destructive edit. Either way the '
            'original is never destroyed and edits stay reversible.',
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
