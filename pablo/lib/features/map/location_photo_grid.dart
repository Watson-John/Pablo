import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_surface.dart';

class LocationPhotoGrid extends StatefulWidget {
  const LocationPhotoGrid({required this.photos, this.thumbSize = 112, super.key});
  final List<Photo> photos;
  final double thumbSize;

  @override
  State<LocationPhotoGrid> createState() => _LocationPhotoGridState();
}

class _LocationPhotoGridState extends State<LocationPhotoGrid> {
  String? _hovered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PabloSpacing.xl, PabloSpacing.lg, PabloSpacing.xl, PabloSpacing.xxxl,
      ),
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: widget.photos.map((p) {
          final hov = _hovered == p.id;
          return MouseRegion(
            onEnter: (_) => setState(() => _hovered = p.id),
            onExit: (_) => setState(() => _hovered = null),
            child: AnimatedContainer(
              duration: PabloDurations.hover,
              width: widget.thumbSize,
              height: widget.thumbSize,
              transformAlignment: Alignment.center,
              transform: hov
                  ? (Matrix4.identity()..scaleByDouble(1.03, 1.03, 1.0, 1.0))
                  : Matrix4.identity(),
              decoration: BoxDecoration(
                borderRadius: PabloRadius.mdAll,
                boxShadow: hov ? PabloShadows.md : PabloShadows.sm,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(child: PhotoSurface(photo: p)),
                  if (p.starred)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: PabloIcon(
                        PabloIconName.starFill,
                        size: 10,
                        color: PabloColors.amber,
                      ),
                    ),
                  Positioned(
                    bottom: 3,
                    left: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PabloSpacing.sm,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        p.label.replaceAll('IMG_', ''),
                        style: PabloTypography.mono(
                          fontSize: 8,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
