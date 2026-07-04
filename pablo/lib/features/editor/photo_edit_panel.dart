// PhotoEditPanel — sidebar replacement when the lightbox is open.
//
// Binds the 12 filters + Light/Color/Detail sliders to the shared [EditSession]
// (created by EditSessionProvider above the lightbox), so changes drive the
// native live preview and persist to the catalog on Save. Geometry tools
// (crop/straighten/rotate/flip) land in Stage B; heal/red-eye in Stage D.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../components/pablo_slider.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'adjustment_section.dart';
import 'curves_editor.dart';
import 'edit_footer_bar.dart';
import 'edit_session.dart';
import 'edit_spec.dart';
import 'filter_row.dart';
import 'tools_grid.dart';
import 'widgets/panel_buttons.dart';
import 'widgets/text_item_card.dart';

class PhotoEditPanel extends StatefulWidget {
  const PhotoEditPanel({required this.photo, required this.width, super.key});
  final Photo photo;
  final double width;

  @override
  State<PhotoEditPanel> createState() => _PhotoEditPanelState();
}

class _PhotoEditPanelState extends State<PhotoEditPanel> {
  bool _saved = false;
  bool _savedCopy = false;
  // Used only when the panel is built without an EditSessionScope (e.g. tests
  // or a backend-less run) so the controls never throw.
  EditSession? _fallback;
  final Map<String, bool> _open = {
    'light': false,
    'color': false,
    'detail': false,
  };

  EditSession _session() {
    final s = EditSessionScope.of(context);
    if (s != null) return s;
    return _fallback ??= EditSession(
      engine: null,
      assetId: 0,
      path: widget.photo.filePath,
      saved: EditSpec(),
      contentRev: 0,
    );
  }

  String get _saveLabel => _savedCopy
      ? '✓ Copy saved!'
      : _saved
          ? '✓ Saved!'
          : 'Save Edits';

