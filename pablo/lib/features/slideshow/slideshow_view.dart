// slideshow_view.dart — fullscreen auto-advancing slideshow (Picasa parity §10).
//
// A self-contained route: black canvas, one PhotoSurface at a time (reusing the
// gallery's texture path — no EditSession/faces), crossfaded by an
// AnimatedSwitcher, driven by the pure SlideshowController. Chrome (play/pause,
// prev/next, counter, exit) auto-hides after 3 s like the lightbox. Keys:
// Space = play/pause, ←/→ = manual nav, Esc = exit.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_surface.dart';
import 'slideshow_controller.dart';

/// Push the fullscreen slideshow over [photos], starting on [startIndex].
Future<void> showSlideshow(
  BuildContext context, {
  required List<Photo> photos,
  int startIndex = 0,
  Duration interval = const Duration(seconds: 4),
  bool shuffle = false,
}) {
  if (photos.isEmpty) return Future.value();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    barrierColor: PabloColors.lightboxBackground,
    pageBuilder: (_, __, ___) => SlideshowView(
      photos: photos,
      startIndex: startIndex.clamp(0, photos.length - 1),
      interval: interval,
      shuffle: shuffle,
    ),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  ));
}

class SlideshowView extends StatefulWidget {
  const SlideshowView({
    required this.photos,
    this.startIndex = 0,
    this.interval = const Duration(seconds: 4),
    this.shuffle = false,
    super.key,
  });

  final List<Photo> photos;
  final int startIndex;
  final Duration interval;
  final bool shuffle;

  @override
  State<SlideshowView> createState() => _SlideshowViewState();
}

class _SlideshowViewState extends State<SlideshowView> {
  late final SlideshowController _ctl;
  final FocusNode _focus = FocusNode();
  bool _chromeVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _ctl = SlideshowController(
      count: widget.photos.length,
      start: widget.startIndex,
      interval: widget.interval,
      shuffle: widget.shuffle,
    )..addListener(_onTick);
    // Auto-play on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _ctl.play();
      _scheduleHide();
    });
  }

  void _onTick() => setState(() {});

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _revealChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleHide();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    _revealChrome();
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _ctl.next();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _ctl.previous();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.space) {
      _ctl.toggle();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _exit() => Navigator.of(context).maybePop();

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ctl.removeListener(_onTick);
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_ctl.currentIndex];
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _exit,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _revealChrome(),
          child: Scaffold(
            backgroundColor: PabloColors.lightboxBackground,
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _ctl.toggle,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      child: Padding(
                        // Keyed by id so the switcher crossfades on change.
                        key: ValueKey(photo.id),
                        padding: const EdgeInsets.all(PabloSpacing.xxxxl),
                        child: Center(
                          child: PhotoSurface(
                            photo: photo,
                            targetW: 1920,
                            targetH: 1920,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_chromeVisible)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _Chrome(
                      controller: _ctl,
                      index: _ctl.currentIndex,
                      total: widget.photos.length,
                      onExit: _exit,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.controller,
    required this.index,
    required this.total,
    required this.onExit,
  });

  final SlideshowController controller;
  final int index;
  final int total;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PabloSpacing.xxl,
        vertical: PabloSpacing.lg,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            PabloColors.lightboxBackground.withValues(alpha: 0.85),
            PabloColors.lightboxBackground.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: PabloIconName.arrowLeft,
            onTap: controller.previous,
          ),
          const SizedBox(width: PabloSpacing.base),
          _CircleButton(
            icon: controller.playing
                ? PabloIconName.pause
                : PabloIconName.play,
            onTap: controller.toggle,
          ),
          const SizedBox(width: PabloSpacing.base),
          _CircleButton(
            icon: PabloIconName.arrowRight,
            onTap: controller.next,
          ),
          const SizedBox(width: PabloSpacing.xl),
          Text(
            '${index + 1} / $total',
            style: PabloTypography.mono(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          _CircleButton(icon: PabloIconName.close, onTap: onExit),
        ],
      ),
    );
  }
}

class _CircleButton extends StatefulWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final PabloIconName icon;
  final VoidCallback onTap;
  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
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
            color: _hover
                ? PabloColors.lightboxNavHoverBg
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: PabloIcon(
            widget.icon,
            size: 18,
            color: _hover
                ? PabloColors.lightboxNavHoverIcon
                : PabloColors.lightboxNavIcon,
          ),
        ),
      ),
    );
  }
}
