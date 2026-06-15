// AdvancedSearchModal — two-column criteria modal with live result count.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_checkbox.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/pablo_radio.dart';
import '../../data/mock/mock_data.dart';
import '../../theme/tokens.dart';

class AdvancedSearchModal extends StatefulWidget {
  const AdvancedSearchModal({
    required this.photoCount,
    required this.onClose,
    required this.onApply,
    super.key,
  });

  final int photoCount;
  final VoidCallback onClose;
  final ValueChanged<AdvSearchCriteria> onApply;

  @override
  State<AdvancedSearchModal> createState() => _AdvancedSearchModalState();
}

class _AdvancedSearchModalState extends State<AdvancedSearchModal> {
  late AdvSearchCriteria _c = AdvSearchCriteria();
  final _dateFromCtl = TextEditingController();
  final _dateToCtl = TextEditingController();
  final _dayOfMonthCtl = TextEditingController();
  final _yearCtl = TextEditingController();
  final _lensCtl = TextEditingController();
  final _isoMinCtl = TextEditingController();
  final _isoMaxCtl = TextEditingController();
  final _apertureMinCtl = TextEditingController();
  final _apertureMaxCtl = TextEditingController();
  final _focalMinCtl = TextEditingController();
  final _focalMaxCtl = TextEditingController();
  final _tagsCtl = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _dateFromCtl,
      _dateToCtl,
      _dayOfMonthCtl,
      _yearCtl,
      _lensCtl,
      _isoMinCtl,
      _isoMaxCtl,
      _apertureMinCtl,
      _apertureMaxCtl,
      _focalMinCtl,
      _focalMaxCtl,
      _tagsCtl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _resultCount {
    var n = widget.photoCount;
    if (_c.starred) n = (n * 0.14).floor();
    if (_c.videosOnly) n = (n * 0.08).floor();
    if (_c.people.isNotEmpty) n = (n * (0.3 * _c.people.length)).floor();
    if (_c.dateMode != 'any') n = (n * 0.4).floor();
    if (_c.camera != 'Any') n = (n * 0.6).floor();
    if (_c.tags.isNotEmpty) n = (n * 0.2).floor();
    return n.clamp(0, widget.photoCount);
  }

