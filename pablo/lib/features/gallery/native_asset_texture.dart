// NativeAssetTexture — renders an asset's decoded pixels through a photo_core
// [TextureSlot], optionally cropped to a normalized sub-rect.
//
// Owns a slot for its lifetime, requests a thumbnail for (assetId, path),
// learns the decoded frame's real dimensions from STAGE_READY events, and
// rebinds when the asset identity changes. With [crop] null it cover-fits the
// whole frame into the tile (the gallery thumbnail). With [crop] set it shows
// just that sub-rect scaled to cover the tile (a face crop). Extracted from
// the original _NativeThumbSurface so PhotoThumb and FaceThumb share one place
// that knows how an assetId becomes a Texture.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

class NativeAssetTexture extends StatefulWidget {
  const NativeAssetTexture({
    required this.engine,
    required this.events,
    required this.assetId,
    required this.path,
    this.crop,
    required this.fallback,
    this.targetW = 256,
    this.targetH = 256,
    this.contentRev = 0,
    this.previewSpec,
    super.key,
  });

  final Engine engine;
  final Stream<PhotoEvent> events;
  final int assetId;
  final String path;

  /// The asset's saved-edit content_rev. When it changes the slot rebinds and
  /// re-requests, so a saved edit repaints an already-displayed tile (the
  /// freshly-served frame carries the native-applied edit). 0 = unedited.
  final int contentRev;

  /// When non-null and non-empty, render this TRANSIENT edit spec via
  /// `previewEdits` instead of the cached thumbnail request — live editor
  /// preview. Empty/null falls back to the normal request (original / saved).
  final String? previewSpec;

  /// Normalized [0,1) sub-rect of the source image to show. Null = whole image
  /// (cover-fit). Set = crop to this rect, scaled to cover the tile.
  final Rect? crop;

  /// Shown before the slot exists or the frame dimensions are known (and, when
  /// cropping, until both are available so the crop math is correct).
  final Widget fallback;

  final int targetW;
  final int targetH;

  @override
  State<NativeAssetTexture> createState() => _NativeAssetTextureState();
}

class _NativeAssetTextureState extends State<NativeAssetTexture> {
  TextureSlot? _slot;
  int _inFlightRequestId = 0;
  bool _disposed = false;
  int? _frameW;
  int? _frameH;
  StreamSubscription<PhotoEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _createSlot();
  }

  Future<void> _createSlot() async {
    final TextureSlot slot;
    try {
      slot =
          await TextureSlot.create(widget.engine, initialW: 64, initialH: 64);
    } catch (e) {
      // Slot/texture registration failed (e.g. the platform registrar). Degrade
      // to the fallback surface rather than throwing an uncaught zone error.
      if (!_disposed) debugPrint('[pablo] texture slot create failed: $e');
      return;
    }
    if (_disposed) {
      await slot.dispose();
      return;
    }
    _sub = widget.events.listen((e) {
      if (e.kind != PhotoEventKind.stageReady) return;
      final s = _slot;
      if (s == null || e.slotId != s.slotId) return;
      if (e.generation != s.currentGeneration) return;
      if (e.width <= 0 || e.height <= 0) return;
      // A new frame was published. Force the embedder to re-copy the texture,
      // even when the dimensions are unchanged (e.g. a same-size stage upgrade
      // or a cache-hit re-publish). Without this a stale, lower-resolution
      // frame lingers until the next layout change forces a re-composite —
      // which is the "stays pixelated until you zoom again" symptom.
      s.markFrameAvailable();
      if (e.width == _frameW && e.height == _frameH) return;
      if (mounted) {
        setState(() {
          _frameW = e.width;
          _frameH = e.height;
        });
      }
    });
    setState(() => _slot = slot);
    _submitRequest();
  }

  @override
  void didUpdateWidget(covariant NativeAssetTexture old) {
    super.didUpdateWidget(old);
    final slot = _slot;
    if (slot == null) return;
    final assetChanged =
        old.assetId != widget.assetId || old.path != widget.path;
    final revChanged = old.contentRev != widget.contentRev;
    final previewChanged = old.previewSpec != widget.previewSpec;
    if (assetChanged || revChanged) {
      if (_inFlightRequestId != 0) {
        widget.engine.cancelRequest(_inFlightRequestId);
        _inFlightRequestId = 0;
      }
      slot.rebind(); // fresh generation drops any stale in-flight frame
      if (assetChanged) {
        // Only a different asset can change the frame dimensions; a same-asset
        // rev/preview change keeps them, so don't flash the fallback.
        _frameW = null;
        _frameH = null;
      }
      _submitRequest();
    } else if (previewChanged) {
      // Bump the generation so a late frame from the PRIOR (now-superseded)
      // preview spec is dropped by the STAGE_READY generation guard — preview
      // jobs don't carry a cancellable request id, and rapid slider drags issue
      // them ~45ms apart, so without this an out-of-order frame could clobber
      // the latest edit. rebind() keeps the current frame (no flash).
      slot.rebind();
      _submitRequest();
    }
  }

  void _submitRequest() {
    final slot = _slot;
    if (slot == null) return;
    final ps = widget.previewSpec;
    if (ps != null) {
      // Live editor preview: render the WORKING spec straight to the slot. A
      // non-null-but-empty spec is the editor showing the *original* (working
      // spec reset to identity) — distinct from a null previewSpec (gallery /
      // filmstrip), which uses the cached request that applies the SAVED edit.
      widget.engine.previewEdits(
        slotId: slot.slotId,
        generation: slot.currentGeneration,
        path: widget.path,
        targetW: widget.targetW,
        targetH: widget.targetH,
        spec: ps,
      );
      _inFlightRequestId = 0;
      return;
    }
    _inFlightRequestId = widget.engine.requestThumbnail(
      assetId: widget.assetId,
      slotId: slot.slotId,
      generation: slot.currentGeneration,
      path: widget.path,
      targetW: widget.targetW,
      targetH: widget.targetH,
    );
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
    if (slot == null) return widget.fallback;
    final texture = Texture(textureId: slot.textureId);
    final fw = _frameW, fh = _frameH;

    final crop = widget.crop;
    if (crop == null) {
      // Until the real frame dimensions arrive (initial load, or just after a
      // rebind to a different asset), show the neutral fallback rather than the
      // raw texture — the latter fills the tile and visibly stretches whatever
      // frame the slot still holds.
      if (fw == null || fh == null) return widget.fallback;
      // Cover-fit the whole frame, center-cropping overflow.
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

    // Cropping needs the real frame size to map the normalized box to pixels.
    if (fw == null || fh == null) return widget.fallback;
    return LayoutBuilder(
      builder: (context, constraints) {
        final ow = constraints.maxWidth;
        final oh = constraints.maxHeight;
        final fwd = fw.toDouble(), fhd = fh.toDouble();
        final cropPxW = (crop.width * fwd).clamp(1.0, fwd);
        final cropPxH = (crop.height * fhd).clamp(1.0, fhd);
        // Scale the crop to cover the tile.
        final scale =
            (ow / cropPxW) > (oh / cropPxH) ? ow / cropPxW : oh / cropPxH;
        final displayW = fwd * scale;
        final displayH = fhd * scale;
        // Center the crop's center on the tile's center.
        final dx = ow / 2 - (crop.left + crop.width / 2) * fwd * scale;
        final dy = oh / 2 - (crop.top + crop.height / 2) * fhd * scale;
        return ClipRect(
          child: SizedBox(
            width: ow,
            height: oh,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: dx,
                  top: dy,
                  width: displayW,
                  height: displayH,
                  child: texture,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
