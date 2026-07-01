// AdvancedSearchModal — two-column criteria modal with live result count.

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_checkbox.dart';
import '../../components/pablo_icon.dart';
import '../../components/pablo_icon_button.dart';
import '../../components/pablo_radio.dart';
import '../../components/pablo_text_field.dart';
import '../../data/constants.dart';
import '../../data/saved_search_store.dart';
import '../../theme/tokens.dart';

/// Colour-search options (must match SearchService's `_ColorMatcher`).
const List<String> kAdvSearchColors = [
  'Any', 'Red', 'Orange', 'Yellow', 'Green', 'Cyan', 'Blue', 'Purple',
  'Pink', 'White', 'Black', 'Gray',
];

class AdvancedSearchModal extends StatefulWidget {
  const AdvancedSearchModal({
    required this.photoCount,
    required this.onClose,
    required this.onApply,
    this.initial,
    this.resultCounter,
    this.savedSearches = const [],
    this.onSaveSearch,
    this.onLoadSaved,
    this.onDeleteSaved,
    super.key,
  });

  final int photoCount;
  final VoidCallback onClose;
  final ValueChanged<AdvSearchCriteria> onApply;

  /// Pre-populate the form (e.g. re-open with the active criteria).
  final AdvSearchCriteria? initial;

  /// Returns the REAL number of matches for a criteria set (catalog + retrieval
  /// backed). When null the modal shows the total library count as a fallback.
  final int Function(AdvSearchCriteria)? resultCounter;

  /// Persisted saved searches to offer as one-tap chips.
  final List<StoredSearch> savedSearches;
  final void Function(String name, AdvSearchCriteria criteria)? onSaveSearch;
  final void Function(StoredSearch)? onLoadSaved;
  final void Function(StoredSearch)? onDeleteSaved;

  @override
  State<AdvancedSearchModal> createState() => _AdvancedSearchModalState();
}

class _AdvancedSearchModalState extends State<AdvancedSearchModal> {
  late AdvSearchCriteria _c =
      widget.initial ?? AdvSearchCriteria();
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
      _saveNameCtl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  final _saveNameCtl = TextEditingController();

  // Real match count from the catalog + retrieval index. Falls back to the full
  // library count only when no counter is wired (e.g. widget tests without a
  // backend). No more heuristic estimates.
  int get _resultCount =>
      widget.resultCounter?.call(_c) ?? widget.photoCount;

  void _set(VoidCallback mutate) {
    setState(mutate);
  }

