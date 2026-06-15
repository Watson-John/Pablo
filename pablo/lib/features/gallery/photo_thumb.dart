// PhotoThumb — hover/selected/in-tray states, star indicator, hover-add-to-tray
// + button, optional double-click to open lightbox.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../backend/native_backend.dart';
import '../../theme/tokens.dart';

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
      ] else if (_hover) ...PabloShadows.md
      else ...PabloShadows.sm,
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
            if (_lastPointerEvent != null) widget.onTap?.call(_lastPointerEvent!);
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
                    AnimatedContainer(
                      duration: PabloDurations.hover,
                      width: widget.size,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: PabloRadius.lgAll,
                        border: Border.all(color: borderColor),
                        boxShadow: shadows,
                      ),
                      child: ClipRRect(
                        borderRadius: PabloRadius.lgAll,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _ThumbBackdrop(photo: widget.photo),
                            ),
                            if (widget.photo.starred)
                              const Positioned(
                                bottom: 5,
                                left: 5,
                                child: PabloIcon(
                                  PabloIconName.starFill,
                                  size: 13,
                                  color: PabloColors.amber,
                                ),
                              ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: overlayCheck(),
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

/// Renders the thumbnail's pixel surface. When the native backend is
/// available, routes through a [TextureSlot] (a Texture widget backed by
/// photo_core). Otherwise renders the original linear gradient as the
/// M0 mockup did. Border + shadow + overlays live in PhotoThumb above.
class _ThumbBackdrop extends StatelessWidget {
  const _ThumbBackdrop({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: photo.gradient),
      );
    }
    return _NativeThumbSurface(
      photo: photo,
      engine: backend.engine,
      events: backend.events,
    );
  }
}

/// Stateful surface that owns a [TextureSlot] for its lifetime. Rebinds
/// the slot generation when the photo identity changes and publishes a
/// representative solid color (computed from the source gradient) via the
/// M1 test hook. M2 replaces the publish with a real decode request.
class _NativeThumbSurface extends StatefulWidget {
  const _NativeThumbSurface({
    required this.photo,
    required this.engine,
    required this.events,
  });

  final Photo photo;
  final Engine engine;
  final Stream<PhotoEvent> events;

  @override
  State<_NativeThumbSurface> createState() => _NativeThumbSurfaceState();
}

class _NativeThumbSurfaceState extends State<_NativeThumbSurface> {
  TextureSlot? _slot;
  String? _requestedPhotoId;
  int _inFlightRequestId = 0;
  bool _disposed = false;

  // Real decoded-frame dimensions for the current photo, learned from
  // STAGE_READY events. Drives the cover-fit so the texture fills its tile
  // without distortion. Null until the first frame for this photo lands.
  int? _frameW;
  int? _frameH;
  StreamSubscription<PhotoEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _createSlot();
  }

  Future<void> _createSlot() async {
    final slot = await TextureSlot.create(
      widget.engine,
      initialW: 64,
      initialH: 64,
    );
    if (_disposed) {
      await slot.dispose();
      return;
    }
    // Listen for this slot's stage-ready events to capture the decoded frame's
    // real dimensions. Stale-generation events (from a recycled tile's prior
    // photo) are dropped by the generation check.
    _sub = widget.events.listen((e) {
      if (e.kind != PhotoEventKind.stageReady) return;
      final s = _slot;
      if (s == null || e.slotId != s.slotId) return;
      if (e.generation != s.currentGeneration) return;
      if (e.width <= 0 || e.height <= 0) return;
      if (e.width == _frameW && e.height == _frameH) return;
      if (mounted) {
        setState(() {
          _frameW = e.width;
          _frameH = e.height;
        });
      }
    });
    setState(() => _slot = slot);
    _submitRequestForCurrentPhoto();
  }

  @override
  void didUpdateWidget(covariant _NativeThumbSurface old) {
    super.didUpdateWidget(old);
    if (_slot != null && old.photo.id != widget.photo.id) {
      // Cancel the previous in-flight request (advisory; even if it lands
      // first, generation-token check in the engine drops the stale result).
      if (_inFlightRequestId != 0) {
        widget.engine.cancelRequest(_inFlightRequestId);
        _inFlightRequestId = 0;
      }
      _slot!.rebind();
      _requestedPhotoId = null;
      // New photo: the previous photo's dimensions no longer apply. Reset so
      // we fill the tile until the new photo's first frame reports its size.
      _frameW = null;
      _frameH = null;
      _submitRequestForCurrentPhoto();
    }
  }

  void _submitRequestForCurrentPhoto() {
    final slot = _slot;
    if (slot == null) return;
    if (_requestedPhotoId == widget.photo.id) return;
    // assetId is a stable per-photo number derived from the id string.
    // Real asset ids come from the catalog in M3.
    final assetId = widget.photo.id.hashCode.abs();
    _inFlightRequestId = widget.engine.requestThumbnail(
      assetId: assetId,
      slotId: slot.slotId,
      generation: slot.currentGeneration,
      // Real file path drives the M3 libvips decode; falls back to the
      // synthetic id (M2 solid color) for gradient-mock photos.
      path: widget.photo.filePath ?? widget.photo.id,
      targetW: 256,
      targetH: 256,
    );
    _requestedPhotoId = widget.photo.id;
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    if (_inFlightRequestId != 0) {
      widget.engine.cancelRequest(_inFlightRequestId);
    }
    _slot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    if (slot == null) {
      // Brief gap during async slot creation — fall back to gradient so
      // there's no black flash.
      return DecoratedBox(
        decoration: BoxDecoration(gradient: widget.photo.gradient),
      );
    }
    final texture = Texture(textureId: slot.textureId);
    final fw = _frameW, fh = _frameH;
    if (fw == null || fh == null) {
      // Dimensions not yet known — fill the tile (matches prior behavior).
      return texture;
    }
    // Cover-fit the decoded frame into the tile: scale to fill preserving the
    // photo's real aspect, center-crop the overflow. In masonry the tile
    // already matches this aspect, so nothing is cropped; in the uniform grid
    // the photo is cropped to the cell instead of stretched.
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: fw.toDouble(),
          height: fh.toDouble(),
          child: texture,
        ),
      ),
    );
  }
}
