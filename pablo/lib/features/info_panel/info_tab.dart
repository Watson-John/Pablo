// Inspector "Info" tab (Pablo v4): a real photo preview, icon-led property rows
// from the file's own metadata, a Manage-details card, and People / Tags
// preview sections. Camera/date/GPS rows fall back to an em-dash when the file
// carries no EXIF (most of the Flickr30k set).

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show GeoPoint;

import '../../backend/native_backend.dart';
import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../../utils/reveal_in_file_manager.dart';
import '../gallery/photo_surface.dart';
import '../map/reverse_geocode.dart';
import '../map/set_location_dialog.dart';
import '../people/people_scope.dart';
import 'shared.dart';

class InfoTab extends StatelessWidget {
  const InfoTab({
    required this.photo,
    required this.onManage,
    required this.onGoToTab,
    super.key,
  });

  final Photo photo;
  final VoidCallback onManage;
  final void Function(String tab) onGoToTab;

  @override
  Widget build(BuildContext context) {
    final exif = getPhotoExif(photo.id);
    final tags = getPhotoTags(photo.id);
    final assetId = assetIdFor(photo.id);
    final faceCount =
        PeopleScope.of(context).facesForAsset(assetId).length;

    // Current geotag (manual override or EXIF) from the live catalog, if any.
    final backend = NativeBackendScope.maybeOf(context);
    GeoPoint? geo;
    if (backend != null) {
      for (final g in backend.engine.listGeotagged()) {
        if (g.assetId == assetId) {
          geo = g;
          break;
        }
      }
    }
    final geoLabel = geo != null
        ? (reverseGeocode(geo.lat, geo.lon)?.label ??
            '${geo.lat.toStringAsFixed(3)}, ${geo.lon.toStringAsFixed(3)}')
        : exif.location;

    final dims = exif.width > 0 ? '${exif.width} × ${exif.height}' : null;
    final sizeLine =
        [exif.fileSize, dims, exif.format].whereType<String>().join(' · ');
    final dateLine = exif.dateLabel != null
        ? '${exif.dateLabel}${exif.timeLabel != null ? ' · ${exif.timeLabel}' : ''}'
        : 'Unknown';
    final exposure = [
      exif.aperture,
      exif.shutter,
      exif.iso != null ? 'ISO ${exif.iso}' : null,
      exif.focalLength,
    ].whereType<String>().join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview + filename
        Padding(
          padding: const EdgeInsets.only(
              top: PabloSpacing.xl, bottom: PabloSpacing.base),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: PabloRadius.smAll,
                child: Container(
                  width: 64,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: PabloRadius.smAll,
                    border: Border.all(color: PabloColors.borderSubtle),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PhotoSurface(photo: photo, targetW: 128, targetH: 96),
                ),
              ),
              const SizedBox(width: PabloSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      photo.label,
                      style: PabloTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InspectorLink('Open folder location',
                        fontSize: 11.5,
                        onTap: () => revealInFileManager(photo.filePath)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Properties
        MetaRow(
          icon: PabloIconName.calendar,
          label: 'Date taken',
          child: Text(dateLine),
        ),
        MetaRow(
          icon: PabloIconName.library,
          label: 'Size',
          child: Text(sizeLine),
        ),
        MetaRow(
          icon: PabloIconName.camera,
          label: 'Camera',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exif.camera ?? 'Unknown camera'),
              if (exposure.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  exposure,
                  style: PabloTypography.mono(
                      fontSize: 11.5, color: PabloColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        MetaRow(
          icon: PabloIconName.map,
          label: 'Location',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(geoLabel ?? 'No location'),
              if (backend != null) ...[
                const SizedBox(height: 2),
                InspectorLink(
                  geo != null ? 'Edit on map →' : 'Set on map →',
                  fontSize: 11.5,
                  onTap: () => showSetLocationDialog(
                    context,
                    engine: backend.engine,
                    assetIds: [assetId],
                    initialLat: geo?.lat,
                    initialLon: geo?.lon,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Manage details card
        Padding(
          padding: const EdgeInsets.only(top: PabloSpacing.xxl),
          child: _ManageCard(onTap: onManage),
        ),

        // People preview — real detected faces for this photo.
        SectionLabel('People',
            right: InspectorLink('Manage →', onTap: () => onGoToTab('people'))),
        _emptyHint(faceCount == 0
            ? 'No faces detected'
            : '$faceCount face${faceCount == 1 ? '' : 's'} detected'),

        // Tags preview
        SectionLabel('Tags',
            right: InspectorLink('Manage →', onTap: () => onGoToTab('tags'))),
        if (tags.isEmpty)
          _emptyHint('No tags yet')
        else
          Wrap(
            spacing: PabloSpacing.sm,
            runSpacing: PabloSpacing.sm,
            children: [for (final t in tags.take(8)) _TagChip(label: t)],
          ),
      ],
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PabloSpacing.sm),
        child: Text(
          text,
          style: PabloTypography.sans(
            fontSize: 11.5,
            color: PabloColors.textMuted,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
      );
}

class _ManageCard extends StatefulWidget {
  const _ManageCard({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_ManageCard> createState() => _ManageCardState();
}

class _ManageCardState extends State<_ManageCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.fast,
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl, vertical: PabloSpacing.lg),
          decoration: BoxDecoration(
            color: _hover
                ? PabloColors.backgroundHover
                : PabloColors.backgroundSurfaceAlt,
            border: Border.all(color: PabloColors.borderSubtle),
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manage details',
                        style: PabloTypography.sans(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text('Edit camera, file & metadata fields',
                        style: PabloTypography.sans(
                            fontSize: 11, color: PabloColors.textMuted)),
                  ],
                ),
              ),
              const Text('→',
                  style: TextStyle(
                      color: PabloColors.accentPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.smAll,
      ),
      child: Text(label, style: PabloTypography.sans(fontSize: 11.5)),
    );
  }
}
