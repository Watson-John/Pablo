// SectionScrollView — sticky section headers + photo wrap. Used for folders,
// albums, and timeline.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';
import 'photo_thumb.dart';

class GallerySectionData {
  GallerySectionData({
    required this.id,
    required this.title,
    this.subtitle = '',
  });
  final String id;
  final String title;
  final String subtitle;
}

class SectionScrollView extends StatelessWidget {
  const SectionScrollView({
    required this.sections,
    this.onPhotoSecondary,
    super.key,
  });

  final List<GallerySectionData> sections;
  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Container(
      color: PabloColors.backgroundSurface,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        // Prefetch ~1.5 screens of sections ahead so their thumbnails are
        // requested (and cached by the native engine) before they scroll in.
        cacheExtent: 1200,
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final section = sections[i];
          final photos = photosFor(section.id);
          final isSelected = st.selectedItem == section.id;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(
                title: section.title,
                subtitle: section.subtitle,
                count: photos.length,
                highlighted: isSelected,
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  PabloSpacing.xxl,
                  PabloSpacing.xl,
                  PabloSpacing.xxl,
                  18,
                ),
                child: Wrap(
                  spacing: PabloSpacing.base,
                  runSpacing: PabloSpacing.base,
                  children: photos.isEmpty
                      ? [
                          Text(
                            'No photos yet.',
                            style: PabloTypography.sans(
                              fontSize: 12,
                              color: PabloColors.textMuted,
                              fontWeight: FontWeight.w400,
                            ).copyWith(fontStyle: FontStyle.italic),
                          ),
                        ]
                      : photos.map((p) {
                          // Isolate each thumb's repaints (hover/select/zoom)
                          // from its neighbours.
                          return RepaintBoundary(
                              child: PhotoThumb(
                            photo: p,
                            size: st.thumbSize,
                            selected: st.selectedPhotos.contains(p.id),
                            inTray: st.trayPhotos.contains(p.id),
                            onTap: (e) {
                              st.selectPhoto(
                                p.id,
                                ctrl: HardwareKeyboard
                                        .instance.isControlPressed ||
                                    HardwareKeyboard.instance.isMetaPressed,
                                shift: HardwareKeyboard.instance.isShiftPressed,
                                contextPhotoIds:
                                    photos.map((x) => x.id).toList(),
                              );
                            },
                            onDoubleTap: () => st.openLightbox(p.id),
                            onAddToTray: () => st.addToTray(p.id),
                            onSecondaryTap: (pos) =>
                                onPhotoSecondary?.call(pos, p.id),
                          ));
                        }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.highlighted,
  });

  final String title;
  final String subtitle;
  final int count;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.xxxl,
        vertical: PabloSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: const Border(
          bottom: BorderSide(color: PabloColors.borderSubtle),
        ),
        boxShadow: highlighted ? PabloShadows.stickyHighlight : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PabloTypography.sectionTitle),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: PabloTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.base,
              vertical: PabloSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: PabloColors.backgroundSurfaceAlt,
              borderRadius: PabloRadius.smAll,
            ),
            child: Text(
              '$count photos',
              style: PabloTypography.mono(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: PabloColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: PabloSpacing.xl),
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
