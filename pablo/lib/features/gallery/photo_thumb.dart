// PhotoThumb — hover/selected/in-tray states, star indicator, hover-add-to-tray
// + button, optional double-click to open lightbox.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import 'photo_surface.dart';

class PhotoThumb extends StatefulWidget {
  const PhotoThumb({
    required this.photo,
    required this.size,
    required this.selected,
    required this.inTray,
    this.imageAspect,
    this.showLabel = true,
    this.onTap,
    this.onDoubleTap,
    this.onAddToTray,
    this.onToggleSelect,
    this.onSecondaryTap,
    super.key,
  });

  final Photo photo;
  final double size;
  final bool selected;
  final bool inTray;

  /// Image aspect ratio (width / height). When null the thumb uses the fixed
  /// 0.72 footprint (uniform grid). The masonry view passes a per-photo ratio
  /// so tiles vary in height.
  final double? imageAspect;

  /// Whether to render the filename caption under the image. Off in masonry,
  /// where tight tiles read better without captions.
  final bool showLabel;
  final void Function(PointerDownEvent event)? onTap;
  final void Function()? onDoubleTap;
  final void Function()? onAddToTray;

  /// Tapping the selection checkmark toggles the photo's selection (and tray)
  /// membership — the same as a ctrl/cmd-click.
  final void Function()? onToggleSelect;
  final void Function(Offset globalPosition)? onSecondaryTap;

  @override
  State<PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends State<PhotoThumb> {
  bool _hover = false;
  PointerDownEvent? _lastPointerEvent;

  @override
  Widget build(BuildContext context) {
    final h = widget.imageAspect != null
        ? widget.size / widget.imageAspect!
        : widget.size * 0.72;
    // Corner radius scales with tile height so the rounding doesn't eat into
    // small thumbnails (and stays at the standard radius for large ones).
    final tileRadius =
        BorderRadius.circular((h * 0.09).clamp(4.0, PabloRadius.lg).toDouble());
    final borderColor = (widget.selected || widget.inTray)
        ? PabloColors.selectionPrimary.withValues(alpha: 0.4)
        : PabloColors.borderSubtle;
    final shadows = <BoxShadow>[
      if (widget.selected) ...[
        BoxShadow(
          color: PabloColors.selectionPrimary.withValues(alpha: 0.18),
          spreadRadius: 3,
          blurRadius: 0,
        ),
        BoxShadow(
          color: PabloColors.selectionPrimary.withValues(alpha: 0.28),
          blurRadius: 18,
        ),
      ] else if (widget.inTray) ...[
        BoxShadow(
          color: PabloColors.selectionPrimary.withValues(alpha: 0.18),
          spreadRadius: 3,
        ),
        BoxShadow(
          color: PabloColors.selectionPrimary.withValues(alpha: 0.28),
          blurRadius: 18,
        ),
      ] else if (_hover)
        ...PabloShadows.md
      else
        ...PabloShadows.sm,
    ];

    Widget overlayCheck() {
      if (widget.selected || widget.inTray) {
        return Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: PabloColors.selectionPrimary,
            shape: BoxShape.circle,
          ),
          child: const Text(
            '✓',
            style: TextStyle(
              color: PabloColors.textOnAccent,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1,
            ),
          ),
        );
      }
      if (_hover) {
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Listener(
      onPointerDown: (e) {
        _lastPointerEvent = e;
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kSecondaryMouseButton) {
          widget.onSecondaryTap?.call(e.position);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_lastPointerEvent != null) {
              widget.onTap?.call(_lastPointerEvent!);
            }
          },
          onDoubleTap: widget.onDoubleTap,
          child: AnimatedScale(
            duration: PabloDurations.hover,
            scale: widget.selected ? 1.0 : (_hover ? 1.0 : 1.0),
            child: AnimatedSlide(
              duration: PabloDurations.hover,
              offset: widget.selected
                  ? const Offset(0, -0.02)
                  : (_hover ? const Offset(0, -0.01) : Offset.zero),
              child: SizedBox(
                width: widget.size,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // SizedBox sizes the tile instantly; the AnimatedContainer
                    // animates only the decoration (hover/select shadow+border).
                    // Animating the SIZE would briefly overflow its row slot
                    // when the justified grid re-packs as aspect ratios load.
                    SizedBox(
                      width: widget.size,
                      height: h,
                      child: AnimatedContainer(
                        duration: PabloDurations.hover,
                        decoration: BoxDecoration(
                          borderRadius: tileRadius,
                          border: Border.all(color: borderColor),
                          boxShadow: shadows,
                        ),
                        child: ClipRRect(
                          borderRadius: tileRadius,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: PhotoSurface(photo: widget.photo),
                              ),
                              if (widget.photo.starred ||
                                  isStarredAsset(assetIdFor(widget.photo.id)))
                                const Positioned(
                                  top: 6,
                                  left: 6,
                                  child: _StarBadge(),
                                ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.onToggleSelect,
                                  child: overlayCheck(),
                                ),
                              ),
                              if (_hover && !widget.inTray)
                                Positioned(
                                  bottom: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: widget.onAddToTray,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: PabloShadows.sm,
                                      ),
                                      child: const Text(
                                        '+',
                                        style: TextStyle(
                                          color: PabloColors.textSecondary,
                                          fontSize: 13,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.showLabel && widget.size >= 80) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.photo.label,
                        overflow: TextOverflow.ellipsis,
                        style: PabloTypography.mono(fontSize: 10.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Starred-photo badge (design StarBadge, "outlined" style): an amber filled
/// star with a thin white rim + soft shadow so it reads on any photo.
class _StarBadge extends StatelessWidget {
  const _StarBadge();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // White rim behind, with a soft drop shadow for contrast.
        PabloIcon(
          PabloIconName.starFill,
          size: 14.5,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 1.5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        const PabloIcon(
          PabloIconName.starFill,
          size: 13,
          color: PabloColors.amber,
        ),
      ],
    );
  }
}
