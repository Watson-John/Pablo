// CropOverlay — an interactive crop rectangle drawn over the lightbox image
// while the Crop tool is active. Works in NORMALIZED [0,1] coordinates over the
// displayed (already rotated/straightened) image, writing them straight to the
// EditSession's crop fields. The image underneath is shown UN-cropped (the
// preview surface drops the crop while this tool is active), so the user sees
// the whole frame with the crop rect + dim mask on top; the crop bakes on Save.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'edit_session.dart';

/// Crop aspect presets. `ratio` is width/height in source pixels; null = Free,
/// and `original` resolves to the image's own aspect at build time.
class _AspectPreset {
  const _AspectPreset(this.label, this.ratio);
  final String label;
  final double? ratio; // null = free
}

const List<_AspectPreset> _presets = [
  _AspectPreset('Free', null),
  _AspectPreset('Original', -1), // sentinel: use imageAspect
  _AspectPreset('1:1', 1),
  _AspectPreset('4:3', 4 / 3),
  _AspectPreset('3:2', 3 / 2),
  _AspectPreset('16:9', 16 / 9),
];

class CropOverlay extends StatefulWidget {
  const CropOverlay({
    required this.session,
    required this.imageAspect,
    super.key,
  });

  final EditSession session;

  /// Source image aspect (w/h) AFTER rotation, for the "Original" preset and
  /// aspect-locked dragging.
  final double imageAspect;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  late Rect _rect; // normalized [0,1]
  double? _lockRatio; // source-pixel aspect to maintain, null = free
  static const double _minN = 0.06; // min normalized crop size

  @override
  void initState() {
    super.initState();
    final s = widget.session.spec;
    _rect = (s.cropW > 0 && s.cropW <= 1)
        ? Rect.fromLTWH(s.cropL, s.cropT, s.cropW, s.cropH)
        : const Rect.fromLTWH(0, 0, 1, 1);
  }

  void _commit() => widget.session
      .setCrop(_rect.left, _rect.top, _rect.width, _rect.height);

  double? _resolveRatio(_AspectPreset p) {
    if (p.ratio == null) return null;
    if (p.ratio == -1) return widget.imageAspect;
    return p.ratio;
  }

  // Set a centered rect of the given source aspect, normalized over the display
  // (whose box aspect == imageAspect), and lock to it.
  void _applyPreset(_AspectPreset p) {
    final r = _resolveRatio(p);
    setState(() {
      _lockRatio = r;
      if (r == null) return; // Free: keep the current rect
      // normalized cw/ch for source-aspect r: (cw*imgW)/(ch*imgH)=r → cw/ch =
      // r * imgH/imgW = r / imageAspect.
      final k = r / widget.imageAspect; // = cw/ch
      double cw, ch;
      if (k >= 1) {
        cw = 0.9;
        ch = (cw / k).clamp(_minN, 1.0);
      } else {
        ch = 0.9;
        cw = (ch * k).clamp(_minN, 1.0);
      }
      _rect = Rect.fromLTWH((1 - cw) / 2, (1 - ch) / 2, cw, ch);
    });
    _commit();
  }

  // Which handle (if any) a normalized point grabs.
  _Handle _hit(Offset n) {
    const h = 0.06;
    final nearL = (n.dx - _rect.left).abs() < h;
    final nearR = (n.dx - _rect.right).abs() < h;
    final nearT = (n.dy - _rect.top).abs() < h;
    final nearB = (n.dy - _rect.bottom).abs() < h;
    if (nearL && nearT) return _Handle.tl;
    if (nearR && nearT) return _Handle.tr;
    if (nearL && nearB) return _Handle.bl;
    if (nearR && nearB) return _Handle.br;
    if (_rect.contains(Offset(n.dx, n.dy))) return _Handle.move;
    return _Handle.none;
  }

  _Handle _active = _Handle.none;

  void _drag(Offset deltaN) {
    setState(() {
      var l = _rect.left, t = _rect.top, r = _rect.right, b = _rect.bottom;
      switch (_active) {
        case _Handle.move:
          var nl = (l + deltaN.dx).clamp(0.0, 1 - _rect.width);
          var nt = (t + deltaN.dy).clamp(0.0, 1 - _rect.height);
          _rect = Rect.fromLTWH(nl, nt, _rect.width, _rect.height);
          return;
        case _Handle.tl:
          l = (l + deltaN.dx).clamp(0.0, r - _minN);
          t = (t + deltaN.dy).clamp(0.0, b - _minN);
          break;
        case _Handle.tr:
          r = (r + deltaN.dx).clamp(l + _minN, 1.0);
          t = (t + deltaN.dy).clamp(0.0, b - _minN);
          break;
        case _Handle.bl:
          l = (l + deltaN.dx).clamp(0.0, r - _minN);
          b = (b + deltaN.dy).clamp(t + _minN, 1.0);
          break;
        case _Handle.br:
          r = (r + deltaN.dx).clamp(l + _minN, 1.0);
          b = (b + deltaN.dy).clamp(t + _minN, 1.0);
          break;
        case _Handle.none:
          return;
      }
      _rect = Rect.fromLTRB(l, t, r, b);
      _applyLock();
    });
  }