  void _flashSaved() {
    setState(() {
      _saved = true;
      _savedCopy = false;
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _save(EditSession s) {
    s.save();
    _flashSaved();
  }

  Future<void> _saveCopy(EditSession s) async {
    final stem = _stem(widget.photo.label);
    final loc = await getSaveLocation(
      suggestedName: '$stem-edited.jpg',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['jpg', 'png', 'tif']),
      ],
    );
    if (loc == null || !mounted) return;
    final req = s.exportCopy(loc.path);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (req == 0) {
      messenger?.showSnackBar(const SnackBar(
        content: Text('Export is unavailable on this build.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }
    setState(() {
      _savedCopy = true;
      _saved = false;
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _savedCopy = false);
    });
    messenger?.showSnackBar(SnackBar(
      content: Text('Exporting a copy to ${loc.path}…'),
      duration: const Duration(seconds: 3),
    ));
  }

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  void _reset(EditSession s) => s.resetAdjustments();

  void _revert(EditSession s) => s.revertToOriginal();

  // Rotate/flip are instant actions; crop/straighten (and the deferred heal/
  // red-eye) are modes that toggle the active tool. ToolsGrid passes null when a
  // selected tool is re-tapped.
  void _onTool(EditSession s, String? t) {
    switch (t) {
      case 'rotateL':
        s.rotate(-1);
      case 'rotateR':
        s.rotate(1);
      case 'flipH':
        s.toggleFlipH();
      case 'flipV':
        s.toggleFlipV();
      default:
        s.setTool(t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session();
    final spec = session.spec;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        boxShadow: PabloShadows.sidebar,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xl,
                PabloSpacing.xl,
                PabloSpacing.xl,
                PabloSpacing.xxxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AutoFixButton(
                    active: spec.autoFix,
                    onTap: session.toggleAutoFix,
                  ),
                  const SizedBox(height: PabloSpacing.xl),
                  _groupTitle('Filters'),
                  FilterRow(
                    photo: widget.photo,
                    activeFilter: spec.filter,
                    onChange: session.setFilter,
                  ),
                  const SizedBox(height: PabloSpacing.xxl),
                  _groupTitle('Tools'),
                  ToolsGrid(
                    activeTool: session.activeTool,
                    onChange: (t) => _onTool(session, t),
                  ),
                  if (session.activeTool == 'straighten') ...[
                    const SizedBox(height: PabloSpacing.lg),
                    EditSlider(
                      label: 'Straighten',
                      value: spec.straighten,
                      min: -45,
                      max: 45,
                      unit: '°',
                      onChanged: session.setStraighten,
                    ),
                  ] else if (session.activeTool != null) ...[
                    const SizedBox(height: PabloSpacing.base),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PabloSpacing.lg,
                        vertical: PabloSpacing.base,
                      ),
                      decoration: BoxDecoration(
                        color: PabloColors.accentBackground,
                        border: Border.all(color: PabloColors.accentSoft),
                        borderRadius: PabloRadius.lgAll,
                      ),
                      child: Text(
                        _toolHint(session.activeTool!),
                        style: PabloTypography.sans(
                          fontSize: 11.5,
                          color: PabloColors.accentPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: PabloSpacing.xl),
                  AdjustmentSection(
                    label: 'Light',
                    icon: PabloIconName.sun,
                    open: _open['light']!,
                    onToggle: () =>
                        setState(() => _open['light'] = !_open['light']!),
                    children: [
                      EditSlider(
                        label: 'Exposure',
                        value: spec.exposure,
                        onChanged: (v) => session.mutate((s) => s.exposure = v),
                      ),
                      EditSlider(
                        label: 'Contrast',
                        value: spec.contrast,
                        onChanged: (v) => session.mutate((s) => s.contrast = v),
                      ),
                      EditSlider(
                        label: 'Highlights',
                        value: spec.highlights,
                        onChanged: (v) =>
                            session.mutate((s) => s.highlights = v),
                      ),
                      EditSlider(
                        label: 'Shadows',
                        value: spec.shadows,
                        onChanged: (v) => session.mutate((s) => s.shadows = v),
                      ),
                      EditSlider(
                        label: 'Whites',
                        value: spec.whites,
                        onChanged: (v) => session.mutate((s) => s.whites = v),
                      ),
                      EditSlider(
                        label: 'Blacks',
                        value: spec.blacks,
                        onChanged: (v) => session.mutate((s) => s.blacks = v),
                      ),
                      EditSlider(
                        label: 'Clarity',
                        value: spec.clarity,
                        onChanged: (v) => session.mutate((s) => s.clarity = v),
                      ),
                      EditSlider(
                        label: 'Dehaze',
                        value: spec.dehaze,
                        onChanged: (v) => session.mutate((s) => s.dehaze = v),
                      ),
                    ],
                  ),
                  AdjustmentSection(
                    label: 'Color',
                    icon: PabloIconName.droplet,
                    open: _open['color']!,
                    onToggle: () =>
                        setState(() => _open['color'] = !_open['color']!),
                    children: [
                      EditSlider(
                        label: 'Temperature',
                        value: spec.temperature,
                        onChanged: (v) =>
                            session.mutate((s) => s.temperature = v),
                      ),
                      EditSlider(
                        label: 'Tint',
                        value: spec.tint,
                        onChanged: (v) => session.mutate((s) => s.tint = v),
                      ),
                      EditSlider(
                        label: 'Vibrance',
                        value: spec.vibrance,
                        onChanged: (v) => session.mutate((s) => s.vibrance = v),
                      ),
                      EditSlider(
                        label: 'Saturation',
                        value: spec.saturation,
                        onChanged: (v) =>
                            session.mutate((s) => s.saturation = v),
                      ),
                    ],
                  ),
                  AdjustmentSection(
                    label: 'Detail',
                    icon: PabloIconName.sparkle,
                    open: _open['detail']!,
                    onToggle: () =>
                        setState(() => _open['detail'] = !_open['detail']!),
                    children: [
                      EditSlider(
                        label: 'Sharpness',
                        value: spec.sharpness,
                        min: 0,
                        max: 100,
                        onChanged: (v) => session.mutate((s) => s.sharpness = v),
                      ),
                      EditSlider(
                        label: 'Noise Reduction',
                        value: spec.noise,
                        min: 0,
                        max: 100,
                        onChanged: (v) => session.mutate((s) => s.noise = v),
                      ),
                      EditSlider(
                        label: 'Vignette',
                        value: spec.vignette,
                        onChanged: (v) => session.mutate((s) => s.vignette = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: PabloSpacing.xl),
                  _groupTitle('Curves'),
                  CurvesEditor(session: session),
                  if (!spec.curveIsIdentity)
                    Padding(
                      padding: const EdgeInsets.only(top: PabloSpacing.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: LinkButton(
                            label: 'Reset curve', onTap: session.resetCurve),
                      ),
                    ),
                  const SizedBox(height: PabloSpacing.xxl),
                  _groupTitle('Text'),
                  for (var i = 0; i < spec.texts.length; i++)
                    TextItemCard(
                      key: ValueKey('text$i'),
                      item: spec.texts[i],
                      onChanged: (f) => session.updateText(i, f),
                      onDelete: () => session.removeText(i),
                    ),
                  const SizedBox(height: PabloSpacing.base),
                  AddTextButton(
                    onTap: () => session.addText(TextOverlay(text: 'Text')),
                  ),
                ],
              ),
            ),
          ),
          EditFooterBar(
            isDefault: session.isNeutral,
            isDirty: session.isDirty,
            hasSavedEdits: session.hasSavedEdits,
            saveLabel: _saveLabel,
            onSave: () => _save(session),
            onSaveCopy: () => _saveCopy(session),
            onReset: () => _reset(session),
            onRevert: () => _revert(session),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String label) => Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.base),
        padding: const EdgeInsets.only(bottom: PabloSpacing.md),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PabloColors.borderStrong)),
        ),
        child: Text(
          label,
          style:
              PabloTypography.serif(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

  // Instruction shown under the tool grid for the active mode-style tool.
  String _toolHint(String id) {
    return switch (id) {
      'crop' => 'Drag the handles on the photo to crop',
      'redeye' => 'Tap “Auto” to fix detected eyes, or tap each eye; scroll to size the brush',
      'heal' => 'Tap blemishes to heal; scroll to size the brush',
      _ => '${_toolLabel(id)} — coming soon',
    };
  }

  String _toolLabel(String id) {
    return switch (id) {
      'crop' => 'Crop',
      'straighten' => 'Straighten',
      'rotateL' => 'Rotate L',
      'rotateR' => 'Rotate R',
      'flipH' => 'Flip H',
      'flipV' => 'Flip V',
      'heal' => 'Heal',
      'redeye' => 'Red Eye',
      _ => id,
    };
  }

  @override
  void didUpdateWidget(covariant PhotoEditPanel old) {
    super.didUpdateWidget(old);
    // The panel's State is reused across lightbox navigation (it isn't keyed by
    // photo id), so clear the transient save-flash + active tool when the photo
    // changes — otherwise a "✓ Saved!" flash or a selected tool leaks onto the
    // next photo. The EditSession itself is swapped by EditSessionProvider.
    if (old.photo.id != widget.photo.id) {
      setState(() {
        _saved = false;
        _savedCopy = false;
      });
    }
  }

  @override
  void dispose() {
    _fallback?.dispose();
    super.dispose();
  }
}
