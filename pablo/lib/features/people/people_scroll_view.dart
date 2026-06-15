// PeopleScrollView — per-person section with photo/face wrap and suggestion
// cards.
//
// Mock mode keeps its original behavior: gradient suggestion cards with local
// accept/reject verdict state. Live mode reads the person's confirmed faces and
// suggestions from the PeopleController, renders real face crops, and routes
// confirm/reject to the face pipeline (the repo's `changes` stream re-queries,
// so no local verdict state is needed live).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/avatar.dart';
import '../../components/pablo_badge.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_thumb.dart';
import 'face_thumb.dart';
import 'people_controller.dart';
import 'people_scope.dart';

enum _Verdict { pending, accepted, rejected }

class PeopleScrollView extends StatefulWidget {
  const PeopleScrollView({this.onPhotoSecondary, super.key});
  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  State<PeopleScrollView> createState() => _PeopleScrollViewState();
}

class _PeopleScrollViewState extends State<PeopleScrollView> {
  // Mock-mode local verdict state, keyed by the mockup's person ids.
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
    final pc = PeopleScope.of(context);
    return Container(
      color: PabloColors.backgroundSurface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: pc.people().map((person) {
          return pc.isLive
              ? _liveSection(context, st, pc, person)
              : _mockSection(context, st, person);
        }).toList(),
      ),
    );
  }

  // ── Mock section (unchanged behavior) ──────────────────────────────────────

  Widget _mockSection(BuildContext context, PabloAppState st, Person person) {
    final photos = photosFor(person.id);
    final suggs = suggestionsFor(person.id);
    final personState = _state[person.id]!;
    final pending =
        suggs.where((s) => personState[s.id] == _Verdict.pending).toList();
    final lowConfPending =
        pending.where((s) => s.confidence == SuggestionConfidence.low).length;
    final isSelected = st.selectedItem == person.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          name: person.name,
          hue: person.hue,
          lowConfPending: lowConfPending,
          subtitle: 'Last: ${person.lastDate}',
          countLabel: '${photos.length} photos',
          selected: isSelected,
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
                        ctrl: HardwareKeyboard.instance.isControlPressed ||
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
  }

  // ── Live section (real faces from the pipeline) ────────────────────────────

  Widget _liveSection(
    BuildContext context,
    PabloAppState st,
    PeopleController pc,
    Person person,
  ) {
    final personId = PeopleController.nativePersonId(person.id) ?? -1;
    final faces = pc.confirmedFacesForPerson(personId);
    final suggs = pc.suggestionsForPerson(personId);
    final lowConf =
        suggs.where((f) => pc.tierOf(f) == FaceTier.low).length;
    final isSelected = st.selectedItem == person.id;
    final tile = st.thumbSize * 0.82;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          name: person.name,
          hue: person.hue,
          lowConfPending: lowConf,
          subtitle: person.name == 'Unnamed'
              ? 'Unconfirmed cluster'
              : 'Confirmed person',
          countLabel: '${faces.length} faces',
          selected: isSelected,
        ),
        if (faces.isNotEmpty)
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
              children: [
                for (final f in faces) FaceThumb(face: f, size: tile, hue: person.hue),
              ],
            ),
          ),
        if (suggs.isNotEmpty)
          _LiveSuggestionStrip(
            tile: tile,
            suggestions: suggs,
            hue: person.hue,
            onAccept: (f) => pc.approve(clusterId: f.clusterId, faceId: f.faceId),
            onReject: (f) => pc.reject(clusterId: f.clusterId, faceId: f.faceId),
            onAcceptAll: () {
              for (final f in suggs) {
                pc.approve(clusterId: f.clusterId, faceId: f.faceId);
              }
            },
          ),
      ],
    );
  }
}

/// Shared per-person header (avatar, name + low-conf badge, subtitle, count,
/// slideshow button).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.name,
    required this.hue,
    required this.lowConfPending,
    required this.subtitle,
    required this.countLabel,
    required this.selected,
  });
  final String name;
  final int hue;
  final int lowConfPending;
  final String subtitle;
  final String countLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.xxl,
        vertical: PabloSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: const Border(
          bottom: BorderSide(color: PabloColors.borderSubtle),
        ),
        boxShadow: selected ? PabloShadows.stickyHighlight : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PabloAvatar(name: name, hue: hue, size: 40),
          const SizedBox(width: PabloSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: PabloTypography.sectionTitle),
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
                Text(subtitle, style: PabloTypography.caption),
              ],
            ),
          ),
          Text(
            countLabel,
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
    return _SuggestionStripFrame(
      onAcceptAll: onAcceptAll,
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
                  Positioned(top: 4, left: 4, child: PabloBadge.warning()),
                ],
              ),
            ),
            const SizedBox(height: PabloSpacing.sm),
            _DecisionRow(
              width: w,
              onAccept: () => onDecide(sugg.id, _Verdict.accepted),
              onReject: () => onDecide(sugg.id, _Verdict.rejected),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _LiveSuggestionStrip extends StatelessWidget {
  const _LiveSuggestionStrip({
    required this.tile,
    required this.suggestions,
    required this.hue,
    required this.onAccept,
    required this.onReject,
    required this.onAcceptAll,
  });
  final double tile;
  final List<FaceRow> suggestions;
  final int hue;
  final void Function(FaceRow) onAccept;
  final void Function(FaceRow) onReject;
  final VoidCallback onAcceptAll;

  @override
  Widget build(BuildContext context) {
    return _SuggestionStripFrame(
      onAcceptAll: onAcceptAll,
      children: suggestions.map((f) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                FaceThumb(face: f, size: tile, hue: hue),
                Positioned(top: 4, left: 4, child: PabloBadge.warning()),
              ],
            ),
            const SizedBox(height: PabloSpacing.sm),
            _DecisionRow(
              width: tile,
              onAccept: () => onAccept(f),
              onReject: () => onReject(f),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// The "NEW · Suggested matches" banner + Accept-All header and the tile wrap.
class _SuggestionStripFrame extends StatelessWidget {
  const _SuggestionStripFrame({
    required this.children,
    required this.onAcceptAll,
  });
  final List<Widget> children;
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
            children: children,
          ),
        ],
      ),
    );
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({
    required this.width,
    required this.onAccept,
    required this.onReject,
  });
  final double width;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DecisionBtn(
          width: width / 2 - 2,
          background: PabloColors.assignGreen,
          label: '✓',
          onTap: onAccept,
        ),
        const SizedBox(width: PabloSpacing.sm),
        _DecisionBtn(
          width: width / 2 - 2,
          background: PabloColors.ignoreRed,
          label: '✕',
          onTap: onReject,
        ),
      ],
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
