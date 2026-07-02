// RetouchOverlay — the click-to-dab layer for the Red-Eye and Heal tools, drawn
// over the lightbox image while one of those tools is active. Works in
// NORMALIZED [0,1] coordinates over the displayed (already rotated / straightened
// / cropped) frame, which is exactly the space the native apply_redeye /
// apply_heal passes operate on, so a dab placed here lands where the user sees it.
//
// A dab is a circle: tap to place one at the pointer with the current brush size;
// scroll (or the S/M/L chips) resizes the brush. Existing dabs of the active tool
// are drawn as rings so the user can see what's been marked. The retouch bakes on
// the next preview re-render (the session mutation triggers it) and on Save.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Engine;

import '../../theme/tokens.dart';
import 'edit_spec.dart';
import 'edit_session.dart';

class RetouchOverlay extends StatefulWidget {
  const RetouchOverlay({
    required this.session,
    required this.tool, // 'redeye' | 'heal'
    super.key,
  });

  final EditSession session;
  final String tool;

  @override
  State<RetouchOverlay> createState() => _RetouchOverlayState();
}

class _RetouchOverlayState extends State<RetouchOverlay> {
  // Brush radius as a fraction of the frame's short edge (matches EditRegion.r).
  late double _brush = widget.tool == 'redeye' ? 0.035 : 0.06;
  Offset? _hover; // local pointer position for the ghost brush

  bool get _isRedeye => widget.tool == 'redeye';

  List<EditRegion> get _dabs =>
      _isRedeye ? widget.session.spec.redeye : widget.session.spec.heal;

  Color get _color =>
      _isRedeye ? PabloColors.error : PabloColors.selectionPrimary;

  // Index of the topmost existing dab containing the normalized point, or -1.
  int _hitDab(double u, double v, Size box) {
    final short = box.shortestSide;
    final dabs = _dabs;
    for (var i = dabs.length - 1; i >= 0; i--) {
      final d = dabs[i];
      final dx = (u - d.x) * box.width, dy = (v - d.y) * box.height;
      if (dx * dx + dy * dy <= (d.r * short) * (d.r * short)) return i;
    }
    return -1;
  }

  void _place(Offset local, Size box) {
    final u = (local.dx / box.width).clamp(0.0, 1.0);
    final v = (local.dy / box.height).clamp(0.0, 1.0);
    // Tap on an existing dab removes it (per-eye veto, like Picasa's per-
    // correction X) rather than stacking a second dab on top of it.
    final hit = _hitDab(u, v, box);
    if (hit >= 0) {
      widget.session.removeRetouchAt(widget.tool, hit);
      return;
    }
    final region = EditRegion(x: u, y: v, r: _brush);
    if (_isRedeye) {
      widget.session.addRedeye(region);
    } else {
      widget.session.addHeal(region);
    }
  }

  void _resizeBrush(double delta) {
    setState(() => _brush = (_brush + delta).clamp(0.01, 0.25));
  }

  // One-click auto-fix: detect red-eyes from the asset's face landmarks and add a
  // dab for each. Reports the outcome so the user knows whether to brush manually
  // — and tells the truth on builds where detection never ran (no face models on
  // Linux/Windows), instead of a misleading "no red-eye detected".
  void _autoFix() {
    if (!Engine.redeyeAutoSupported) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text(
            'Auto red-eye isn’t available on this platform — tap each eye to fix it manually'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    final n = widget.session.autoRedeye();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(n > 0
          ? 'Fixed $n red-${n == 1 ? 'eye' : 'eyes'} automatically — tap a mark to remove'
          : 'No red-eye detected — tap each eye to fix it manually'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      return Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  _resizeBrush(e.scrollDelta.dy > 0 ? -0.004 : 0.004);
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (e) => setState(() => _hover = e.localPosition),
                onExit: (_) => setState(() => _hover = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _place(d.localPosition, box),
                  child: CustomPaint(
                    painter: _RetouchPainter(
                      dabs: _dabs,
                      color: _color,
                      brush: _brush,
                      hover: _hover,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: PabloSpacing.lg,
            child: _RetouchBar(
              tool: widget.tool,
              brush: _brush,
              count: _dabs.length,
              onBrush: (r) => setState(() => _brush = r),
              onAuto: _isRedeye ? _autoFix : null,
              onUndo: () => widget.session.undoRetouch(widget.tool),
              onClear: () => widget.session.clearRetouch(widget.tool),
              onDone: () => widget.session.setTool(null),
            ),
          ),
        ],
      );
    });
  }
}

class _RetouchPainter extends CustomPainter {
  _RetouchPainter({
    required this.dabs,
    required this.color,
    required this.brush,
    required this.hover,
  });

  final List<EditRegion> dabs;
  final Color color;
  final double brush;
  final Offset? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final short = size.shortestSide;
    // Committed dabs: a tinted fill + a solid ring in the tool colour.
    final fill = Paint()..color = color.withValues(alpha: 0.28);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final d in dabs) {
      final c = Offset(d.x * size.width, d.y * size.height);
      final r = d.r * short;
      canvas.drawCircle(c, r, fill);
      canvas.drawCircle(c, r, ring);
    }
    // Ghost brush at the pointer.
    if (hover != null) {
      final g = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.9);
      canvas.drawCircle(hover!, brush * short, g);
    }
  }

  @override
  bool shouldRepaint(_RetouchPainter old) =>
      old.dabs.length != dabs.length ||
      old.brush != brush ||
      old.hover != hover ||
      old.color != color;
}

class _RetouchBar extends StatelessWidget {
  const _RetouchBar({
    required this.tool,
    required this.brush,
    required this.count,
    required this.onBrush,
    required this.onUndo,
    required this.onClear,
    required this.onDone,
    this.onAuto,
  });
  final String tool;
  final double brush;
  final int count;
  final ValueChanged<double> onBrush;
  final VoidCallback onUndo;
  final VoidCallback onClear;
  final VoidCallback onDone;
  final VoidCallback? onAuto;  // red-eye only: one-click auto-detect

  static const Map<String, double> _sizes = {'S': 0.025, 'M': 0.05, 'L': 0.09};

  @override
  Widget build(BuildContext context) {
    final label = tool == 'redeye' ? 'Red-Eye' : 'Heal';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.base, vertical: PabloSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: PabloRadius.pillAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm),
              child: Text(
                count == 0
                    ? '$label — tap to mark'
                    : '$label ($count) — tap a mark to remove',
                style: PabloTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            _divider(),
            for (final e in _sizes.entries)
              _Chip(
                label: e.key,
                selected: (brush - e.value).abs() < 0.012,
                onTap: () => onBrush(e.value),
              ),
            _divider(),
            if (onAuto != null)
              _Chip(label: 'Auto', selected: false, onTap: onAuto!),
            _Chip(label: 'Undo', selected: false, onTap: onUndo),
            _Chip(label: 'Clear', selected: false, onTap: onClear),
            _Chip(label: 'Done', selected: false, onTap: onDone, accent: true),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm),
        child: Container(
            width: 1, height: 16, color: Colors.white.withValues(alpha: 0.2)),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.xs),
          padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.lg, vertical: PabloSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? PabloColors.selectionPrimary
                : (accent ? PabloColors.assignGreen : Colors.transparent),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Text(
            label,
            style: PabloTypography.sans(
              fontSize: 11.5,
              fontWeight: selected || accent ? FontWeight.w600 : FontWeight.w500,
              color: Colors.white.withValues(alpha: selected || accent ? 1 : 0.8),
            ),
          ),
        ),
      ),
    );
  }
}
