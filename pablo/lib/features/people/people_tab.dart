import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import 'decision_buttons.dart';
import 'face_thumb.dart';
import 'manual_face_dialog.dart';
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
    final visible = faces.where((f) => !f.ignored).toList();
    final ignored = faces.where((f) => f.ignored).toList();
    if (faces.isEmpty) {
      return _emptyBody(pc, assetId);
    }
    final confirmed = visible.where((f) => f.confirmed).toList();
    final unconfirmed = visible.where((f) => !f.confirmed).toList();
    final anyNamed = confirmed.any((f) => pc.personNameFor(f.personId) != null);
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
                name: pc.personNameFor(f.personId) ??
                    (f.manual ? 'Unnamed (manual)' : 'Person ${f.personId}'),
                onIgnore: () => pc.setFaceIgnored(f.faceId, true),
                onRemove: f.manual ? () => pc.removeFace(f.faceId) : null,
              ),
          ],
          if (unconfirmed.isNotEmpty) ...[
            if (confirmed.isNotEmpty) const SizedBox(height: PabloSpacing.lg),
            _groupLabel('Unconfirmed Suggestions', PabloColors.warningText),
            for (final f in unconfirmed)
              _suggestionCard(
                leading: _faceAvatar(f),
                label: Text(
                  pc.tierOf(f) == FaceTier.high
                      ? 'Likely match'
                      : 'Possible match',
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    color: PabloColors.textSecondary,
                  ),
                ),
                confirmLabel: '✓ Confirm',
                onConfirm: () =>
                    pc.approve(clusterId: f.clusterId, faceId: f.faceId),
                onReject: () =>
                    pc.reject(clusterId: f.clusterId, faceId: f.faceId),
                onIgnore: () => pc.setFaceIgnored(f.faceId, true),
              ),
          ],
          if (ignored.isNotEmpty) ...[
            const SizedBox(height: PabloSpacing.lg),
            _groupLabel('Ignored', PabloColors.textMuted),
            for (final f in ignored)
              _ignoredCard(
                leading: _faceAvatar(f),
                onRestore: () => pc.setFaceIgnored(f.faceId, false),
              ),
          ],
          const SizedBox(height: PabloSpacing.lg),
          _groupLabel('Add Person', PabloColors.textMuted),
          _AddPersonAffordance(onTap: () => _addManualFace(pc)),
          if (anyNamed) ...[
            const SizedBox(height: PabloSpacing.lg),
            _XmpExportRow(onTap: () => _exportXmp(pc, assetId)),
          ],
        ],
      ),
    );
  }

  Widget _emptyBody(PeopleController pc, int assetId) => Padding(
        padding: const EdgeInsets.only(top: PabloSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _emptyState('No faces detected\nin this photo', PabloIconName.person),
            const SizedBox(height: PabloSpacing.lg),
            _groupLabel('Add Person', PabloColors.textMuted),
            _AddPersonAffordance(onTap: () => _addManualFace(pc)),
          ],
        ),
      );

  Future<void> _addManualFace(PeopleController pc) async {
    final photo = Library.instance.byId[widget.photoId];
    if (photo == null) return;
    final assetId = assetIdFor(widget.photoId);
    final exif = getPhotoExif(widget.photoId);
    await showManualFaceDialog(
      context,
      photo: photo,
      assetId: assetId,
      imgW: exif.width,
      imgH: exif.height,
      controller: pc,
    );
  }

  void _exportXmp(PeopleController pc, int assetId) {
    final path = pc.writeFaceXmp(assetId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path == null
          ? 'No named faces to export'
          : 'Wrote face tags to ${path.split('/').last}'),
    ));
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

  Widget _confirmedCard({
    required Widget leading,
    required String name,
    VoidCallback? onIgnore,
    VoidCallback? onRemove,
  }) =>
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
            if (onRemove != null)
              _FaceIconAction(
                icon: PabloIconName.trash,
                tooltip: 'Remove face',
                onTap: onRemove,
              ),
            if (onIgnore != null)
              _FaceIconAction(
                icon: PabloIconName.close,
                tooltip: 'Ignore this face',
                onTap: onIgnore,
              ),
            const SizedBox(width: PabloSpacing.xs),
            const Text(
              '✓',
              style: TextStyle(color: PabloColors.success, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _ignoredCard({required Widget leading, required VoidCallback onRestore}) =>
      Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.lg,
          vertical: PabloSpacing.md,
        ),
        decoration: BoxDecoration(
          color: PabloColors.backgroundSurfaceAlt,
          border: Border.all(color: PabloColors.borderSubtle),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Row(
          children: [
            Opacity(opacity: 0.5, child: leading),
            const SizedBox(width: PabloSpacing.lg),
            Expanded(
              child: Text(
                'Ignored',
                style: PabloTypography.sans(
                  fontSize: 12.5,
                  color: PabloColors.textMuted,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            _FaceIconAction(
              icon: PabloIconName.check,
              tooltip: 'Restore this face',
              onTap: onRestore,
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
    VoidCallback? onIgnore,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.base),
        padding: const EdgeInsets.all(PabloSpacing.base),
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
                if (onIgnore != null)
                  _FaceIconAction(
                    icon: PabloIconName.close,
                    tooltip: 'Ignore this face',
                    onTap: onIgnore,
                  ),
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
                const SizedBox(width: 5),
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

/// A small square icon button used for per-face actions (ignore / restore /
/// remove) on the People-tab cards.
class _FaceIconAction extends StatelessWidget {
  const _FaceIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final PabloIconName icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xs),
          child: PabloIcon(icon, size: 14, color: PabloColors.textMuted),
        ),
      ),
    );
  }
}

/// Row that exports the photo's named face regions to an XMP sidecar.
class _XmpExportRow extends StatelessWidget {
  const _XmpExportRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          const PabloIcon(PabloIconName.exportIcon,
              size: 13, color: PabloColors.accentPrimary),
          const SizedBox(width: PabloSpacing.base),
          Text(
            'Export face tags (XMP sidecar)',
            style: PabloTypography.sans(
              fontSize: 12,
              color: PabloColors.accentPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Tag someone in this photo" affordance — a dashed-border box with a person
/// icon, matching the design's Add Person section. Tapping opens the manual
/// face-rectangle dialog.
class _AddPersonAffordance extends StatefulWidget {
  const _AddPersonAffordance({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_AddPersonAffordance> createState() => _AddPersonAffordanceState();
}

class _AddPersonAffordanceState extends State<_AddPersonAffordance> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: CustomPaint(
          painter: _DashedRectPainter(
            color:
                _hover ? PabloColors.accentPrimary : PabloColors.borderStrong,
            radius: PabloRadius.md,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.lg,
              vertical: PabloSpacing.lg,
            ),
            child: Row(
              children: [
                PabloIcon(
                  PabloIconName.person,
                  size: 14,
                  color: _hover
                      ? PabloColors.accentPrimary
                      : PabloColors.textMuted,
                ),
                const SizedBox(width: PabloSpacing.base),
                Text(
                  'Tag someone in this photo…',
                  style: PabloTypography.sans(
                    fontSize: 12,
                    color: PabloColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dash),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}
