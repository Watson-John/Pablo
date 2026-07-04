// LightboxView — dark surface, filmstrip, arrow nav, EXIF strip.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../people/people_scope.dart';
import '../slideshow/slideshow_view.dart';
import 'lightbox_video.dart';
import 'photo_surface.dart';
import 'widgets/caption_bar.dart';
import 'widgets/lightbox_chrome.dart';
import 'widgets/lightbox_image.dart';

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
                        const SizedBox(width: PabloSpacing.xl),
                        TopBarButton(
                          icon: PabloIconName.play,
                          tooltip: 'Slideshow',
                          onTap: () => showSlideshow(
                            context,
                            photos: widget.photos,
                            startIndex: idx,
                          ),
                        ),
                        if (widget.onToggleFullscreen != null) ...[
                          const SizedBox(width: PabloSpacing.base),
                          FullscreenButton(
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
                                IgnorePointer(child: FilmEdgeFade(left: true)),
                          ),
                          const Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                                child: FilmEdgeFade(left: false)),
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
                          child: photo.isVideo
                              ? LightboxVideo(
                                  key: ValueKey('vid-${photo.id}'),
                                  photo: photo,
                                )
                              : LightboxImage(
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
                  CaptionBar(
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
        child: NavArrowButton(icon: icon, onTap: onTap),
      ),
    );
  }
}
