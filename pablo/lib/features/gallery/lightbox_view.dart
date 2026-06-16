// LightboxView — dark surface, filmstrip, arrow nav, EXIF strip.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';

class LightboxView extends StatefulWidget {
  const LightboxView({
    required this.photos,
    required this.initialId,
    required this.onClose,
    super.key,
  });

  final List<Photo> photos;
  final String initialId;
  final VoidCallback onClose;

  @override
  State<LightboxView> createState() => _LightboxViewState();
}

class _LightboxViewState extends State<LightboxView> {
  late String _currentId = widget.initialId;
  final FocusNode _focus = FocusNode();
  final ScrollController _filmCtl = ScrollController();

  int get _idx => widget.photos.indexWhere((p) => p.id == _currentId).clamp(0, widget.photos.length - 1);

  Photo get _photo => widget.photos[_idx];

  void _goTo(int idx) {
    final c = idx.clamp(0, widget.photos.length - 1);
    setState(() => _currentId = widget.photos[c].id);
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
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _filmCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exif = getPhotoExif(_photo.id);
    final hasPrev = _idx > 0;
    final hasNext = _idx < widget.photos.length - 1;

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Container(
        color: PabloColors.lightboxBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xxl, PabloSpacing.lg, PabloSpacing.xxl, PabloSpacing.md,
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
                    _photo.label,
                    style: PabloTypography.mono(
                      fontSize: 12.5,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(width: PabloSpacing.xl),
                  Expanded(
                    child: Text(
                      '${exif.camera} · ${exif.aperture} · ${exif.shutter} · ISO ${exif.iso}',
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  Text(
                    '${_idx + 1} / ${widget.photos.length}',
                    style: PabloTypography.mono(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                ],
              ),
            ),

            // Filmstrip
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
                  separatorBuilder: (_, __) => const SizedBox(width: 5),
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
                              gradient: p.gradient,
                              borderRadius: PabloRadius.mdAll,
                              border: Border.all(
                                color: current
                                    ? PabloColors.selectionPrimary
                                    : PabloColors.borderSubtle,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                    // Edge fades so thumbnails dissolve into the chrome.
                    const Positioned(
                      left: 0, top: 0, bottom: 0,
                      child: IgnorePointer(child: _FilmEdgeFade(left: true)),
                    ),
                    const Positioned(
                      right: 0, top: 0, bottom: 0,
                      child: IgnorePointer(child: _FilmEdgeFade(left: false)),
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
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: PabloSpacing.xxxxl,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _photo.gradient,
                                borderRadius: PabloRadius.lgAll,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    offset: const Offset(0, 8),
                                    blurRadius: 40,
                                  ),
                                ],
                              ),
                              // Subtle glossy shine highlight (inset).
                              child: Center(
                                child: FractionallySizedBox(
                                  widthFactor: 0.84,
                                  heightFactor: 0.84,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: PabloRadius.mdAll,
                                      gradient: RadialGradient(
                                        center: const Alignment(-0.24, -0.44),
                                        radius: 0.65,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.14),
                                          Colors.white.withValues(alpha: 0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
          ],
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
            color: _hover
                ? PabloColors.lightboxNavHoverBg
                : Colors.transparent,
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