  void _set(VoidCallback mutate) {
    setState(mutate);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 680,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            decoration: BoxDecoration(
              color: PabloColors.backgroundSurface,
              borderRadius: PabloRadius.panelAll,
              boxShadow: PabloShadows.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PabloSpacing.xxxl,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: PabloColors.borderSubtle),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Advanced Search',
                          style: PabloTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PabloIconButton(
                        icon: PabloIconName.close,
                        size: 28,
                        iconSize: 14,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(PabloSpacing.xxxl),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _leftColumn()),
                        const SizedBox(width: 28),
                        Expanded(child: _rightColumn()),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PabloSpacing.xxxl,
                    vertical: PabloSpacing.xl,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: PabloColors.borderSubtle),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _resultCount > 0
                            ? Text.rich(
                                TextSpan(children: [
                                  TextSpan(
                                    text: '~$_resultCount',
                                    style: PabloTypography.sans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: PabloColors.accentPrimary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' photos match',
                                    style: PabloTypography.sans(
                                      fontSize: 12,
                                      color: PabloColors.textSecondary,
                                    ),
                                  ),
                                ]),
                              )
                            : Text(
                                'No photos match',
                                style: PabloTypography.sans(
                                  fontSize: 12,
                                  color: PabloColors.error,
                                ),
                              ),
                      ),
                      PabloButton(
                        label: 'Clear All',
                        onPressed: () {
                          setState(() {
                            _c = AdvSearchCriteria();
                          });
                        },
                      ),
                      const SizedBox(width: PabloSpacing.lg),
                      PabloButton(label: 'Cancel', onPressed: widget.onClose),
                      const SizedBox(width: PabloSpacing.lg),
                      PabloButton(
                        label: 'Search',
                        variant: PabloButtonVariant.primary,
                        onPressed: () {
                          widget.onApply(_c);
                          widget.onClose();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _leftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sHead('Date & Time'),
        PabloRadio<String>(
          label: 'Any date',
          value: 'any',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        PabloRadio<String>(
          label: 'Date range',
          value: 'range',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        if (_c.dateMode == 'range') ...[
          _inlineField('From', _dateFromCtl, 'YYYY-MM-DD'),
          _inlineField('To', _dateToCtl, 'YYYY-MM-DD'),
        ],
        PabloRadio<String>(
          label: 'Specific month',
          value: 'specificMonth',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        if (_c.dateMode == 'specificMonth') _select(kAdvSearchMonths, _c.specificMonth, (v) => _set(() => _c.specificMonth = v)),
        PabloRadio<String>(
          label: 'Day of month',
          value: 'dayOfMonth',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        if (_c.dateMode == 'dayOfMonth') _inlineField('Day', _dayOfMonthCtl, '1–31'),
        PabloRadio<String>(
          label: 'Year',
          value: 'year',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        if (_c.dateMode == 'year') _inlineField('Year', _yearCtl, 'e.g. 2023'),
        const SizedBox(height: PabloSpacing.xl),
        _sHead('Content & Type'),
        PabloCheckbox(
          label: 'Starred / Favourites only',
          value: _c.starred,
          onChanged: (v) => _set(() => _c.starred = v),
        ),
        PabloCheckbox(
          label: 'Videos only',
          value: _c.videosOnly,
          onChanged: (v) => _set(() => _c.videosOnly = v),
        ),
        PabloCheckbox(
          label: 'Has GPS location',
          value: _c.hasLocation,
          onChanged: (v) => _set(() => _c.hasLocation = v),
        ),
        PabloCheckbox(
          label: 'Not in any album',
          value: _c.notInAlbum,
          onChanged: (v) => _set(() => _c.notInAlbum = v),
        ),
        PabloCheckbox(
          label: 'Has been edited',
          value: _c.hasBeenEdited,
          onChanged: (v) => _set(() => _c.hasBeenEdited = v),
        ),
        const SizedBox(height: PabloSpacing.lg),
        _label('File type'),
        _select(kAdvSearchFileTypes, _c.fileType, (v) => _set(() => _c.fileType = v)),
      ],
    );
  }

  Widget _rightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sHead('People'),
        for (final p in kPeople)
          PabloCheckbox(
            label: '${p.name} (${p.count})',
            value: _c.people.contains(p.id),
            onChanged: (v) => _set(() {
              if (v) {
                _c.people.add(p.id);
              } else {
                _c.people.remove(p.id);
              }
            }),
          ),
        const SizedBox(height: PabloSpacing.lg),
        _label('People match'),
        Row(
          children: [
            PabloRadio<String>(
              label: 'Any (OR)',
              value: 'or',
              groupValue: _c.peopleMatch,
              onChanged: (v) => _set(() => _c.peopleMatch = v),
            ),
            const SizedBox(width: PabloSpacing.xxl),
            PabloRadio<String>(
              label: 'All (AND)',
              value: 'and',
              groupValue: _c.peopleMatch,
              onChanged: (v) => _set(() => _c.peopleMatch = v),
            ),
          ],
        ),
        const SizedBox(height: PabloSpacing.xl),
        _sHead('Camera & EXIF'),
        _label('Camera'),
        _select(kAdvSearchCameras, _c.camera, (v) => _set(() => _c.camera = v)),
        const SizedBox(height: PabloSpacing.base),
        _label('Lens'),
        _input(_lensCtl, 'e.g. 24-70mm f/2.8',
            onChanged: (v) => _c.lens = v),
        const SizedBox(height: PabloSpacing.base),
        _label('ISO range'),
        Row(
          children: [
            Expanded(child: _input(_isoMinCtl, 'min', onChanged: (v) => _c.isoMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(child: _input(_isoMaxCtl, 'max', onChanged: (v) => _c.isoMax = v)),
          ],
        ),
        const SizedBox(height: PabloSpacing.base),
        _label('Aperture'),
        Row(
          children: [
            const Text('f/'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(child: _input(_apertureMinCtl, '1.4', onChanged: (v) => _c.apertureMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            const Text('f/'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(child: _input(_apertureMaxCtl, '16', onChanged: (v) => _c.apertureMax = v)),
          ],
        ),
        const SizedBox(height: PabloSpacing.base),
        _label('Focal length'),
        Row(
          children: [
            Expanded(child: _input(_focalMinCtl, 'min', onChanged: (v) => _c.focalMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(child: _input(_focalMaxCtl, 'max', onChanged: (v) => _c.focalMax = v)),
            const SizedBox(width: PabloSpacing.sm),
            Text('mm', style: PabloTypography.sans(fontSize: 11, color: PabloColors.textMuted)),
          ],
        ),
        const SizedBox(height: PabloSpacing.xl),
        _sHead('Tags & Albums'),
        _label('Tags (comma-separated)'),
        _input(_tagsCtl, 'vacation, family…', onChanged: (v) => _c.tags = v),
        const SizedBox(height: PabloSpacing.base),
        _label('In album'),
        _select(['Any', ...kAlbums.map((a) => a.name)], _c.album, (v) => _set(() => _c.album = v)),
      ],
    );
  }

  Widget _sHead(String label) => Container(
        padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
        margin: const EdgeInsets.only(top: PabloSpacing.md, bottom: PabloSpacing.lg),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
        ),
        child: Text(
          label.toUpperCase(),
          style: PabloTypography.sans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: PabloColors.accentPrimary,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _label(String label) => Padding(
        padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
        child: Text(
          label,
          style: PabloTypography.sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: PabloColors.textSecondary,
          ),
        ),
      );

  Widget _input(
    TextEditingController ctl,
    String placeholder, {
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.mdAll,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.base,
        vertical: PabloSpacing.sm + 1,
      ),
      child: TextField(
        controller: ctl,
        onChanged: (v) {
          onChanged(v);
          setState(() {});
        },
        style: PabloTypography.sans(fontSize: 12),
        cursorColor: PabloColors.accentPrimary,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: placeholder,
          hintStyle: PabloTypography.sans(
            fontSize: 12,
            color: PabloColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _inlineField(String label, TextEditingController ctl, String placeholder) {
    return Padding(
      padding: const EdgeInsets.only(left: PabloSpacing.xxxl, bottom: PabloSpacing.base),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: PabloTypography.sans(fontSize: 11, color: PabloColors.textSecondary),
            ),
          ),
          const SizedBox(width: PabloSpacing.base),
          Expanded(child: _input(ctl, placeholder, onChanged: (_) {})),
        ],
      ),
    );
  }

  Widget _select(
    List<String> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.mdAll,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.base,
        vertical: 1,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          style: PabloTypography.sans(fontSize: 12),
          onChanged: (v) => v == null ? null : onChanged(v),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
        ),
      ),
    );
  }
}
