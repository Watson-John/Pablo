// map_data.dart — turns the catalog's geotagged assets into the [MapLocation]
// markers the USA heat map renders, clustering nearby photos and projecting
// lat/lon onto the stylized outline.
//
// The map is a stylized continental-US outline (not a real world map), so
// coordinates are projected with a plain equirectangular map of the US bounding
// box; photos outside it clamp to the nearest edge. A real world map is a later
// feature — this wiring makes the existing map data-driven from real GPS.

import 'package:photo_native/photo_native.dart' show GeoPoint;

import '../../data/models.dart';

/// The map markers plus, per marker, the catalog asset ids it covers (so the
/// page can resolve the photos to show when a marker is selected).
class MapData {
  const MapData(this.locations, this.assetIdsByLocation);

  final List<MapLocation> locations;
  final Map<String, List<int>> assetIdsByLocation;

  static const MapData empty = MapData([], {});
}

// Approx continental-US bounding box (deg).
const double _kLonW = -125, _kLonE = -66, _kLatN = 49, _kLatS = 24;

/// Cluster [points] into ~1° cells and build the markers (largest first).
MapData buildMapData(List<GeoPoint> points) {
  if (points.isEmpty) return MapData.empty;

  final cells = <String, List<GeoPoint>>{};
  for (final p in points) {
    final key = '${p.lat.round()},${p.lon.round()}';
    (cells[key] ??= <GeoPoint>[]).add(p);
  }

  final locations = <MapLocation>[];
  final byLoc = <String, List<int>>{};
  cells.forEach((key, pts) {
    final lat = pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length;
    final lon = pts.map((p) => p.lon).reduce((a, b) => a + b) / pts.length;
    final cx = ((lon - _kLonW) / (_kLonE - _kLonW)).clamp(0.0, 1.0);
    final cy = ((_kLatN - lat) / (_kLatN - _kLatS)).clamp(0.0, 1.0);
    final id = 'geo_$key';
    locations.add(MapLocation(
      id: id,
      name: _label(lat, lon),
      cx: cx.toDouble(),
      cy: cy.toDouble(),
      count: pts.length,
    ));
    byLoc[id] = [for (final p in pts) p.assetId];
  });

  locations.sort((a, b) => b.count.compareTo(a.count));
  return MapData(locations, byLoc);
}

String _label(double lat, double lon) {
  final ns = lat >= 0 ? 'N' : 'S';
  final ew = lon >= 0 ? 'E' : 'W';
  return '${lat.abs().toStringAsFixed(1)}°$ns, ${lon.abs().toStringAsFixed(1)}°$ew';
}
