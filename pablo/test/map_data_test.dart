import 'package:flutter_test/flutter_test.dart';
import 'package:photo_native/photo_native.dart' show GeoPoint;
import 'package:pablo/features/map/map_data.dart';

void main() {
  test('empty input produces no markers', () {
    expect(buildMapData(const []).locations, isEmpty);
  });

  test('clusters nearby points by ~1° cell and counts them', () {
    final data = buildMapData(const [
      GeoPoint(1, 37.77, -122.42), // San Francisco
      GeoPoint(2, 37.78, -122.41), // San Francisco (same cell)
      GeoPoint(3, 40.71, -74.00), // New York
    ]);
    expect(data.locations.length, 2);
    // Largest cluster first.
    expect(data.locations.first.count, 2);
    final sf = data.locations.firstWhere((l) => l.count == 2);
    expect(data.assetIdsByLocation[sf.id], containsAll(<int>[1, 2]));
  });

  test('projects US coordinates into the [0,1] outline box', () {
    final l = buildMapData(const [GeoPoint(1, 37.0, -95.5)]).locations.single;
    expect(l.cx, inInclusiveRange(0.0, 1.0));
    expect(l.cy, inInclusiveRange(0.0, 1.0));
    expect(l.cx, closeTo(0.5, 0.1)); // -95.5 lon ≈ horizontal centre
    expect(l.cy, closeTo(0.48, 0.1)); // 37 lat ≈ vertical centre
  });

  test('out-of-US coordinates clamp into the box', () {
    final l = buildMapData(const [GeoPoint(1, 51.5, 0.0)]).locations.single;
    expect(l.cx, inInclusiveRange(0.0, 1.0));
    expect(l.cy, inInclusiveRange(0.0, 1.0));
  });

  test('markers carry true cluster-centroid lat/lon for the world map', () {
    final l = buildMapData(const [
      GeoPoint(1, 37.77, -122.42),
      GeoPoint(2, 37.79, -122.40),
    ]).locations.single;
    expect(l.lat, closeTo(37.78, 0.05));
    expect(l.lon, closeTo(-122.41, 0.05));
  });

  test('reverse-geocodes marker labels to a city when one is near', () {
    // A cluster right on London gets a place-name label, not raw degrees.
    final l = buildMapData(const [GeoPoint(1, 51.5074, -0.1278)]).locations.single;
    expect(l.name, contains('London'));
  });

  test('falls back to degree label far from any known city', () {
    final l = buildMapData(const [GeoPoint(1, -30.0, -140.0)]).locations.single;
    expect(l.name, contains('°'));
  });
}
