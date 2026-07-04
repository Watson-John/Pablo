// HoverSurface — the one hover state machine, extracted.
//
// Nearly every interactive row/card/thumb in Pablo needs the same plumbing:
// a MouseRegion tracking `bool _hover`, a click cursor, and a GestureDetector
// for tap/double-tap/right-click. Before this component ~20 feature widgets
// each hand-rolled a StatefulWidget for it. HoverSurface owns the state and
// hands `hovered` to a builder; the call site keeps full control of visuals
// (decoration, tint, ring) so widgets that look nothing alike still share the
// behavior. Design-system primitives in this folder (buttons, nav rows) keep
// their bespoke state machines — they ARE the design system; this is for
// feature-level composites.

import 'package:flutter/widgets.dart';

class HoverSurface extends StatefulWidget {
  const HoverSurface({
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onHoverChanged,
    this.cursor = SystemMouseCursors.click,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  /// Builds the visual for the current hover state.
  final Widget Function(BuildContext context, bool hovered) builder;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Right-click, with the global position (context menus).
  final void Function(Offset globalPosition)? onSecondaryTapDown;

  /// Fires on enter/exit for call sites that need side effects beyond the
  /// rebuild (e.g. prefetching a preview on hover).
  final ValueChanged<bool>? onHoverChanged;

  final MouseCursor cursor;
  final HitTestBehavior behavior;

  @override
  State<HoverSurface> createState() => _HoverSurfaceState();
}

class _HoverSurfaceState extends State<HoverSurface> {
  bool _hover = false;

  void _set(bool v) {
    if (_hover == v) return;
    setState(() => _hover = v);
    widget.onHoverChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapDown: widget.onSecondaryTapDown == null
            ? null
            : (d) => widget.onSecondaryTapDown!(d.globalPosition),
        child: widget.builder(context, _hover),
      ),
    );
  }
}
