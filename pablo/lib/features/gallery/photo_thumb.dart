// PhotoThumb — hover/selected/in-tray states, star indicator, hover-add-to-tray
// + button, optional double-click to open lightbox.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class PhotoThumb extends StatefulWidget {
  const PhotoThumb({
    required this.photo,
    required this.size,
    required this.selected,
    required this.inTray,
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
    final h = widget.size * 0.72;
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
                        gradient: widget.photo.gradient,
                        borderRadius: PabloRadius.lgAll,
                        border: Border.all(color: borderColor),
                        boxShadow: shadows,
                      ),
                      child: Stack(
                        children: [
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
                                    color: Colors.white.withValues(alpha: 0.9),
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
                    if (widget.size >= 80) ...[
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
