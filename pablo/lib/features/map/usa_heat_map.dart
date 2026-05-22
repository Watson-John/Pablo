// USAHeatMap — CustomPainter rendering the simplified continental USA outline
// (verbatim USA_PATH from pablo3-map.jsx) with heat circles per MapLocation.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class USAHeatMap extends StatelessWidget {
  const USAHeatMap({required this.selectedId, required this.onSelect, super.key});
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Compute scaling so the 800×480 viewBox fits in the available space.
      final w = c.maxWidth;
      final h = c.maxHeight;
      final scale = math.min(w / 800, h / 480);
      return GestureDetector(
        onTapUp: (d) {
          final dx = (d.localPosition.dx - (w - 800 * scale) / 2) / scale;
          final dy = (d.localPosition.dy - (h - 480 * scale) / 2) / scale;
          // Hit-test the closest location within 20 units.
          MapLocation? hit;
          double best = 20;
          for (final loc in kMapLocations) {
            final r = math.sqrt(loc.count.toDouble()) * 2.8;
            final dist =
                math.sqrt(math.pow(dx - loc.cx, 2) + math.pow(dy - loc.cy, 2));
            if (dist <= r + 4 && dist < best) {
              best = dist;
              hit = loc;
            }
          }
          if (hit != null) onSelect(hit.id);
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: _USAHeatMapPainter(selectedId: selectedId),
        ),
      );
    });
  }
}

class _USAHeatMapPainter extends CustomPainter {
  _USAHeatMapPainter({this.selectedId});
  final String? selectedId;

  Path _usaPath() {
    final p = Path();
    final tokens = kUsaPath.split(RegExp(r'\s+'));
    double cx = 0, cy = 0;
    int i = 0;
    while (i < tokens.length) {
      final t = tokens[i];
      if (t == 'M' && i + 1 < tokens.length) {
        final parts = tokens[i + 1].split(',');
        cx = double.parse(parts[0]);
        cy = double.parse(parts[1]);
        p.moveTo(cx, cy);
        i += 2;
      } else if (t == 'L' && i + 1 < tokens.length) {
        final parts = tokens[i + 1].split(',');
        cx = double.parse(parts[0]);
        cy = double.parse(parts[1]);
        p.lineTo(cx, cy);
        i += 2;
      } else if (t == 'Z') {
        p.close();
        i += 1;
      } else {
        i += 1;
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Center & scale 800×480 viewBox into the available space (xMidYMid meet).
    final scale = math.min(size.width / 800, size.height / 480);
    canvas.save();
    canvas.translate(
      (size.width - 800 * scale) / 2,
      (size.height - 480 * scale) / 2,
    );
    canvas.scale(scale);

    // Ocean
    final ocean = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.7,
        colors: [PabloColors.mapOceanLight, PabloColors.mapOcean],
      ).createShader(const Rect.fromLTWH(0, 0, 800, 480));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 480), ocean);

    // Lat/lon grid
    final grid = Paint()
      ..color = PabloColors.mapGridLine
      ..strokeWidth = 0.7;
    for (var i = 0; i < 9; i++) {
      canvas.drawLine(Offset(0, i * 60.0), Offset(800, i * 60.0), grid);
    }
    for (var i = 0; i < 14; i++) {
      canvas.drawLine(Offset(i * 62.0, 0), Offset(i * 62.0, 480), grid);
    }

    // Land
    final landFill = Paint()
      ..color = PabloColors.mapLand
      ..style = PaintingStyle.fill;
    final landStroke = Paint()
      ..color = PabloColors.mapLandBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = _usaPath();
    canvas.drawPath(path, landFill);
    canvas.drawPath(path, landStroke);

    // Heat circles
    final maxCount = kMapLocations
        .map((l) => l.count)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    for (final loc in kMapLocations) {
      final isSelected = selectedId == loc.id;
      final r = math.sqrt(loc.count.toDouble()) * 2.8;
      final intensity = loc.count / maxCount;
      final glow = Paint()
        ..color = PabloColors.accentPrimary
            .withValues(alpha: isSelected ? 0.28 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(Offset(loc.cx, loc.cy), r * 2.2, glow);

      final ringOuter = Paint()
        ..color = PabloColors.accentPrimary
            .withValues(alpha: 0.08 + intensity * 0.10);
      canvas.drawCircle(Offset(loc.cx, loc.cy), r * 1.9, ringOuter);

      final ringMid = Paint()
        ..color = PabloColors.accentPrimary
            .withValues(alpha: 0.18 + intensity * 0.18);
      canvas.drawCircle(Offset(loc.cx, loc.cy), r * 1.25, ringMid);

      final core = Paint()
        ..color = isSelected
            ? PabloColors.accentPrimary
            : PabloColors.amber.withValues(alpha: 0.75);
      canvas.drawCircle(Offset(loc.cx, loc.cy), r, core);

      final coreStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2 : 1
        ..color = isSelected
            ? PabloColors.accentHover
            : PabloColors.mapHeatStroke;
      canvas.drawCircle(Offset(loc.cx, loc.cy), r, coreStroke);

      final centerDot = Paint()..color = PabloColors.mapCenterDot;
      canvas.drawCircle(Offset(loc.cx, loc.cy), 3.5, centerDot);

      // Labels
      final namePainter = TextPainter(
        text: TextSpan(
          text: loc.name,
          style: PabloTypography.sans(
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? PabloColors.accentPrimary : PabloColors.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      namePainter.paint(
        canvas,
        Offset(loc.cx - namePainter.width / 2, loc.cy + r + 8),
      );
      final countPainter = TextPainter(
        text: TextSpan(
          text: '${loc.count} photos',
          style: PabloTypography.sans(
            fontSize: 8.5,
            color: isSelected ? PabloColors.accentHover : PabloColors.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countPainter.paint(
        canvas,
        Offset(loc.cx - countPainter.width / 2, loc.cy + r + 20),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _USAHeatMapPainter old) =>
      old.selectedId != selectedId;
}
