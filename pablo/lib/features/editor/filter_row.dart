import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_surface.dart';
import 'filter_matrices.dart';

class FilterRow extends StatelessWidget {
  const FilterRow({
    required this.photo,
    required this.activeFilter,
    required this.onChange,
    super.key,
  });
  final Photo photo;
  final String activeFilter;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final filters = kEditorFilters;
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 2),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = activeFilter == f.id;
          Widget tile = Container(
            width: 48,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: PabloRadius.lgAll,
              border: Border.all(
                color: sel ? PabloColors.accentPrimary : PabloColors.borderSubtle,
                width: 2,
              ),
              boxShadow: sel ? PabloShadows.md : PabloShadows.sm,
            ),
            clipBehavior: Clip.antiAlias,
            child: PhotoSurface(photo: photo, targetW: 96, targetH: 72),
          );
          if (f.filter != null) {
            tile = ColorFiltered(colorFilter: f.filter!, child: tile);
          }
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChange(f.id),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: sel ? 1.06 : 1.0,
                    duration: PabloDurations.hover,
                    child: tile,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    f.label,
                    style: PabloTypography.sans(
                      fontSize: 9.5,
                      color: sel ? PabloColors.accentPrimary : PabloColors.textMuted,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
