// LightboxView — dark surface, filmstrip, arrow nav, EXIF strip.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_native/photo_native.dart';

import '../../components/pablo_icon.dart';
import '../../data/caption_store.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../editor/crop_overlay.dart';
import '../editor/retouch_overlay.dart';
import '../editor/edit_preview_surface.dart';
import '../editor/edit_session.dart';
import '../people/face_naming.dart';
import '../people/people_scope.dart';
import 'photo_surface.dart';

class LightboxView extends StatefulWidget {
  const LightboxView({
    required this.photos,
    required this.initialId,
    required this.onClose,
    this.fullscreen = false,
    this.onToggleFullscreen,
    this.onCurrentChanged,
    super.key,
  });

  final List<Photo> photos;
  final String initialId;
  final VoidCallback onClose;

  /// Fired when navigation changes the viewed photo, so the host can keep the
  /// edit panel + EditSession pointed at the image on screen.
  final ValueChanged<String>? onCurrentChanged;

  /// Immersive edge-to-edge mode: the top bar, filmstrip, and caption bar
  /// auto-hide (reveal on mouse-move); only the image + nav arrows remain.
  final bool fullscreen;

  /// Toggles immersive mode (the `F` key + the toolbar button). When null the
  /// fullscreen control is hidden.
  final VoidCallback? onToggleFullscreen;

  @override
  State<LightboxView> createState() => _LightboxViewState();
}

class _LightboxViewState extends State<LightboxView> {
  late String _currentId = widget.initialId;
  final FocusNode _focus = FocusNode();
  final ScrollController _filmCtl = ScrollController();

  // Immersive-mode chrome auto-hide.
  bool _chromeVisible = true;
  Timer? _hideTimer;

