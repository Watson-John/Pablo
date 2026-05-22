// LightboxView — dark surface, filmstrip, arrow nav, EXIF strip.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../data/photo_factory.dart';
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
                child: ListView.separated(
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
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
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
                          horizontal: 80,
                          vertical: PabloSpacing.xxl,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _photo.gradient,
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(14)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    offset: const Offset(0, 28),
                                    blurRadius: 80,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasPrev)
                      _navArrow(
                          alignment: Alignment.centerLeft,
                          label: '‹',
                          onTap: () => _goTo(_idx - 1)),
                    if (hasNext)
                      _navArrow(
                          alignment: Alignment.centerRight,
                          label: '›',
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
    required String label,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xxl),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 26,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
