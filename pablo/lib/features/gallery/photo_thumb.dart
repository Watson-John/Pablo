// PhotoThumb — hover/selected/in-tray states, star indicator, hover-add-to-tray
// + button, optional double-click to open lightbox.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/caption_store.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../editor/edits_store.dart';
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
    this.dragPaths,
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

  /// When non-empty, long-pressing the tile starts a drag carrying these file
  /// paths (the drag selection) for in-app reorganize onto a sidebar folder.
  final List<String>? dragPaths;

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

    final Widget tile = Listener(
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
                              // §11 video cues: a centered play circle (always)
                              // and a duration pill (hidden on hover so it
                              // doesn't fight the add-to-tray "+").
                              if (widget.photo.isVideo) ...[
                                const Positioned.fill(
                                  child: Center(child: _PlayCircle()),
                                ),
                                if (!_hover && widget.photo.durationMs > 0)
                                  Positioned(
                                    bottom: 6,
                                    right: 6,
                                    child: _DurationPill(
                                        ms: widget.photo.durationMs),
                                  ),
                              ],
                              if (widget.photo.starred ||
                                  isStarredAsset(assetIdFor(widget.photo.id)))
                                const Positioned(
                                  top: 6,
                                  left: 6,
                                  child: _StarBadge(),
                                ),
                              // "Edited" badge — a saved non-destructive edit
                              // exists (revertible). Reacts to EditsStore.
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: ListenableBuilder(
                                  listenable: EditsStore.instance,
                                  builder: (context, _) =>
                                      EditsStore.instance.isEdited(
                                              assetIdFor(widget.photo.id))
                                          ? const _EditedBadge()
                                          : const SizedBox.shrink(),
                                ),
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
                              // Caption overlay — a bottom band shown only when
                              // the asset carries a user caption. Reactive to
                              // CaptionStore so it appears as captions stream in.
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _CaptionBand(photoId: widget.photo.id),
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
    if (widget.dragPaths == null || widget.dragPaths!.isEmpty) return tile;
    return LongPressDraggable<List<String>>(
      data: widget.dragPaths!,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(count: widget.dragPaths!.length),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}

/// Floating chip shown under the cursor while dragging photos to a folder.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.lg, vertical: PabloSpacing.sm),
        decoration: BoxDecoration(
          color: PabloColors.accentPrimary,
          borderRadius: PabloRadius.pillAll,
          boxShadow: PabloShadows.md,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PabloIcon(PabloIconName.move,
                size: 14, color: PabloColors.textOnAccent),
            const SizedBox(width: PabloSpacing.sm),
            Text(
              'Move $count photo${count == 1 ? '' : 's'}',
              style: PabloTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PabloColors.textOnAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom caption band over a thumbnail — a dark-to-transparent gradient with
/// one line of the asset's user caption. Renders nothing (zero footprint) when
/// the asset has no caption. Reactive to [CaptionStore.captionRevision] so it
/// appears the moment a caption is read or edited.
class _CaptionBand extends StatelessWidget {
  const _CaptionBand({required this.photoId});
  final String photoId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CaptionStore.instance.captionRevision,
      builder: (context, _, __) {
        final cap = CaptionStore.instance.captionOf(assetIdFor(photoId));
        if (cap == null || cap.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.base,
            vertical: PabloSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.62),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
          child: Text(
            cap,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PabloTypography.sans(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/// Format a duration in ms as m:ss (or h:mm:ss for long clips).
String formatDuration(int ms) {
  final total = (ms / 1000).round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Centered translucent play circle marking a video thumbnail (§11).
class _PlayCircle extends StatelessWidget {
  const _PlayCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
      ),
      child: const PabloIcon(
        PabloIconName.playFill,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

/// A small dark pill showing a video clip's duration (bottom-right of the tile).
class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.ms});
  final int ms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: PabloRadius.smAll,
      ),
      child: Text(
        formatDuration(ms),
        style: PabloTypography.mono(
          fontSize: 9.5,
          color: Colors.white,
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

/// "Edited" badge: a small copper chip with a sparkle glyph marking a photo that
/// carries a saved (reversible) non-destructive edit.
class _EditedBadge extends StatelessWidget {
  const _EditedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: PabloColors.accentPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 1.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const PabloIcon(
        PabloIconName.sparkle,
        size: 10,
        color: PabloColors.textOnAccent,
      ),
    );
  }
}
