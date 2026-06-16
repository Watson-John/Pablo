// PeopleScrollView — per-person section with confirmed-face wrap and the
// suggested-match strip, driven entirely by the live face pipeline.
//
// People and faces come from the PeopleController (native read-back). Confirm /
// reject route to the pipeline; the repo's `changes` stream re-queries, so no
// local verdict state is needed. Until the boot face scan has produced any
// clusters the list is empty and an in-progress hint is shown.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/avatar.dart';
import '../../components/pablo_badge.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'decision_buttons.dart';
import 'face_thumb.dart';
import 'people_controller.dart';
import 'people_scope.dart';

// Render caps — each FaceThumb holds a native texture slot, so we bound how
// many a single person section instantiates at once.
const int _kMaxFacesPerSection = 24;
const int _kMaxSuggestionsPerSection = 12;

class PeopleScrollView extends StatelessWidget {
  const PeopleScrollView({this.onPhotoSecondary, super.key});
  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final pc = PeopleScope.of(context);
    final people = pc.people();
    if (people.isEmpty) {
      return Container(
        color: PabloColors.backgroundSurface,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(PabloSpacing.xxxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.35,
              child: const PabloIcon(PabloIconName.people,
                  size: 40, color: PabloColors.textMuted),
            ),
            const SizedBox(height: PabloSpacing.xl),
            Text(
              pc.isLive
                  ? 'Scanning the library for faces…\nNamed people will appear here as clusters form.'
                  : 'Face recognition is unavailable.\nRun with the native backend to detect people.',
              textAlign: TextAlign.center,
              style: PabloTypography.sans(
                fontSize: 13,
                color: PabloColors.textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      color: PabloColors.backgroundSurface,
      // Lazy: off-screen person sections aren't built, so their FaceThumbs
      // don't each mount a native texture slot (bounds slot usage to the
      // visible sections rather than people.length × 36).
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: people.length,
        itemBuilder: (ctx, i) => _liveSection(context, st, pc, people[i]),
      ),
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
    // Each FaceThumb allocates a native texture slot, so cap how many we
    // render per section (the header still shows the true totals; Accept-All
    // still acts on every suggestion).
    final shownFaces = faces.take(_kMaxFacesPerSection).toList();
    final shownSuggs = suggs.take(_kMaxSuggestionsPerSection).toList();

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
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final f in shownFaces)
                  FaceThumb(face: f, size: tile, hue: person.hue),
                if (faces.length > shownFaces.length)
                  Text(
                    '+${faces.length - shownFaces.length} more',
                    style: PabloTypography.caption,
                  ),
              ],
            ),
          ),
        if (suggs.isNotEmpty)
          _LiveSuggestionStrip(
            tile: tile,
            suggestions: shownSuggs,
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
        DecisionPill(
          width: width / 2 - 2,
          color: PabloColors.assignGreen,
          label: '✓',
          borderRadius: PabloRadius.panelAll,
          onTap: onAccept,
        ),
        const SizedBox(width: PabloSpacing.sm),
        DecisionPill(
          width: width / 2 - 2,
          color: PabloColors.ignoreRed,
          label: '✕',
          borderRadius: PabloRadius.panelAll,
          onTap: onReject,
        ),
      ],
    );
  }
}