  Future<void> _promptSave() async {
    _saveNameCtl.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _SaveSearchDialog(controller: _saveNameCtl),
    );
    if (!mounted) return;
    if (name != null && name.trim().isNotEmpty) {
      widget.onSaveSearch?.call(name.trim(), _c);
    }
  }

  // One-tap chips to re-run (or delete) a persisted saved search.
  Widget _savedSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.xxxl,
        vertical: PabloSpacing.base,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            'SAVED',
            style: PabloTypography.sans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: PabloColors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: PabloSpacing.lg),
          Expanded(
            child: Wrap(
              spacing: PabloSpacing.base,
              runSpacing: PabloSpacing.sm,
              children: [
                for (final s in widget.savedSearches) _savedChip(s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedChip(StoredSearch s) {
    return GestureDetector(
      onTap: () {
        setState(() => _c = AdvSearchCriteria.fromJson(s.criteria.toJson()));
        widget.onLoadSaved?.call(s);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.lg,
          vertical: PabloSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: PabloColors.accentBackground,
          borderRadius: PabloRadius.pillAll,
          border: Border.all(color: PabloColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.name,
              style: PabloTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: PabloColors.accentActive,
              ),
            ),
            if (widget.onDeleteSaved != null) ...[
              const SizedBox(width: PabloSpacing.sm),
              GestureDetector(
                onTap: () => widget.onDeleteSaved?.call(s),
                child: Text(
                  '✕',
                  style: PabloTypography.sans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: PabloColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
                      const PabloIcon(
                        PabloIconName.search,
                        size: 20,
                        color: PabloColors.textSecondary,
                      ),
                      const SizedBox(width: PabloSpacing.lg),
                      Expanded(
                        child: Text(
                          'Advanced Search',
                          style: PabloTypography.serif(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PabloIconButton(
                        icon: PabloIconName.close,
                        size: 32,
                        iconSize: 16,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                if (widget.savedSearches.isNotEmpty) _savedSearchBar(),
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
                      Container(
                        width: 9,
                        height: 9,
                        margin: const EdgeInsets.only(right: PabloSpacing.base),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _resultCount > 0
                              ? PabloColors.accentPrimary
                              : PabloColors.error,
                          boxShadow: _resultCount > 0
                              ? [
                                  BoxShadow(
                                    color: PabloColors.accentPrimary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
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
                      if (widget.onSaveSearch != null) ...[
                        PabloButton(
                          label: 'Save Search',
                          onPressed: _resultCount > 0 ? _promptSave : null,
                        ),
                        const SizedBox(width: PabloSpacing.lg),
                      ],
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
        if (_c.dateMode == 'specificMonth')
          _select(kAdvSearchMonths, _c.specificMonth,
              (v) => _set(() => _c.specificMonth = v)),
        PabloRadio<String>(
          label: 'Day of month',
          value: 'dayOfMonth',
          groupValue: _c.dateMode,
          onChanged: (v) => _set(() => _c.dateMode = v),
        ),
        if (_c.dateMode == 'dayOfMonth')
          _inlineField('Day', _dayOfMonthCtl, '1–31'),
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
        _select(kAdvSearchFileTypes, _c.fileType,
            (v) => _set(() => _c.fileType = v)),
      ],
    );
  }

  Widget _rightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sHead('People'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: PabloSpacing.sm),
          child: Text(
            'Named people appear here after the face scan completes.',
            style: PabloTypography.sans(
              fontSize: 11,
              color: PabloColors.textMuted,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
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
        _input(_lensCtl, 'e.g. 24-70mm f/2.8', onChanged: (v) => _c.lens = v),
        const SizedBox(height: PabloSpacing.base),
        _label('ISO range'),
        Row(
          children: [
            Expanded(
                child:
                    _input(_isoMinCtl, 'min', onChanged: (v) => _c.isoMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(
                child:
                    _input(_isoMaxCtl, 'max', onChanged: (v) => _c.isoMax = v)),
          ],
        ),
        const SizedBox(height: PabloSpacing.base),
        _label('Aperture'),
        Row(
          children: [
            const Text('f/'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(
                child: _input(_apertureMinCtl, '1.4',
                    onChanged: (v) => _c.apertureMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            const Text('f/'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(
                child: _input(_apertureMaxCtl, '16',
                    onChanged: (v) => _c.apertureMax = v)),
          ],
        ),
        const SizedBox(height: PabloSpacing.base),
        _label('Focal length'),
        Row(
          children: [
            Expanded(
                child: _input(_focalMinCtl, 'min',
                    onChanged: (v) => _c.focalMin = v)),
            const SizedBox(width: PabloSpacing.sm),
            const Text('–'),
            const SizedBox(width: PabloSpacing.sm),
            Expanded(
                child: _input(_focalMaxCtl, 'max',
                    onChanged: (v) => _c.focalMax = v)),
            const SizedBox(width: PabloSpacing.sm),
            Text('mm',
                style: PabloTypography.sans(
                    fontSize: 11, color: PabloColors.textMuted)),
          ],
        ),
        const SizedBox(height: PabloSpacing.xl),
        _sHead('Tags & Albums'),
        _label('Tags (comma-separated)'),
        _input(_tagsCtl, 'vacation, family…', onChanged: (v) => _c.tags = v),
        const SizedBox(height: PabloSpacing.base),
        _label('In album'),
        _select(const ['Any'], _c.album, (v) => _set(() => _c.album = v)),
        const SizedBox(height: PabloSpacing.xl),
        _sHead('Colour'),
        Padding(
          padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
          child: Text(
            'Find photos dominated by a colour.',
            style: PabloTypography.sans(
              fontSize: 11,
              color: PabloColors.textMuted,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ),
        _select(kAdvSearchColors, _c.color, (v) => _set(() => _c.color = v)),
      ],
    );
  }

  Widget _sHead(String label) => Container(
        padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
        margin: const EdgeInsets.only(
            top: PabloSpacing.md, bottom: PabloSpacing.lg),
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

  Widget _inlineField(
      String label, TextEditingController ctl, String placeholder) {
    return Padding(
      padding: const EdgeInsets.only(
          left: PabloSpacing.xxxl, bottom: PabloSpacing.base),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: PabloTypography.sans(
                  fontSize: 11, color: PabloColors.textSecondary),
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
          value: options.contains(value) ? value : options.first,
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

/// A small themed dialog to name a saved search.
class _SaveSearchDialog extends StatelessWidget {
  const _SaveSearchDialog({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    void submit() => Navigator.of(context).pop(controller.text);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(PabloSpacing.xxxl),
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurface,
            borderRadius: PabloRadius.panelAll,
            boxShadow: PabloShadows.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save Search',
                style: PabloTypography.serif(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: PabloSpacing.lg),
              PabloTextField(
                controller: controller,
                placeholder: 'Name this search…',
                autoFocus: true,
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: PabloSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PabloButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PabloSpacing.lg),
                  PabloButton(
                    label: 'Save',
                    variant: PabloButtonVariant.primary,
                    onPressed: submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
