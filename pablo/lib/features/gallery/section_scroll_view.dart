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
import '../../data/aspect_store.dart';
import '../../data/models.dart';
import '../../data/library.dart';
import '../../theme/tokens.dart';
import 'justified_rows.dart';
import 'photo_thumb.dart';

// Memoized justified row plans, keyed by (section, width, height, aspectRev,
// count). Keeps scrolling recompute-free; recomputes when aspects land or the
// layout/section changes. Small LRU — only a few sections are ever on screen.
final Map<String, List<JRow>> _planCache = {};
final List<String> _planOrder = [];

List<JRow> _rowPlanFor(String sectionId, List<Photo> photos, double avail,
    double targetH, double gap, int rev) {
  final key =
      '$sectionId|${avail.round()}|${targetH.round()}|$rev|${photos.length}';
  final cached = _planCache[key];
  if (cached != null) return cached;
  final aspects = [
    for (final p in photos) AspectStore.instance.aspectOf(p.filePath) ?? 1.0,
  ];
  final rows =
      packRows(aspects: aspects, availWidth: avail, targetH: targetH, gap: gap);
  _planCache[key] = rows;
  _planOrder.add(key);
  while (_planOrder.length > 6) {
    _planCache.remove(_planOrder.removeAt(0));
  }
  return rows;
}

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
      // Re-pack rows as real aspect ratios stream in from the background reader.
      child: ValueListenableBuilder<int>(
        valueListenable: AspectStore.instance.aspectRevision,
        builder: (context, rev, _) => LayoutBuilder(
          builder: (context, constraints) {
            final avail = (constraints.maxWidth - _hPad * 2).clamp(1.0, 1e9);
            // Masonry column math (fixed-width columns).
            var cols = ((avail + _spacing) / (st.thumbSize + _spacing)).floor();
            if (cols < 1) cols = 1;
            final cw = (avail - _spacing * (cols - 1)) / cols;
            // Justified-grid target row height (mirrors the old cell intuition,
            // so the thumb-size slider still reads sensibly).
            final targetH = st.thumbSize * 0.72;

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
                padding: const EdgeInsets.fromLTRB(
                    _hPad, PabloSpacing.xl, _hPad, 18),
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
                            imageAspect: aspectFor(photos[i]),
                            showLabel: false,
                          ),
                        ),
                      )
                    : _justifiedSliver(
                        st, section.id, photos, avail, targetH, rev),
              ));
            }

            // Prefetch ~1.5 screens ahead so thumbnails are requested (and
            // cached by the native engine) before they scroll into view.
            return CustomScrollView(cacheExtent: 1200, slivers: slivers);
          },
        ),
      ),
    );
  }

  /// Justified, fixed-row-height grid: every tile in a row shares one height,
  /// widths follow the real aspect ratio (no cropping). Rows are virtualized —
  /// each SliverList child is one row.
  Widget _justifiedSliver(
    PabloAppState st,
    String sectionId,
    List<Photo> photos,
    double avail,
    double targetH,
    int rev,
  ) {
    final rows = _rowPlanFor(sectionId, photos, avail, targetH, _spacing, rev);
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, rowIdx) {
          final r = rows[rowIdx];
          // Fetch real aspects for the photos in (or near) view first.
          AspectStore.instance.prioritize([
            for (var k = 0; k < r.count; k++) photos[r.start + k].filePath,
          ]);
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(bottom: _spacing),
              child: SizedBox(
                height: r.height,
                child: Row(
                  children: [
                    for (var k = 0; k < r.count; k++)
                      Padding(
                        // Key by photo id so a zoom re-pack reconciles tiles by
                        // identity — each tile keeps (or gets a fresh) texture
                        // slot for its OWN photo, instead of a reused element
                        // inheriting the previous occupant's stale frame.
                        key: ValueKey(photos[r.start + k].id),
                        padding: EdgeInsets.only(left: k == 0 ? 0.0 : _spacing),
                        child: SizedBox(
                          width: r.widths[k],
                          child: _thumbCell(
                            st,
                            photos,
                            photos[r.start + k],
                            r.widths[k],
                            // width / height == the aspect the row was packed
                            // at, so PhotoThumb's h = size/imageAspect == r.height.
                            imageAspect: r.widths[k] / r.height,
                            showLabel: false,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
        childCount: rows.length,
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
      // The checkmark toggles selection + tray membership, same as a cmd-click.
      onToggleSelect: () =>
          st.selectPhoto(p.id, ctrl: true, contextPhotoIds: const []),
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
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
        ],
      ),
    );
  }
}
