import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import 'decision_buttons.dart';
import 'face_thumb.dart';
import 'people_controller.dart';
import 'people_scope.dart';

class PeopleTab extends StatefulWidget {
  const PeopleTab({required this.photoId, super.key});
  final String photoId;
  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  @override
  Widget build(BuildContext context) {
    final pc = PeopleScope.of(context);
    return _liveBody(pc);
  }

  // ── Live: faces detected in this asset, from the pipeline ──────────────────

  Widget _liveBody(PeopleController pc) {
    final assetId = assetIdFor(widget.photoId);
    final faces = pc.facesForAsset(assetId);
    if (faces.isEmpty) {
      return _emptyState('No faces detected\nin this photo', PabloIconName.person);
    }
    final confirmed = faces.where((f) => f.confirmed).toList();
    final unconfirmed = faces.where((f) => !f.confirmed).toList();
    return Padding(
      padding: const EdgeInsets.only(top: PabloSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (confirmed.isNotEmpty) ...[
            _groupLabel('Confirmed', PabloColors.textMuted),
            for (final f in confirmed)
              _confirmedCard(
                leading: _faceAvatar(f),
                name: pc.personNameFor(f.personId) ?? 'Person ${f.personId}',
              ),
          ],
          if (unconfirmed.isNotEmpty) ...[
            if (confirmed.isNotEmpty) const SizedBox(height: PabloSpacing.lg),
            _groupLabel('Unconfirmed Suggestions', PabloColors.warningText),
            for (final f in unconfirmed)
              _suggestionCard(
                leading: _faceAvatar(f),
                label: Text(
                  pc.tierOf(f) == FaceTier.high ? 'Likely match' : 'Possible match',
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    color: PabloColors.textSecondary,
                  ),
                ),
                confirmLabel: '✓ Confirm',
                onConfirm: () => pc.approve(clusterId: f.clusterId, faceId: f.faceId),
                onReject: () => pc.reject(clusterId: f.clusterId, faceId: f.faceId),
              ),
          ],
        ],
      ),
    );
  }

  Widget _faceAvatar(FaceRow f) =>
      FaceThumb(face: f, size: 26, borderRadius: BorderRadius.circular(13));

  Widget _groupLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: PabloSpacing.base),
        child: Text(
          text.toUpperCase(),
          style: PabloTypography.sans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.05 * 10,
          ),
        ),
      );

  Widget _emptyState(String text, PabloIconName icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Opacity(
                opacity: 0.3,
                child: PabloIcon(icon, size: 28, color: PabloColors.textMuted),
              ),
              const SizedBox(height: PabloSpacing.base),
              Text(
                text,
                textAlign: TextAlign.center,
                style: PabloTypography.sans(
                  fontSize: 12,
                  color: PabloColors.textMuted,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );

  // Shared row chrome for the confirmed + suggestion cards — the leading
  // widget, label, and handlers differ; the card does not.

  Widget _confirmedCard({required Widget leading, required String name}) =>
      Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.lg,
          vertical: PabloSpacing.md,
        ),
        decoration: BoxDecoration(
          color: PabloColors.successBackground,
          border: Border.all(color: PabloColors.successBorder),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: PabloSpacing.lg),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: PabloTypography.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              '✓',
              style: TextStyle(color: PabloColors.success, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _suggestionCard({
    required Widget leading,
    required Widget label,
    required String confirmLabel,
    required VoidCallback onConfirm,
    required VoidCallback onReject,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.base),
        padding: const EdgeInsets.all(PabloSpacing.md),
        decoration: BoxDecoration(
          color: PabloColors.warningBackground,
          border: Border.all(color: PabloColors.warningBorder),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: PabloSpacing.base),
                Expanded(child: label),
              ],
            ),
            const SizedBox(height: PabloSpacing.base),
            Row(
              children: [
                Expanded(
                  child: DecisionPill(
                    label: confirmLabel,
                    color: PabloColors.assignGreen,
                    height: 26,
                    fontSize: 11.5,
                    onTap: onConfirm,
                  ),
                ),
                const SizedBox(width: PabloSpacing.sm),
                DecisionPill(
                  label: '✕',
                  color: PabloColors.ignoreRed,
                  width: 34,
                  height: 26,
                  fontSize: 12,
                  onTap: onReject,
                ),
              ],
            ),
          ],
        ),
      );
}
