// EditPreviewSurface — the lightbox main image while the editor is open.
//
// Listens to the [EditSession] and renders a live, debounced preview of the
// working spec through the native re-render path (PhotoSurface.previewSpec →
// NativeAssetTexture → previewEdits). One implementation of the edit math, so
// the preview is exactly what a Save will persist.
//
// Key this widget by photo id so it is recreated when the lightbox navigates to
// a different asset (which is when EditSessionProvider swaps the session).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import '../gallery/photo_surface.dart';
import 'edit_session.dart';

class EditPreviewSurface extends StatefulWidget {
  const EditPreviewSurface({
    required this.photo,
    this.targetW = 1280,
    this.targetH = 1280,
    super.key,
  });

  final Photo photo;
  final int targetW;
  final int targetH;

  @override
  State<EditPreviewSurface> createState() => _EditPreviewSurfaceState();
}

class _EditPreviewSurfaceState extends State<EditPreviewSurface> {
  EditSession? _session;
  String _spec = '';
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // read() (no dependency) — we drive rebuilds ourselves via the listener so
    // we can debounce; the widget is keyed by photo id, so a session swap on
    // navigation recreates this State and re-reads the current session here.
    final s = EditSessionScope.read(context);
    if (!identical(s, _session)) {
      _session?.removeListener(_onSessionChanged);
      _session = s;
      _session?.addListener(_onSessionChanged);
      _spec = _previewEncode();
    }
  }

  // While the Crop tool is active, preview the image WITHOUT the crop so the
  // crop overlay can draw its rect over the full (rotated/straightened) frame;
  // the crop bakes in once the tool is dismissed (or on Save).
  String _previewEncode() {
    final s = _session;
    if (s == null) return '';
    if (s.activeTool == 'crop') {
      final clone = s.spec.clone()
        ..cropL = 0
        ..cropT = 0
        ..cropW = 1
        ..cropH = 1;
      return clone.encode();
    }
    return s.encoded;
  }

  void _onSessionChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 45), () {
      final next = _previewEncode();
      if (next != _spec && mounted) setState(() => _spec = next);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PhotoSurface(
      photo: widget.photo,
      targetW: widget.targetW,
      targetH: widget.targetH,
      previewSpec: _spec,
    );
  }
}
