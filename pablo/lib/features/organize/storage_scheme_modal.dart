// storage_scheme_modal.dart — the drag-and-drop builder, assembled. A palette of
// tokens on the left; on the right the two visually-distinct stages (folder
// structure, then file name), the options, and a live preview. Opening lazily
// loads saved schemes so app startup and widget tests stay filesystem-free.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'filename_card.dart';
import 'folder_structure_card.dart';
import 'preset_gallery.dart';
import 'scheme_options_panel.dart';
import 'scheme_preview_tree.dart';
import 'scheme_presets.dart';
import 'storage_scheme_modal_name.dart';
import 'token_palette.dart';

/// Open the builder as an overlay. Loads schemes on first use.
void openStorageSchemeBuilder(BuildContext context, PabloAppState appState) {
  if (appState.schemes.isEmpty) appState.loadSchemes();
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    // The root Overlay isn't under a Material, but the builder's text fields and
    // ink effects need one — supply a transparent Material ancestor.
    builder: (_) => Material(
      type: MaterialType.transparency,
      child: StorageSchemeModal(appState: appState, onClose: entry.remove),
    ),
  );
  overlay.insert(entry);
}

class StorageSchemeModal extends StatefulWidget {
  const StorageSchemeModal({
    required this.appState,
    required this.onClose,
    super.key,
  });

  final PabloAppState appState;
  final VoidCallback onClose;

  @override
  State<StorageSchemeModal> createState() => _StorageSchemeModalState();
}

class _StorageSchemeModalState extends State<StorageSchemeModal> {
  late var _scheme =
      (widget.appState.activeScheme ?? buildPresetSchemes().first).clone();
  late final _initial = _scheme.clone();

  void _load(StorageScheme s) => setState(() => _scheme = s);

  void _save() {
    widget.appState.upsertScheme(_scheme.clone());
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: PabloColors.inkAlpha(0.3)),
          ),
        ),
        Center(
          child: Container(
            width: 880,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            decoration: BoxDecoration(
              color: PabloColors.backgroundSurface,
              borderRadius: PabloRadius.panelAll,
              boxShadow: PabloShadows.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(),
                Flexible(child: _body()),
                _footer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxxl, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
        ),
        child: Row(
          children: [
            const PabloIcon(PabloIconName.folderOpen,
                size: 20, color: PabloColors.sectionFolders),
            const SizedBox(width: PabloSpacing.lg),
            Expanded(
              child: Text('Organization scheme',
                  style: PabloTypography.serif(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            PabloIconButton(
                icon: PabloIconName.close,
                size: 32,
                iconSize: 16,
                onPressed: widget.onClose),
          ],
        ),
      );

  Widget _body() => SingleChildScrollView(
        padding: const EdgeInsets.all(PabloSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SchemeNameField(
              name: _scheme.name,
              onChanged: (v) {
                _scheme.name = v;
                _refresh(); // keep the Save button's enabled state in sync
              },
            ),
            const SizedBox(height: PabloSpacing.xl),
            PresetGallery(onPick: _load),
            const SizedBox(height: PabloSpacing.xxl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 280, child: TokenPalette()),
                const SizedBox(width: PabloSpacing.xl),
                Expanded(child: _stages()),
              ],
            ),
          ],
        ),
      );

  Widget _stages() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FolderStructureCard(scheme: _scheme, onChanged: _refresh),
          const SizedBox(height: PabloSpacing.lg),
          FilenameCard(scheme: _scheme, onChanged: _refresh),
          const SizedBox(height: PabloSpacing.lg),
          SchemeOptionsPanel(scheme: _scheme, onChanged: _refresh),
          const SizedBox(height: PabloSpacing.lg),
          // No key: the State persists (samples gathered once) while each
          // rebuild re-runs the engine against the freshly-edited scheme.
          SchemePreviewTree(scheme: _scheme),
        ],
      );

  void _refresh() => setState(() {});

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxxl, vertical: PabloSpacing.xl),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PabloColors.borderSubtle)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Schemes describe how photos are filed. Pablo applies them when '
                'importing or reorganizing (coming soon).',
                style: PabloTypography.caption,
              ),
            ),
            PabloButton(
                label: 'Reset', onPressed: () => _load(_initial.clone())),
            const SizedBox(width: PabloSpacing.lg),
            PabloButton(label: 'Cancel', onPressed: widget.onClose),
            const SizedBox(width: PabloSpacing.lg),
            PabloButton(
              label: 'Save scheme',
              variant: PabloButtonVariant.primary,
              disabled: _scheme.name.trim().isEmpty,
              onPressed: _scheme.name.trim().isEmpty ? null : _save,
            ),
          ],
        ),
      );
}
