// kml_export.dart — build a KML document from geotagged photos (Picasa parity
// §8 "KML / KMZ export"). Pure string building, so it is fully unit-testable and
// carries no dependency; the caller writes the returned text to a `.kml` file.
//
// KML is Google Earth / Maps XML. Each photo becomes a <Placemark> with a
// <Point>. Note KML orders coordinates as lon,lat,alt (not lat,lon).

/// One point of interest to export.
class KmlPlacemark {
  const KmlPlacemark({
    required this.name,
    required this.lat,
    required this.lon,
    this.description,
  });

  final String name;
  final double lat;
  final double lon;
  final String? description;
}

/// Build a complete KML document. Placemarks with out-of-range coordinates are
/// skipped (defensive — the catalog should never store them).
String buildKml({
  required String documentName,
  required List<KmlPlacemark> placemarks,
}) {
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
  b.writeln('  <Document>');
  b.writeln('    <name>${_esc(documentName)}</name>');
  for (final p in placemarks) {
    if (p.lat.isNaN || p.lon.isNaN) continue;
    if (p.lat < -90 || p.lat > 90 || p.lon < -180 || p.lon > 180) continue;
    b.writeln('    <Placemark>');
    b.writeln('      <name>${_esc(p.name)}</name>');
    if (p.description != null && p.description!.isNotEmpty) {
      b.writeln('      <description>${_esc(p.description!)}</description>');
    }
    b.writeln('      <Point>');
    // lon,lat,alt — KML's coordinate order.
    b.writeln('        <coordinates>${_num(p.lon)},${_num(p.lat)},0</coordinates>');
    b.writeln('      </Point>');
    b.writeln('    </Placemark>');
  }
  b.writeln('  </Document>');
  b.writeln('</kml>');
  return b.toString();
}

String _num(double v) {
  // Trim to 6 decimals (~0.1 m) and drop trailing zeros for compactness.
  var s = v.toStringAsFixed(6);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
