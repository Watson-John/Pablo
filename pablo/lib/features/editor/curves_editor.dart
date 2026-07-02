// CurvesEditor — a draggable master tone curve. Works in normalized [0,1] with
// y inverted (origin bottom-left, like every curves UI), writing the control
// points to the EditSession. Drag a point to move it; tap empty space to add a
// point; double-tap a middle point to remove it.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'edit_session.dart';

class CurvesEditor extends StatefulWidget {
  const CurvesEditor({required this.session, super.key});
  final EditSession session;

  @override
  State<CurvesEditor> createState() => _CurvesEditorState();
}

class _CurvesEditorState extends State<CurvesEditor> {
  late List<Offset> _pts;
  int _drag = -1;
  static const double _grab = 0.06;

  @override
  void initState() {
    super.initState();
    _load();
    // Re-sync when the curve is changed out from under us (footer Reset / Revert
    // to Original / an external undo) — otherwise the graph keeps showing a stale
    // bent curve after the spec has already collapsed to identity.
    widget.session.addListener(_syncFromSession);
  }

  @override
  void didUpdateWidget(CurvesEditor old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      old.session.removeListener(_syncFromSession);
      widget.session.addListener(_syncFromSession);
      setState(_load);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_syncFromSession);
    super.dispose();
  }

  List<Offset> _sessionPts() {
    final c = widget.session.spec.curve;
    return c.isEmpty
        ? [const Offset(0, 0), const Offset(1, 1)]
        : (List<Offset>.from(c)..sort((a, b) => a.dx.compareTo(b.dx)));
  }

  void _load() {
    _pts = _sessionPts();
  }

  static bool _samePts(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).distance > 1e-4) return false;
    }
    return true;
  }

  // Called on every session change. Reloads the displayed points from the spec
  // unless the user is mid-drag (never clobber an in-progress edit) or the points
  // already match (avoids churn on unrelated slider changes and our own commit).
  void _syncFromSession() {
    if (_drag >= 0) return;
    final target = _sessionPts();
    if (_samePts(target, _pts)) return;
    if (mounted) setState(() => _pts = target);
  }

  void _commit() {
    // A straight diagonal commits as "no curve" (identity).
    final identity = _pts.every((p) => (p.dx - p.dy).abs() < 1e-3);
    widget.session.setCurve(identity ? <Offset>[] : List<Offset>.from(_pts));
  }

  int _hit(Offset n) {
    for (var i = 0; i < _pts.length; i++) {
      if ((_pts[i] - n).distance < _grab) return i;
    }
    return -1;
  }

  void _start(Offset n) {
    _drag = _hit(n);
    if (_drag < 0) {
      // Insert a new point at this x (keep sorted, not past the endpoints).
      final x = n.dx.clamp(0.02, 0.98);
      var idx = _pts.indexWhere((p) => p.dx > x);
      if (idx < 0) idx = _pts.length;
      setState(() {
        _pts.insert(idx, Offset(x, n.dy.clamp(0.0, 1.0)));
        _drag = idx;
      });
      _commit();
    }
  }

  void _move(Offset n) {
    if (_drag < 0) return;
    setState(() {
      final isFirst = _drag == 0, isLast = _drag == _pts.length - 1;
      // Endpoints keep their x (0 or 1); middle points stay between neighbours.
      double x = _pts[_drag].dx;
      if (!isFirst && !isLast) {
        final lo = _pts[_drag - 1].dx + 0.01;
        final hi = _pts[_drag + 1].dx - 0.01;
        x = n.dx.clamp(lo, hi);
      }
      _pts[_drag] = Offset(x, n.dy.clamp(0.0, 1.0));
    });
  }

  void _removeAt(Offset n) {
    final i = _hit(n);
    if (i > 0 && i < _pts.length - 1) {
      setState(() => _pts.removeAt(i));
      _commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, c) {
        final s = c.maxWidth;
        Offset toN(Offset p) =>
            Offset((p.dx / s).clamp(0.0, 1.0), 1 - (p.dy / s).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _start(toN(d.localPosition)),
          onPanUpdate: (d) => _move(toN(d.localPosition)),
          onPanEnd: (_) {
            _commit();
            _drag = -1;  // gesture over → allow external re-syncs again
          },
          onDoubleTapDown: (d) => _removeAt(toN(d.localPosition)),
          child: CustomPaint(
            painter: _CurvePainter(_pts),
            size: Size(s, s),
          ),
        );
      }),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.pts);
  final List<Offset> pts;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Offset sc(Offset n) => Offset(n.dx * w, (1 - n.dy) * h);

    canvas.drawRect(Offset.zero & size,
        Paint()..color = PabloColors.backgroundSurfaceAlt);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = PabloColors.borderSubtle;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(Offset(w * i / 4, 0), Offset(w * i / 4, h), grid);
      canvas.drawLine(Offset(0, h * i / 4), Offset(w, h * i / 4), grid);
    }
    // Identity diagonal reference.
    canvas.drawLine(
        sc(const Offset(0, 0)),
        sc(const Offset(1, 1)),
        Paint()
          ..color = PabloColors.borderStrong
          ..strokeWidth = 1);
    // The curve through the points.
    final path = Path()..moveTo(sc(pts.first).dx, sc(pts.first).dy);
    for (final p in pts.skip(1)) {
      path.lineTo(sc(p).dx, sc(p).dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = PabloColors.accentPrimary);
    // Handles.
    for (final p in pts) {
      final c = sc(p);
      canvas.drawCircle(c, 5, Paint()..color = PabloColors.backgroundSurface);
      canvas.drawCircle(
          c,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = PabloColors.accentPrimary);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.pts != pts;
}