  void _revealChrome() {
    if (!widget.fullscreen) return;
    _hideTimer?.cancel();
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.fullscreen) setState(() => _chromeVisible = false);
    });
  }

  @override
  void didUpdateWidget(covariant LightboxView old) {
    super.didUpdateWidget(old);
    if (widget.fullscreen && !old.fullscreen) {
      _revealChrome(); // entered fullscreen: show chrome, then fade it out
    } else if (!widget.fullscreen && old.fullscreen) {
      _hideTimer?.cancel();
      _chromeVisible = true;
    }
  }

  // The photos list can be tens of thousands long for a flat folder, so build()
  // resolves the current index once into a local. This getter is only for the
  // navigation handlers (one scan per key/scroll event, not per build).
  int get _idx => widget.photos
      .indexWhere((p) => p.id == _currentId)
      .clamp(0, widget.photos.length - 1);

  void _goTo(int idx) {
    final c = idx.clamp(0, widget.photos.length - 1);
    setState(() => _currentId = widget.photos[c].id);
    widget.onCurrentChanged?.call(_currentId);
    // Scroll filmstrip to keep current centered.
    final offset = c * 77.0 - 200;
    if (_filmCtl.hasClients) {
      _filmCtl.animateTo(
        offset.clamp(0.0, _filmCtl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goTo(_idx + 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goTo(_idx - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyF &&
        widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!();
      return KeyEventResult.handled;
    }
    // Escape is handled via CallbackShortcuts (the Actions layer) rather than
    // here — Focus.onKeyEvent doesn't reliably receive Escape on desktop.
    return KeyEventResult.ignored;
  }

  void _onEscape() {
    // Exit fullscreen first, then close on a second press.
    if (widget.fullscreen && widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!();
    } else {
      widget.onClose();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    _filmCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final idx = widget.photos
        .indexWhere((p) => p.id == _currentId)
        .clamp(0, widget.photos.length - 1);
    final photo = widget.photos[idx];
    final exif = getPhotoExif(photo.id);
    final exifLine = [
      exif.camera,
      exif.aperture,
      exif.shutter,
      exif.iso != null ? 'ISO ${exif.iso}' : null,
    ].whereType<String>().join(' · ');
    final hasPrev = idx > 0;
    final hasNext = idx < widget.photos.length - 1;
    // Faces detected in this photo (empty if it hasn't been scanned), drawn as
    // hover-to-name boxes over the big image.
    final pc = PeopleScope.of(context);
    // Ignored faces are hidden from the lightbox overlay (manage them in the
    // info-panel People tab).
    final faces =
        pc.facesForAsset(assetIdFor(photo.id)).where((f) => !f.ignored).toList();
    // In immersive mode the chrome (top bar, filmstrip, caption) auto-hides.
    final showChrome = !widget.fullscreen || _chromeVisible;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      },
      child: Focus(
        focusNode: _focus,
        // Grab keyboard focus as soon as this instance mounts. The windowed and
        // fullscreen lightbox live in different parts of the tree, so toggling
        // fullscreen disposes one LightboxView and mounts another — autofocus
        // ensures the fresh instance owns the keyboard (Esc / F / arrows)
        // without racing a post-frame requestFocus.
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _revealChrome(),
          child: Container(
            color: PabloColors.lightboxBackground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showChrome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      PabloSpacing.xxl,
                      PabloSpacing.lg,
                      PabloSpacing.xxl,
                      PabloSpacing.md,
                    ),
                    child: Row(
                      children: [
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: widget.onClose,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: PabloSpacing.xxl,
                              ),
                              height: 32,
                              decoration: BoxDecoration(
                                color: PabloColors.selectionPrimary,
                                borderRadius: PabloRadius.pillAll,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const PabloIcon(
                                    PabloIconName.arrowLeft,
                                    size: 14,
                                    color: PabloColors.textOnAccent,
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    'Back',
                                    style: PabloTypography.sans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: PabloColors.textOnAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: PabloSpacing.xl),
                        Text(
                          photo.label,
                          style: PabloTypography.mono(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(width: PabloSpacing.xl),
                        Expanded(
                          child: Text(
                            exifLine,
                            overflow: TextOverflow.ellipsis,
                            style: PabloTypography.sans(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.28),
                            ),
                          ),
                        ),
                        Text(
                          '${idx + 1} / ${widget.photos.length}',
                          style: PabloTypography.mono(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        if (widget.onToggleFullscreen != null) ...[
                          const SizedBox(width: PabloSpacing.xl),
                          _FullscreenButton(
                            fullscreen: widget.fullscreen,
                            onTap: widget.onToggleFullscreen!,
                          ),
                        ],
                      ],
                    ),
                  ),

                // Filmstrip
                if (showChrome)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PabloSpacing.xxl,
                      vertical: PabloSpacing.base,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      height: 52,
                      child: Stack(
                        children: [
                          ListView.separated(
                            controller: _filmCtl,
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.photos.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 5),
                            itemBuilder: (_, i) {
                              final p = widget.photos[i];
                              final current = p.id == _currentId;
                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => _goTo(i),
                                  child: AnimatedScale(
                                    scale: current ? 1.08 : 1.0,
                                    duration: PabloDurations.hover,
                                    child: Container(
                                      width: 72,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        borderRadius: PabloRadius.mdAll,
                                        border: Border.all(
                                          color: current
                                              ? PabloColors.selectionPrimary
                                              : PabloColors.borderSubtle,
                                          width: 2,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: PhotoSurface(
                                          photo: p, targetW: 144, targetH: 104),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Edge fades so thumbnails dissolve into the chrome.
                          const Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child:
                                IgnorePointer(child: _FilmEdgeFade(left: true)),
                          ),
                          const Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                                child: _FilmEdgeFade(left: false)),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Main image
                Expanded(
                  child: Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        _goTo(_idx + (e.scrollDelta.dy > 0 ? 1 : -1));
                      }
                    },
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: PabloSpacing.xxxxl,
                          ),
                          child: _LightboxImage(
                            photo: photo,
                            faces: faces,
                            imgW: exif.width,
                            imgH: exif.height,
                          ),
                        ),
                        if (hasPrev)
                          _navArrow(
                              alignment: Alignment.centerLeft,
                              icon: PabloIconName.arrowLeft,
                              onTap: () => _goTo(_idx - 1)),
                        if (hasNext)
                          _navArrow(
                              alignment: Alignment.centerRight,
                              icon: PabloIconName.arrowRight,
                              onTap: () => _goTo(_idx + 1)),
                      ],
                    ),
                  ),
                ),

                // Editable caption bar (Picasa-style "Make a caption!"). Fresh state
                // per photo so navigating away cancels any in-progress edit. Part of
                // the chrome that auto-hides in immersive mode.
                if (showChrome)
                  _CaptionBar(
                    key: ValueKey('cap-${photo.id}'),
                    assetId: assetIdFor(photo.id),
                    parentFocus: _focus,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navArrow({
    required Alignment alignment,
    required PabloIconName icon,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xxl),
        child: _NavArrowButton(icon: icon, onTap: onTap),
      ),
    );
  }
}

/// The big image, sized to the photo's true aspect (so the whole frame shows),
/// with one hover-to-name marker per detected face overlaid on top. Falls back
/// to a 4:3 frame with no markers when the source dimensions aren't known.
class _LightboxImage extends StatelessWidget {
  const _LightboxImage({
    required this.photo,
    required this.faces,
    required this.imgW,
    required this.imgH,
  });

  final Photo photo;
  final List<FaceRow> faces;
  final int imgW;
  final int imgH;

  @override
  Widget build(BuildContext context) {
    // Depend on the edit session so the box re-sizes as geometry changes.
    final session = EditSessionScope.of(context);
    final spec = session?.spec;
    final cropMode = session?.activeTool == 'crop';
    final retouchMode =
        session?.activeTool == 'redeye' || session?.activeTool == 'heal';
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 900.0;
      final maxH = c.maxHeight.isFinite ? c.maxHeight : 700.0;
      final known = imgW > 0 && imgH > 0;
      // Aspect after rotation (the space the crop overlay maps over)…
      double rotAspect = known ? imgW / imgH : 4 / 3;
      if (spec != null && spec.rot90 % 2 == 1) rotAspect = 1 / rotAspect;
      // …and the displayed-box aspect, which also folds in the crop unless we're
      // actively cropping (then we show the full uncropped frame).
      var aspect = rotAspect;
      if (spec != null &&
          !cropMode &&
          spec.cropW > 0 &&
          (spec.cropW != 1 || spec.cropH != 1)) {
        aspect *= spec.cropW / spec.cropH;
      }
      // Contain the image at that aspect within the available area.
      var dW = maxW;
      var dH = dW / aspect;
      if (dH > maxH) {
        dH = maxH;
        dW = dH * aspect;
      }
      final showFaces = known &&
          !cropMode &&
          !retouchMode &&
          (spec == null || !spec.hasGeometry);
      return Center(
        child: SizedBox(
          width: dW,
          height: dH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: PabloRadius.lgAll,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.7),
                        offset: const Offset(0, 8),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    // The main image renders the live edit preview when an
                    // EditSession is in scope (editor open); otherwise it shows
                    // the saved/original frame. Keyed by id so navigation
                    // recreates it against the freshly-swapped session.
                    child: EditPreviewSurface(
                      key: ValueKey(photo.id),
                      photo: photo,
                      targetW: 1280,
                      targetH: 1280,
                    ),
                  ),
                ),
              ),
              if (cropMode && session != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    child: CropOverlay(
                        session: session, imageAspect: rotAspect),
                  ),
                ),
              if (retouchMode && session != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: PabloRadius.lgAll,
                    child: RetouchOverlay(
                        session: session, tool: session.activeTool!),
                  ),
                ),
              if (showFaces)
                for (final f in faces)
                  Positioned(
                    left: (f.boxX / imgW) * dW,
                    top: (f.boxY / imgH) * dH,
                    width: (f.boxW / imgW) * dW,
                    height: (f.boxH / imgH) * dH,
                    child: _FaceMarker(face: f),
                  ),
            ],
          ),
        ),
      );
    });
  }
}

