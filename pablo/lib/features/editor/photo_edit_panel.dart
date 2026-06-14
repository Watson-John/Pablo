// PhotoEditPanel — sidebar replacement when the lightbox is open.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../components/pablo_slider.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'adjustment_section.dart';
import 'edit_footer_bar.dart';
import 'filter_row.dart';
import 'tools_grid.dart';

class EditAdjustments {
  EditAdjustments({
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.whites = 0,
    this.blacks = 0,
    this.clarity = 0,
    this.dehaze = 0,
    this.temperature = 0,
    this.tint = 0,
    this.vibrance = 0,
    this.saturation = 0,
    this.sharpness = 0,
    this.noiseReduction = 0,
    this.vignette = 0,
  });
  double exposure;
  double contrast;
  double highlights;
  double shadows;
  double whites;
  double blacks;
  double clarity;
  double dehaze;
  double temperature;
  double tint;
  double vibrance;
  double saturation;
  double sharpness;
  double noiseReduction;
  double vignette;

  bool get isDefault =>
      exposure == 0 &&
      contrast == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      whites == 0 &&
      blacks == 0 &&
      clarity == 0 &&
      dehaze == 0 &&
      temperature == 0 &&
      tint == 0 &&
      vibrance == 0 &&
      saturation == 0 &&
      sharpness == 0 &&
      noiseReduction == 0 &&
      vignette == 0;

  EditAdjustments cloneReset() => EditAdjustments();
}

class PhotoEditPanel extends StatefulWidget {
  const PhotoEditPanel({required this.photo, required this.width, super.key});
  final Photo photo;
  final double width;

  @override
  State<PhotoEditPanel> createState() => _PhotoEditPanelState();
}

class _PhotoEditPanelState extends State<PhotoEditPanel> {
  EditAdjustments _adj = EditAdjustments();
  String? _activeTool;
  String _activeFilter = 'none';
  bool _saved = false;
  bool _savedCopy = false;
  final Map<String, bool> _open = {
    'light': false,
    'color': false,
    'detail': false,
  };

  String get _saveLabel => _savedCopy
      ? '✓ Copy saved!'
      : _saved
          ? '✓ Saved!'
          : 'Save Edits';

  void _set(void Function(EditAdjustments) mut) {
    setState(() {
      mut(_adj);
    });
  }

  void _save() {
    setState(() {
      _saved = true;
      _savedCopy = false;
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _saveCopy() {
    setState(() {
      _savedCopy = true;
      _saved = false;
    });
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _savedCopy = false);
    });
  }

  void _reset() {
    setState(() {
      _adj = _adj.cloneReset();
      _activeFilter = 'none';
      _activeTool = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDefault = _adj.isDefault && _activeFilter == 'none';
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
                  _groupTitle('Filters'),
                  FilterRow(
                    photo: widget.photo,
                    activeFilter: _activeFilter,
                    onChange: (f) => setState(() => _activeFilter = f),
                  ),
                  const SizedBox(height: PabloSpacing.xxl),
                  _groupTitle('Tools'),
                  ToolsGrid(
                    activeTool: _activeTool,
                    onChange: (t) => setState(() => _activeTool = t),
                  ),
                  if (_activeTool != null) ...[
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
                        '${_toolLabel(_activeTool!)} — click on photo to apply',
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
                    onToggle: () => setState(() => _open['light'] = !_open['light']!),
                    children: [
                      EditSlider(
                        label: 'Exposure',
                        value: _adj.exposure,
                        onChanged: (v) => _set((a) => a.exposure = v),
                      ),
                      EditSlider(
                        label: 'Contrast',
                        value: _adj.contrast,
                        onChanged: (v) => _set((a) => a.contrast = v),
                      ),
                      EditSlider(
                        label: 'Highlights',
                        value: _adj.highlights,
                        onChanged: (v) => _set((a) => a.highlights = v),
                      ),
                      EditSlider(
                        label: 'Shadows',
                        value: _adj.shadows,
                        onChanged: (v) => _set((a) => a.shadows = v),
                      ),
                      EditSlider(
                        label: 'Whites',
                        value: _adj.whites,
                        onChanged: (v) => _set((a) => a.whites = v),
                      ),
                      EditSlider(
                        label: 'Blacks',
                        value: _adj.blacks,
                        onChanged: (v) => _set((a) => a.blacks = v),
                      ),
                      EditSlider(
                        label: 'Clarity',
                        value: _adj.clarity,
                        onChanged: (v) => _set((a) => a.clarity = v),
                      ),
                      EditSlider(
                        label: 'Dehaze',
                        value: _adj.dehaze,
                        onChanged: (v) => _set((a) => a.dehaze = v),
                      ),
                    ],
                  ),

                  AdjustmentSection(
                    label: 'Color',
                    icon: PabloIconName.droplet,
                    open: _open['color']!,
                    onToggle: () => setState(() => _open['color'] = !_open['color']!),
                    children: [
                      EditSlider(
                        label: 'Temperature',
                        value: _adj.temperature,
                        onChanged: (v) => _set((a) => a.temperature = v),
                      ),
                      EditSlider(
                        label: 'Tint',
                        value: _adj.tint,
                        onChanged: (v) => _set((a) => a.tint = v),
                      ),
                      EditSlider(
                        label: 'Vibrance',
                        value: _adj.vibrance,
                        onChanged: (v) => _set((a) => a.vibrance = v),
                      ),
                      EditSlider(
                        label: 'Saturation',
                        value: _adj.saturation,
                        onChanged: (v) => _set((a) => a.saturation = v),
                      ),
                    ],
                  ),

                  AdjustmentSection(
                    label: 'Detail',
                    icon: PabloIconName.sparkle,
                    open: _open['detail']!,
                    onToggle: () => setState(() => _open['detail'] = !_open['detail']!),
                    children: [
                      EditSlider(
                        label: 'Sharpness',
                        value: _adj.sharpness,
                        min: 0,
                        max: 100,
                        onChanged: (v) => _set((a) => a.sharpness = v),
                      ),
                      EditSlider(
                        label: 'Noise Reduction',
                        value: _adj.noiseReduction,
                        min: 0,
                        max: 100,
                        onChanged: (v) => _set((a) => a.noiseReduction = v),
                      ),
                      EditSlider(
                        label: 'Vignette',
                        value: _adj.vignette,
                        onChanged: (v) => _set((a) => a.vignette = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          EditFooterBar(
            isDefault: isDefault,
            saveLabel: _saveLabel,
            onSave: _save,
            onSaveCopy: _saveCopy,
            onReset: _reset,
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
          style: PabloTypography.serif(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

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
}
