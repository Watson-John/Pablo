// world_map.dart — a real, world-wide photo map. Equirectangular projection of
// the whole globe (replacing the USA-only stylized outline), with simplified
// continent landmasses, a labelled graticule, and heat circles placed by true
// GPS coordinates. Supports a "place location" mode used by manual geotagging:
// a tap reports the lat/lon under the cursor instead of selecting a marker.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'world_geometry.dart';

// 2:1 equirectangular viewBox.
const double _kVbW = 800;
const double _kVbH = 400;

class WorldHeatMap extends StatelessWidget {
  const WorldHeatMap({
    required this.locations,
    required this.selectedId,
    required this.onSelect,
    this.placing = false,
    this.onPlace,
    super.key,
  });

  final List<MapLocation> locations;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// When true, a tap reports coordinates via [onPlace] (manual geotag) instead
  /// of selecting a marker.
  final bool placing;
  final void Function(double lat, double lon)? onPlace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final scale = math.min(w / _kVbW, h / _kVbH);
      final offX = (w - _kVbW * scale) / 2;
      final offY = (h - _kVbH * scale) / 2;
      return MouseRegion(
        cursor: placing ? SystemMouseCursors.precise : MouseCursor.defer,
        child: GestureDetector(
          onTapUp: (d) {
            final vx = (d.localPosition.dx - offX) / scale;
            final vy = (d.localPosition.dy - offY) / scale;
            if (vx < 0 || vx > _kVbW || vy < 0 || vy > _kVbH) return;
            if (placing && onPlace != null) {
              final ll = unprojectNorm(vx / _kVbW, vy / _kVbH);
              onPlace!(ll[0], ll[1]);
              return;
            }
            // Hit-test the nearest marker within its radius.
            MapLocation? hit;
            double best = 24;
            for (final loc in locations) {
              final p = projectNorm(loc.lat, loc.lon);
              final lx = p.dx * _kVbW, ly = p.dy * _kVbH;
              final r = _radiusFor(loc, locations);
              final dist = math.sqrt(
                  math.pow(vx - lx, 2).toDouble() + math.pow(vy - ly, 2));
              if (dist <= r + 6 && dist < best) {
                best = dist;
                hit = loc;
              }
            }
            if (hit != null) onSelect(hit.id);
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _WorldPainter(locations: locations, selectedId: selectedId),
          ),
        ),
      );
    });
  }
}

double _radiusFor(MapLocation loc, List<MapLocation> all) =>
    (math.sqrt(loc.count.toDouble()) * 2.6).clamp(4.0, 26.0);

class _WorldPainter extends CustomPainter {
  _WorldPainter({required this.locations, this.selectedId});
  final List<MapLocation> locations;
  final String? selectedId;

  Offset _vb(double lat, double lon) {
    final p = projectNorm(lat, lon);
    return Offset(p.dx * _kVbW, p.dy * _kVbH);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / _kVbW, size.height / _kVbH);
    canvas.save();
    canvas.translate(
      (size.width - _kVbW * scale) / 2,
      (size.height - _kVbH * scale) / 2,
    );
    canvas.scale(scale);
    canvas.clipRect(const Rect.fromLTWH(0, 0, _kVbW, _kVbH));

    // Ocean.
    final ocean = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [PabloColors.mapOceanLight, PabloColors.mapOcean],
      ).createShader(const Rect.fromLTWH(0, 0, _kVbW, _kVbH));
    canvas.drawRect(const Rect.fromLTWH(0, 0, _kVbW, _kVbH), ocean);

    // Graticule every 30°, with a stronger equator + prime meridian.
    final grid = Paint()
      ..color = PabloColors.mapGridLine
      ..strokeWidth = 0.6;
    final gridStrong = Paint()
      ..color = PabloColors.mapGridLine
      ..strokeWidth = 1.2;
    for (var lon = -180; lon <= 180; lon += 30) {
      final x = _vb(0, lon.toDouble()).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, _kVbH), lon == 0 ? gridStrong : grid);
    }
    for (var lat = -90; lat <= 90; lat += 30) {
      final y = _vb(lat.toDouble(), 0).dy;
      canvas.drawLine(Offset(0, y), Offset(_kVbW, y), lat == 0 ? gridStrong : grid);
    }

    // Continents.
    final landFill = Paint()
      ..color = PabloColors.mapLand
      ..style = PaintingStyle.fill;
    final landStroke = Paint()
      ..color = PabloColors.mapLandBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;
    for (final ring in kWorldOutline) {
      final path = Path();
      for (var i = 0; i < ring.length; i++) {
        final o = _vb(ring[i][1], ring[i][0]);
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      path.close();
      canvas.drawPath(path, landFill);
      canvas.drawPath(path, landStroke);
    }

    // Heat circles.
    if (locations.isNotEmpty) {
      final maxCount = locations
          .map((l) => l.count)
          .reduce((a, b) => a > b ? a : b)
          .toDouble();
      for (final loc in locations) {
        final c = _vb(loc.lat, loc.lon);
        final isSelected = selectedId == loc.id;
        final r = _radiusFor(loc, locations);
        final intensity = loc.count / maxCount;

        final glow = Paint()
          ..color = PabloColors.accentPrimary
              .withValues(alpha: isSelected ? 0.30 : 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(c, r * 2.1, glow);

        final ringMid = Paint()
          ..color = PabloColors.accentPrimary
              .withValues(alpha: 0.18 + intensity * 0.18);
        canvas.drawCircle(c, r * 1.25, ringMid);

        final core = Paint()
          ..color = isSelected
              ? PabloColors.accentPrimary
              : PabloColors.amber.withValues(alpha: 0.78);
        canvas.drawCircle(c, r, core);

        final coreStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2 : 1
          ..color =
              isSelected ? PabloColors.accentHover : PabloColors.mapHeatStroke;
        canvas.drawCircle(c, r, coreStroke);

        final dot = Paint()..color = PabloColors.mapCenterDot;
        canvas.drawCircle(c, 1.6, dot);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WorldPainter old) =>
      old.locations != locations || old.selectedId != selectedId;
}
