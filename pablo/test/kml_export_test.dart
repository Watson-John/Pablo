import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/map/kml_export.dart';

void main() {
  test('builds a valid KML document with placemarks', () {
    final kml = buildKml(
      documentName: 'My Trip',
      placemarks: const [
        KmlPlacemark(
            name: 'Beach', lat: 37.5, lon: -122.3, description: '4 photos'),
        KmlPlacemark(name: 'Summit', lat: 46.0, lon: 7.0),
      ],
    );
    expect(kml, startsWith('<?xml'));
    expect(kml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
    expect(kml, contains('<name>My Trip</name>'));
    expect(kml, contains('<name>Beach</name>'));
    expect(kml, contains('<description>4 photos</description>'));
    // KML coordinate order is lon,lat,alt.
    expect(kml, contains('<coordinates>-122.3,37.5,0</coordinates>'));
    expect(kml, contains('<coordinates>7,46,0</coordinates>'));
    expect(kml.trimRight(), endsWith('</kml>'));
  });

  test('escapes XML special characters in names', () {
    final kml = buildKml(
      documentName: 'A & B',
      placemarks: const [KmlPlacemark(name: 'Tom & <Jerry>', lat: 0, lon: 0)],
    );
    expect(kml, contains('<name>A &amp; B</name>'));
    expect(kml, contains('<name>Tom &amp; &lt;Jerry&gt;</name>'));
    expect(kml, isNot(contains('Tom & <Jerry>')));
  });

  test('skips out-of-range coordinates', () {
    final kml = buildKml(
      documentName: 'D',
      placemarks: const [
        KmlPlacemark(name: 'ok', lat: 10, lon: 20),
        KmlPlacemark(name: 'bad-lat', lat: 200, lon: 0),
        KmlPlacemark(name: 'bad-lon', lat: 0, lon: 999),
      ],
    );
    expect(kml, contains('<name>ok</name>'));
    expect(kml, isNot(contains('bad-lat')));
    expect(kml, isNot(contains('bad-lon')));
  });

  test('empty placemark list still yields a document', () {
    final kml = buildKml(documentName: 'Empty', placemarks: const []);
    expect(kml, contains('<name>Empty</name>'));
    expect(kml, isNot(contains('<Placemark>')));
  });
}
