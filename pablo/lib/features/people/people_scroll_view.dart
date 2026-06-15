// PeopleScrollView — per-person section with photo wrap and suggestion cards.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../components/avatar.dart';
import '../../components/pablo_badge.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_thumb.dart';

enum _Verdict { pending, accepted, rejected }

class PeopleScrollView extends StatefulWidget {
  const PeopleScrollView({this.onPhotoSecondary, super.key});
  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  State<PeopleScrollView> createState() => _PeopleScrollViewState();
}

class _PeopleScrollViewState extends State<PeopleScrollView> {
  final Map<String, Map<String, _Verdict>> _state = {
    for (final p in kPeople)
      p.id: {
        for (final s in suggestionsFor(p.id)) s.id: _Verdict.pending,
      },
  };

  void _decide(String personId, String suggId, _Verdict v) {
    setState(() => _state[personId]![suggId] = v);
  }

  void _acceptAll(String personId, List<Suggestion> pending) {
    setState(() {
      for (final s in pending) {
        _state[personId]![s.id] = _Verdict.accepted;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Container(
      color: PabloColors.backgroundSurface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: kPeople.map((person) {
          final photos = photosFor(person.id);
          final suggs = suggestionsFor(person.id);
          final personState = _state[person.id]!;
          final pending = suggs
              .where((s) => personState[s.id] == _Verdict.pending)
              .toList();
          final lowConfPending = pending
              .where((s) => s.confidence == SuggestionConfidence.low)
              .length;
          final isSelected = st.selectedItem == person.id;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PabloSpacing.xxl,
                  vertical: PabloSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: PabloColors.backgroundSurface,
                  border: const Border(
                    bottom: BorderSide(color: PabloColors.borderSubtle),
                  ),
                  boxShadow: isSelected ? PabloShadows.stickyHighlight : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PabloAvatar(
                      name: person.name,
                      hue: person.hue,
                      size: 40,
                    ),
                    const SizedBox(width: PabloSpacing.xl),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(person.name,
                                  style: PabloTypography.sectionTitle),
                              if (lowConfPending > 0) ...[
                                const SizedBox(width: PabloSpacing.base),
                                PabloBadge.warning(),
                                const SizedBox(width: PabloSpacing.sm + 1),
                                Text(
                                  '$lowConfPending new',
                                  style: PabloTypography.sans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: PabloColors.warningText,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('Last: ${person.lastDate}',
                              style: PabloTypography.caption),
                        ],
                      ),
                    ),
                    Text(
                      '${photos.length} photos',
                      style: PabloTypography.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: PabloColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: PabloSpacing.base),
                    PabloButton(
                      label: 'Slideshow',
                      variant: PabloButtonVariant.primary,
                      icon: PabloIconName.playFill,
                      iconSize: 15,
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  PabloSpacing.xxl,
                  PabloSpacing.xl,
                  PabloSpacing.xxl,
                  PabloSpacing.md,
                ),
                child: Wrap(
                  spacing: PabloSpacing.base,
                  runSpacing: PabloSpacing.base,
                  children: photos
                      .map((p) => PhotoThumb(
                            photo: p,
                            size: st.thumbSize,
                            selected: st.selectedPhotos.contains(p.id),
                            inTray: st.trayPhotos.contains(p.id),
                            onTap: (_) => st.selectPhoto(
                              p.id,
                              ctrl:
                                  HardwareKeyboard.instance.isControlPressed ||
                                      HardwareKeyboard.instance.isMetaPressed,
                              shift: HardwareKeyboard.instance.isShiftPressed,
                              contextPhotoIds: photos.map((x) => x.id).toList(),
                            ),
                            onDoubleTap: () => st.openLightbox(p.id),
                            onAddToTray: () => st.addToTray(p.id),
                            onSecondaryTap: (pos) =>
                                widget.onPhotoSecondary?.call(pos, p.id),
                          ))
                      .toList(),
                ),
              ),
              if (pending.isNotEmpty)
                _SuggestionStrip(
                  thumbSize: st.thumbSize,
                  pending: pending,
                  onDecide: (suggId, v) => _decide(person.id, suggId, v),
                  onAcceptAll: () => _acceptAll(person.id, pending),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.thumbSize,
    required this.pending,
    required this.onDecide,
    required this.onAcceptAll,
  });
  final double thumbSize;
  final List<Suggestion> pending;
  final void Function(String, _Verdict) onDecide;
  final VoidCallback onAcceptAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        PabloSpacing.xxl,
        PabloSpacing.base,
        PabloSpacing.xxl,
        PabloSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: PabloSpacing.base,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: PabloColors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'NEW',
                  style: PabloTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: PabloColors.textOnAccent,
                  ),
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              Text(
                'Suggested matches — confirm or reject',
                style: PabloTypography.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: PabloColors.warningText,
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              PabloButton(
                label: '✓ Accept All',
                variant: PabloButtonVariant.success,
                size: PabloButtonSize.xs,
                onPressed: onAcceptAll,
              ),
            ],
          ),
          const SizedBox(height: PabloSpacing.base),
          Wrap(
            spacing: PabloSpacing.lg,
            runSpacing: PabloSpacing.lg,
            children: pending.map((sugg) {
              final w = thumbSize;
              final h = thumbSize * 0.75;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      gradient: sugg.gradient,
                      borderRadius: PabloRadius.lgAll,
                      border: Border.all(color: PabloColors.borderSubtle),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 4,
                          left: 4,
                          child: PabloBadge.warning(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: PabloSpacing.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DecisionBtn(
                        width: w / 2 - 2,
                        background: PabloColors.assignGreen,
                        label: '✓',
                        onTap: () => onDecide(sugg.id, _Verdict.accepted),
                      ),
                      const SizedBox(width: PabloSpacing.sm),
                      _DecisionBtn(
                        width: w / 2 - 2,
                        background: PabloColors.ignoreRed,
                        label: '✕',
                        onTap: () => onDecide(sugg.id, _Verdict.rejected),
                      ),
                    ],
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DecisionBtn extends StatelessWidget {
  const _DecisionBtn({
    required this.width,
    required this.background,
    required this.label,
    required this.onTap,
  });
  final double width;
  final Color background;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: PabloRadius.panelAll,
          ),
          child: Text(
            label,
            style: PabloTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PabloColors.textOnAccent,
            ),
          ),
        ),
      ),
    );
  }
}
