// Floating photo tray — a compact, elevated card of tray photos that hovers
// over the bottom of the gallery instead of docking as a fixed-height strip.
// It costs zero vertical space when the tray is empty (renders nothing), and
// its empty surroundings stay click-through so the gallery underneath is fully
// usable. Mounted as a bottom-anchored overlay in the gallery Stack.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/app_state.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_surface.dart';

class FloatingPhotoTray extends StatelessWidget {
  const FloatingPhotoTray({super.key});

  // Card geometry. Thumbnails are a fixed compact size; the card sizes to its
  // content (header + strip) up to a responsive cap, then scrolls horizontally.
  static const double _thumbH = 64;
  static const double _thumbW = 86; // ~4:3 landscape (round(64 * 1.35))
  static const double _gap = PabloSpacing.md;
  static const double _pad = PabloSpacing.lg;
  static const double _absMaxWidth = 760;
  static const double _minWidth = 300;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final ids = st.trayPhotos;
    // Empty tray → no card, no reserved space. The whole point of floating.
    if (ids.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final band = constraints.maxWidth;
        final cap = math.max(240.0, math.min(_absMaxWidth, band * 0.92));
        final innerMax = cap - _pad * 2;
        final n = ids.length;
        final contentW = n * _thumbW + (n - 1) * _gap;
        final fits = contentW <= innerMax;
        final stripW = math.min(contentW, innerMax);
        final minCard = math.min(_minWidth, cap);
        final cardW = (stripW + _pad * 2).clamp(minCard, cap).toDouble();

        return Center(
          // Absorb taps anywhere on the card's footprint (padding, header/strip
          // gap) so a click on the card never falls through to select a photo
          // in the gallery behind it. Interactive children (buttons, remove
          // badges) still win the gesture arena over their own areas.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              width: cardW,
              decoration: BoxDecoration(
                color: PabloColors.backgroundSurface,
                borderRadius: PabloRadius.lgAll,
                border: Border.all(color: PabloColors.borderSubtle),
                boxShadow: PabloShadows.lg,
              ),
              padding: const EdgeInsets.all(_pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(st: st, ids: ids),
                  const SizedBox(height: PabloSpacing.base),
                  _Strip(st: st, ids: ids, fits: fits, width: innerMax),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.st, required this.ids});
  final PabloAppState st;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final selected = st.selectedPhotos.length;
    final Widget label;
    if (selected > 0) {
      label = Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$selected',
            style: PabloTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PabloColors.accentPrimary,
            ),
          ),
          TextSpan(
            text: ' selected',
            style: PabloTypography.sans(
              fontSize: 13,
              color: PabloColors.textSecondary,
            ),
          ),
        ]),
      );
    } else {
      label = Text(
        '${ids.length} photo${ids.length == 1 ? '' : 's'} in tray',
        style: PabloTypography.sans(
          fontSize: 13,
          color: PabloColors.textSecondary,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm),
      child: Row(
        children: [
          Flexible(child: label),
          const SizedBox(width: PabloSpacing.base),
          const Spacer(),
          _LockToggle(locked: st.trayLocked, onToggle: st.toggleTrayLock),
          const SizedBox(width: PabloSpacing.lg),
          if (ids.length >= 2) ...[
            PabloButton(
              label: 'Compare',
              variant: PabloButtonVariant.secondary,
              size: PabloButtonSize.xs,
              onPressed: () => st.openCompare(ids.take(2).toList()),
            ),
            const SizedBox(width: PabloSpacing.lg),
          ],
          PabloButton(
            label: 'Clear',
            variant: PabloButtonVariant.danger,
            size: PabloButtonSize.xs,
            onPressed: st.clearTray,
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.st,
    required this.ids,
    required this.fits,
    required this.width,
  });
  final PabloAppState st;
  final List<String> ids;
  final bool fits; // content fits without scrolling
  final double width; // max strip width when scrolling

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      for (var i = 0; i < ids.length; i++) ...[
        if (i > 0) const SizedBox(width: FloatingPhotoTray._gap),
        _TrayTile(id: ids[i], onRemove: () => st.removeFromTray(ids[i])),
      ],
    ];
    final row = Row(mainAxisSize: MainAxisSize.min, children: tiles);
    if (fits) {
      // Left-align the snug row within the (possibly wider) card.
      return Align(alignment: Alignment.centerLeft, child: row);
    }
    // Clip.none so the remove badges that overhang the first/last tiles aren't
    // shaved off by the scroll viewport.
    return SizedBox(
      width: width,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: row,
      ),
    );
  }
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({required this.id, required this.onRemove});
  final String id;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = photoById(id);
    if (photo == null) {
      return const SizedBox(
        width: FloatingPhotoTray._thumbW,
        height: FloatingPhotoTray._thumbH,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: FloatingPhotoTray._thumbW,
          height: FloatingPhotoTray._thumbH,
          decoration: BoxDecoration(
            borderRadius: PabloRadius.mdAll,
            border: Border.all(color: PabloColors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: PhotoSurface(photo: photo, targetW: 256, targetH: 192),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PabloColors.ignoreRed,
                shape: BoxShape.circle,
                border: Border.all(
                    color: PabloColors.backgroundSurface, width: 1.5),
                boxShadow: PabloShadows.sm,
              ),
              child: const Text(
                '✕',
                style: TextStyle(
                  color: PabloColors.textOnAccent,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockToggle extends StatelessWidget {
  const _LockToggle({required this.locked, required this.onToggle});
  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Tooltip(
          message: locked
              ? 'Unlock selection (clicks will deselect)'
              : 'Lock selection (clicks won\'t deselect)',
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: locked
                  ? PabloColors.accentPrimary
                  : PabloColors.backgroundSurfaceAlt,
              shape: BoxShape.circle,
              border: Border.all(
                color: locked
                    ? PabloColors.accentPrimary
                    : PabloColors.borderStrong,
              ),
            ),
            child: PabloIcon(
              locked ? PabloIconName.lock : PabloIconName.unlock,
              size: 15,
              color:
                  locked ? PabloColors.textOnAccent : PabloColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