  // After a corner resize, snap the rect back to the locked source aspect by
  // adjusting height around the moved corner.
  void _applyLock() {
    final r = _lockRatio;
    if (r == null || _active == _Handle.move) return;
    final k = r / widget.imageAspect; // cw/ch
    final targetH = (_rect.width / k).clamp(_minN, 1.0);
    double t = _rect.top, b = _rect.bottom;
    if (_active == _Handle.tl || _active == _Handle.tr) {
      t = (b - targetH).clamp(0.0, b - _minN); // anchor bottom
    } else {
      b = (t + targetH).clamp(t + _minN, 1.0); // anchor top
    }
    _rect = Rect.fromLTRB(_rect.left, t, _rect.right, b);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      Offset toN(Offset local) =>
          Offset((local.dx / w).clamp(0.0, 1.0), (local.dy / h).clamp(0.0, 1.0));
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _active = _hit(toN(d.localPosition)),
              onPanUpdate: (d) =>
                  _drag(Offset(d.delta.dx / w, d.delta.dy / h)),
              onPanEnd: (_) {
                _active = _Handle.none;
                _commit();
              },
              child: CustomPaint(painter: _CropPainter(_rect)),
            ),
          ),
          // Aspect presets + Done, anchored at the bottom of the image.
          Positioned(
            left: 0,
            right: 0,
            bottom: PabloSpacing.lg,
            child: _PresetBar(
              active: _lockRatio,
              imageAspect: widget.imageAspect,
              onPreset: _applyPreset,
              onDone: () => widget.session.setTool(null),
            ),
          ),
        ],
      );
    });
  }
}

enum _Handle { none, move, tl, tr, bl, br }

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);
  final Rect rect; // normalized

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(rect.left * size.width, rect.top * size.height,
        rect.right * size.width, rect.bottom * size.height);
    // Dim everything outside the crop.
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.5);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(r);
    canvas.drawPath(
        Path.combine(PathOperation.difference, outer, inner), dim);
    // Border + rule-of-thirds grid.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawRect(r, border);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = Colors.white.withValues(alpha: 0.4);
    for (var i = 1; i < 3; i++) {
      final dx = r.left + r.width * i / 3;
      final dy = r.top + r.height * i / 3;
      canvas.drawLine(Offset(dx, r.top), Offset(dx, r.bottom), grid);
      canvas.drawLine(Offset(r.left, dy), Offset(r.right, dy), grid);
    }
    // Corner handles.
    final hp = Paint()..color = Colors.white;
    const hl = 18.0, ht = 3.0;
    for (final corner in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final sx = corner.dx == r.left ? 1.0 : -1.0;
      final sy = corner.dy == r.top ? 1.0 : -1.0;
      canvas.drawRect(
          Rect.fromLTWH(corner.dx - (sx < 0 ? ht : 0), corner.dy, sx * hl, ht).normalized(),
          hp);
      canvas.drawRect(
          Rect.fromLTWH(corner.dx, corner.dy - (sy < 0 ? ht : 0), ht, sy * hl).normalized(),
          hp);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}

extension on Rect {
  Rect normalized() => Rect.fromLTRB(
        left < right ? left : right,
        top < bottom ? top : bottom,
        left < right ? right : left,
        top < bottom ? bottom : top,
      );
}

class _PresetBar extends StatelessWidget {
  const _PresetBar({
    required this.active,
    required this.imageAspect,
    required this.onPreset,
    required this.onDone,
  });
  final double? active;
  final double imageAspect;
  final ValueChanged<_AspectPreset> onPreset;
  final VoidCallback onDone;

  bool _isActive(_AspectPreset p) {
    final r = p.ratio == -1 ? imageAspect : p.ratio;
    if (r == null) return active == null;
    return active != null && (active! - r).abs() < 1e-3;
  }

  @override
  Widget build(BuildContext context) {
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
            for (final p in _presets)
              _Chip(
                label: p.label,
                selected: _isActive(p),
                onTap: () => onPreset(p),
              ),
            const SizedBox(width: PabloSpacing.base),
            Container(
                width: 1, height: 16, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(width: PabloSpacing.base),
            _Chip(label: 'Done', selected: false, onTap: onDone, accent: true),
          ],
        ),
      ),
    );
  }
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
