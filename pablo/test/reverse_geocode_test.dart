import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/map/reverse_geocode.dart';

void main() {
  test('resolves a coordinate to its nearest city', () {
    final p = reverseGeocode(37.7749, -122.4194); // San Francisco exactly
    expect(p, isNotNull);
    expect(p!.city, 'San Francisco');
    expect(p.country, 'United States');
    expect(p.distanceKm, lessThan(5));
    expect(p.label, 'San Francisco, United States');
  });

  test('near-but-not-exact still names the closest city', () {
    // A point ~40 km south of central Paris resolves to Paris.
    final p = reverseGeocode(48.5, 2.35);
    expect(p, isNotNull);
    expect(p!.city, 'Paris');
    expect(p.distanceKm, greaterThan(0));
    expect(p.distanceKm, lessThan(120));
  });

  test('picks the correct hemisphere city', () {
    final syd = reverseGeocode(-33.87, 151.21);
    expect(syd!.city, 'Sydney');
    final tok = reverseGeocode(35.68, 139.69);
    expect(tok!.city, 'Tokyo');
    final rio = reverseGeocode(-22.9, -43.17);
    expect(rio!.city, 'Rio de Janeiro');
  });

  test('a mid-ocean point falls back to a coarse label', () {
    // Middle of the South Pacific — the nearest city is very far.
    final p = reverseGeocode(-30.0, -140.0);
    expect(p, isNotNull);
    expect(p!.distanceKm, greaterThan(900));
    // The coarse label does not pretend the photo is IN the city.
    expect(p.label, contains('near'));
  });
}
