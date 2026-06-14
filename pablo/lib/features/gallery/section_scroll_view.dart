// SectionScrollView — sticky section headers + a virtualized photo grid.
// Used for folders, albums, and timeline.
//
// The whole multi-section list is one CustomScrollView: each section is a
// pinned SliverPersistentHeader followed by a lazy grid sliver, so only the
// cells actually on screen (plus the cacheExtent prefetch margin) are built —
// no matter how many sections or photos exist. Two layouts:
//   • grid    — uniform SliverGrid (fixed cell height per thumb size)
//   • masonry — SliverMasonryGrid (per-photo aspect ratio, variable height)
// Both are lazy/virtualized. The mode is driven by AppState.gridMode.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/models.dart';
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

  // Horizontal gutter on each side of the grid.
  static const double _hPad = PabloSpacing.xxl;
  static const double _spacing = PabloSpacing.base;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final masonry = st.gridMode == GridMode.masonry;
    return Container(
      color: PabloColors.backgroundSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Column math is shared by both layouts so a thumb is the same
          // width whether it lands in the uniform grid or a masonry column.
          final avail = (constraints.maxWidth - _hPad * 2).clamp(1.0, 1e9);
          var cols = ((avail + _spacing) / (st.thumbSize + _spacing)).floor();
          if (cols < 1) cols = 1;
          final cw = (avail - _spacing * (cols - 1)) / cols;
          // Uniform-grid cell height: image (cw * 0.72) + caption band.
          final labelH = cw >= 80 ? 19.0 : 2.0;
          final cellH = cw * 0.72 + labelH;

          final slivers = <Widget>[];
          for (final section in sections) {
            final photos = photosFor(section.id);
            slivers.add(SliverPersistentHeader(
              pinned: true,
              delegate: _SectionHeaderDelegate(
                title: section.title,
                subtitle: section.subtitle,
                count: photos.length,
                highlighted: st.selectedItem == section.id,
              ),
            ));
            if (photos.isEmpty) {
              slivers.add(const SliverToBoxAdapter(child: _EmptySection()));
              continue;
            }
            slivers.add(SliverPadding(
              padding: const EdgeInsets.fromLTRB(_hPad, PabloSpacing.xl, _hPad, 18),
              sliver: masonry
                  ? SliverMasonryGrid.count(
                      crossAxisCount: cols,
                      mainAxisSpacing: _spacing,
                      crossAxisSpacing: _spacing,
                      childCount: photos.length,
                      itemBuilder: (context, i) => RepaintBoundary(
                        child: _thumbCell(
                          st,
                          photos,
                          photos[i],
                          cw,
                          imageAspect: photoAspect(photos[i].id),
                          showLabel: false,
                        ),
                      ),
                    )
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: _spacing,
                        crossAxisSpacing: _spacing,
                        mainAxisExtent: cellH,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => RepaintBoundary(
                          child: _thumbCell(st, photos, photos[i], cw),
                        ),
                        childCount: photos.length,
                      ),
                    ),
            ));
          }

          // Prefetch ~1.5 screens ahead so thumbnails are requested (and
          // cached by the native engine) before they scroll into view.
          return CustomScrollView(cacheExtent: 1200, slivers: slivers);
        },
      ),
    );
  }

  // One thumbnail cell. Isolate each thumb's repaints (hover/select/zoom) from
  // its neighbours via the RepaintBoundary the callers wrap around this.
  Widget _thumbCell(
    PabloAppState st,
    List<Photo> photos,
    Photo p,
    double size, {
    double? imageAspect,
    bool showLabel = true,
  }) {
    return PhotoThumb(
      photo: p,
      size: size,
      imageAspect: imageAspect,
      showLabel: showLabel,
      selected: st.selectedPhotos.contains(p.id),
      inTray: st.trayPhotos.contains(p.id),
      onTap: (e) {
        st.selectPhoto(
          p.id,
          ctrl: HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed,
          shift: HardwareKeyboard.instance.isShiftPressed,
          // Built lazily here (on click) rather than per build, so large
          // sections don't pay the id-list cost on every repaint.
          contextPhotoIds: photos.map((x) => x.id).toList(),
        );
      },
      onDoubleTap: () => st.openLightbox(p.id),
      onAddToTray: () => st.addToTray(p.id),
      onSecondaryTap: (pos) => onPhotoSecondary?.call(pos, p.id),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SectionScrollView._hPad,
        PabloSpacing.xl,
        SectionScrollView._hPad,
        18,
      ),
      child: Text(
        'No photos yet.',
        style: PabloTypography.sans(
          fontSize: 12,
          color: PabloColors.textMuted,
          fontWeight: FontWeight.w400,
        ).copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

// Pinned, fixed-height section header. Multiple pinned headers naturally
// push each other off as you scroll (iOS-style sticky sections).
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.highlighted,
  });

  final String title;
  final String subtitle;
  final int count;
  final bool highlighted;

  static const double _extent = 64;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return _SectionHeader(
      title: title,
      subtitle: subtitle,
      count: count,
      highlighted: highlighted,
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate old) {
    return title != old.title ||
        subtitle != old.subtitle ||
        count != old.count ||
        highlighted != old.highlighted;
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
              mainAxisAlignment: MainAxisAlignment.center,
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
