import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';
import 'shared.dart';

class InfoTab extends StatelessWidget {
  const InfoTab({required this.photo, super.key});
  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final exif = getPhotoExif(photo.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 72,
          decoration: BoxDecoration(
            gradient: photo.gradient,
            borderRadius: PabloRadius.lgAll,
            border: Border.all(color: PabloColors.borderSubtle),
          ),
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.base,
            vertical: PabloSpacing.md,
          ),
          child: Text(
            photo.label,
            style: PabloTypography.mono(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        const InfoSectionHeader('Camera'),
        InfoRow(label: 'Camera', value: exif.camera),
        InfoRow(label: 'Lens', value: exif.lens),
        InfoRow(label: 'Aperture', value: exif.aperture),
        InfoRow(label: 'Shutter', value: exif.shutter),
        InfoRow(label: 'ISO', value: '${exif.iso}'),
        InfoRow(label: 'Focal', value: exif.focalLength),
        const InfoSectionHeader('File'),
        InfoRow(label: 'Date', value: exif.date),
        InfoRow(label: 'Time', value: exif.time),
        InfoRow(label: 'Format', value: exif.format),
        InfoRow(label: 'Size', value: '${exif.width} × ${exif.height}'),
        InfoRow(label: 'File size', value: exif.fileSize),
        InfoRow(label: 'Color', value: exif.colorSpace),
        if (exif.location != null) ...[
          const InfoSectionHeader('Location'),
          InfoRow(label: 'Place', value: exif.location!),
        ],
      ],
    );
  }
}