/// One face box on the lightbox image: a faint always-on outline (so faces are
/// discoverable), brightening on hover and revealing the name / "Name…" bar.
class _FaceMarker extends StatefulWidget {
  const _FaceMarker({required this.face});
  final FaceRow face;

  @override
  State<_FaceMarker> createState() => _FaceMarkerState();
}

class _FaceMarkerState extends State<_FaceMarker> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pc = PeopleScope.read(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _hover
                      ? PabloColors.selectionPrimary
                      : Colors.white.withValues(alpha: 0.4),
                  width: 2,
                ),
                borderRadius: PabloRadius.smAll,
              ),
            ),
          ),
          // The naming field (rounded, matching the Unnamed Faces cards) sits at
          // the box's bottom edge — inside the hover region so it isn't
          // dismissed before it can be clicked. Shown on hover; persists while
          // focused (so the suggestion dropdown is usable).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FaceNameOverlay(
              face: widget.face,
              controller: pc,
              hovered: _hover,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightbox prev/next arrow — borderless gray glyph that brightens into a dark
/// well on hover (Pablo v4).
class _NavArrowButton extends StatefulWidget {
  const _NavArrowButton({required this.icon, required this.onTap});
  final PabloIconName icon;
  final VoidCallback onTap;
  @override
  State<_NavArrowButton> createState() => _NavArrowButtonState();
}

class _NavArrowButtonState extends State<_NavArrowButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: PabloDurations.hover,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? PabloColors.lightboxNavHoverBg : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: PabloIcon(
            widget.icon,
            size: 20,
            color: _hover
                ? PabloColors.lightboxNavHoverIcon
                : PabloColors.lightboxNavIcon,
          ),
        ),
      ),
    );
  }
}

/// Lightbox top-bar fullscreen toggle — borderless glyph that brightens into a
/// dark well on hover, mirroring [_NavArrowButton].
class _FullscreenButton extends StatefulWidget {
  const _FullscreenButton({required this.fullscreen, required this.onTap});
  final bool fullscreen;
  final VoidCallback onTap;
  @override
  State<_FullscreenButton> createState() => _FullscreenButtonState();
}

class _FullscreenButtonState extends State<_FullscreenButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.fullscreen ? 'Exit Fullscreen (F)' : 'Fullscreen (F)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: PabloDurations.hover,
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  _hover ? PabloColors.lightboxNavHoverBg : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: PabloIcon(
              widget.fullscreen ? PabloIconName.zoomOut : PabloIconName.zoomIn,
              size: 16,
              color: _hover
                  ? PabloColors.lightboxNavHoverIcon
                  : PabloColors.lightboxNavIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Editable caption bar at the bottom of the lightbox (Picasa "Make a
/// caption!"). Click to type; Enter or click-away saves to the catalog via
/// [CaptionStore]; Esc cancels. Shows a muted "Add a caption…" affordance when
/// the photo has none.
class _CaptionBar extends StatefulWidget {
  const _CaptionBar({required this.assetId, this.parentFocus, super.key});
  final int assetId;

  /// The lightbox's keyboard-focus node. Reclaimed when an edit ends so the
  /// lightbox's Esc / F / arrow shortcuts work again after captioning.
  final FocusNode? parentFocus;

  @override
  State<_CaptionBar> createState() => _CaptionBarState();
}

class _CaptionBarState extends State<_CaptionBar> {
  bool _editing = false;
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ensure the caption is read even when the lightbox is opened directly on a
    // photo that never scrolled through the grid.
    CaptionStore.instance.prioritize([widget.assetId]);
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEdit(String current) {
    _ctl.text = current;
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: current.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (!_editing) return;
    CaptionStore.instance.setCaption(widget.assetId, _ctl.text.trim());
    setState(() => _editing = false);
    widget.parentFocus?.requestFocus();
  }

  void _cancel() {
    setState(() => _editing = false);
    widget.parentFocus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CaptionStore.instance.captionRevision,
      builder: (context, _, __) {
        final cap = CaptionStore.instance.captionOf(widget.assetId) ?? '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxl,
            vertical: PabloSpacing.lg,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          alignment: Alignment.center,
          child: _editing ? _field() : _display(cap),
        );
      },
    );
  }

  Widget _field() {
    // Escape cancels the edit. This CallbackShortcuts is nearer the focused
    // TextField than the lightbox's Escape binding, so it wins while editing.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: TextField(
          controller: _ctl,
          focusNode: _focus,
          textAlign: TextAlign.center,
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
          cursorColor: PabloColors.selectionPrimary,
          style: PabloTypography.sans(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.92),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Add a caption…',
            hintStyle: PabloTypography.sans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl,
              vertical: PabloSpacing.base,
            ),
            border: OutlineInputBorder(
              borderRadius: PabloRadius.mdAll,
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _display(String cap) {
    final hasCap = cap.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _beginEdit(cap),
        behavior: HitTestBehavior.opaque,
        child: Text(
          hasCap ? cap : 'Add a caption…',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PabloTypography.sans(
            fontSize: 13,
            fontWeight: hasCap ? FontWeight.w500 : FontWeight.w400,
            color: Colors.white.withValues(alpha: hasCap ? 0.85 : 0.35),
          ).copyWith(fontStyle: hasCap ? FontStyle.normal : FontStyle.italic),
        ),
      ),
    );
  }
}

/// Horizontal gradient that fades the filmstrip into the lightbox chrome at
/// each edge.
class _FilmEdgeFade extends StatelessWidget {
  const _FilmEdgeFade({required this.left});
  final bool left;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            PabloColors.lightboxBackground,
            PabloColors.lightboxBackground.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
