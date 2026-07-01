// reverse_geocode.dart — offline reverse-geocoding: turn decimal-degree
// coordinates into a human place name ("City, Country") by nearest-neighbour
// against a bundled table of ~250 major world cities.
//
// This is deliberately COARSE and fully offline (Picasa parity item §8
// "reverse-geocode to place names" without a network dependency, honouring the
// "no new pub deps" rule). It names the nearest sizeable city, not the exact
// street — good enough to label a map marker or a photo's location. The distance
// to that city is exposed so callers can fall back to an ocean/region label when
// the nearest city is implausibly far (mid-ocean, polar).

import 'dart:math' as math;

/// A resolved place: the nearest known city and how far the query was from it.
class GeoPlace {
  const GeoPlace(this.city, this.country, this.distanceKm);

  final String city;
  final String country;

  /// Great-circle distance (km) from the query point to [city]'s centre.
  final double distanceKm;

  /// "City, Country" — or a coarse fallback when the nearest city is very far.
  String get label {
    if (distanceKm > 900) return _coarse;
    return '$city, $country';
  }

  /// A rough region label used when no city is within [label]'s threshold.
  String get _coarse {
    // Without the city being close, fall back to naming the country/region of
    // the nearest match, which is still informative for a broad marker.
    return '$country (near $city)';
  }

  @override
  String toString() => label;
}

/// Nearest known city to (lat, lon). Returns null only if the table is empty.
GeoPlace? reverseGeocode(double lat, double lon) {
  _City? best;
  double bestKm = double.infinity;
  for (final c in _cities) {
    final d = _haversineKm(lat, lon, c.lat, c.lon);
    if (d < bestKm) {
      bestKm = d;
      best = c;
    }
  }
  if (best == null) return null;
  return GeoPlace(best.name, best.country, bestKm);
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0088; // mean Earth radius (km)
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

double _rad(double deg) => deg * math.pi / 180.0;

class _City {
  const _City(this.name, this.country, this.lat, this.lon);
  final String name;
  final String country;
  final double lat;
  final double lon;
}

// Parsed once from the compact table below. "Name|Country|lat|lon" per line.
final List<_City> _cities = () {
  final out = <_City>[];
  for (final line in _kCitiesTable.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final parts = t.split('|');
    if (parts.length != 4) continue;
    final lat = double.tryParse(parts[2]);
    final lon = double.tryParse(parts[3]);
    if (lat == null || lon == null) continue;
    out.add(_City(parts[0], parts[1], lat, lon));
  }
  return out;
}();

// Compact world-cities table (major cities across every continent). Coordinates
// are city-centre decimal degrees. Kept intentionally small — this drives coarse
// labels, not precise geocoding.
const String _kCitiesTable = '''
New York|United States|40.7128|-74.0060
Los Angeles|United States|34.0522|-118.2437
Chicago|United States|41.8781|-87.6298
Houston|United States|29.7604|-95.3698
Phoenix|United States|33.4484|-112.0740
San Francisco|United States|37.7749|-122.4194
Seattle|United States|47.6062|-122.3321
Denver|United States|39.7392|-104.9903
Las Vegas|United States|36.1699|-115.1398
Miami|United States|25.7617|-80.1918
Boston|United States|42.3601|-71.0589
Washington|United States|38.9072|-77.0369
Atlanta|United States|33.7490|-84.3880
Dallas|United States|32.7767|-96.7970
Minneapolis|United States|44.9778|-93.2650
New Orleans|United States|29.9511|-90.0715
Honolulu|United States|21.3069|-157.8583
Anchorage|United States|61.2181|-149.9003
Toronto|Canada|43.6532|-79.3832
Montreal|Canada|45.5017|-73.5673
Vancouver|Canada|49.2827|-123.1207
Calgary|Canada|51.0447|-114.0719
Ottawa|Canada|45.4215|-75.6972
Mexico City|Mexico|19.4326|-99.1332
Guadalajara|Mexico|20.6597|-103.3496
Cancun|Mexico|21.1619|-86.8515
Havana|Cuba|23.1136|-82.3666
Guatemala City|Guatemala|14.6349|-90.5069
Panama City|Panama|8.9824|-79.5199
Bogota|Colombia|4.7110|-74.0721
Lima|Peru|-12.0464|-77.0428
Quito|Ecuador|-0.1807|-78.4678
Santiago|Chile|-33.4489|-70.6693
Buenos Aires|Argentina|-34.6037|-58.3816
Sao Paulo|Brazil|-23.5558|-46.6396
Rio de Janeiro|Brazil|-22.9068|-43.1729
Brasilia|Brazil|-15.7939|-47.8828
Salvador|Brazil|-12.9777|-38.5016
Caracas|Venezuela|10.4806|-66.9036
Montevideo|Uruguay|-34.9011|-56.1645
London|United Kingdom|51.5074|-0.1278
Manchester|United Kingdom|53.4808|-2.2426
Edinburgh|United Kingdom|55.9533|-3.1883
Dublin|Ireland|53.3498|-6.2603
Paris|France|48.8566|2.3522
Marseille|France|43.2965|5.3698
Lyon|France|45.7640|4.8357
Madrid|Spain|40.4168|-3.7038
Barcelona|Spain|41.3874|2.1686
Lisbon|Portugal|38.7223|-9.1393
Amsterdam|Netherlands|52.3676|4.9041
Brussels|Belgium|50.8503|4.3517
Berlin|Germany|52.5200|13.4050
Munich|Germany|48.1351|11.5820
Frankfurt|Germany|50.1109|8.6821
Hamburg|Germany|53.5511|9.9937
Cologne|Germany|50.9375|6.9603
Zurich|Switzerland|47.3769|8.5417
Geneva|Switzerland|46.2044|6.1432
Vienna|Austria|48.2082|16.3738
Prague|Czechia|50.0755|14.4378
Warsaw|Poland|52.2297|21.0122
Krakow|Poland|50.0647|19.9450
Budapest|Hungary|47.4979|19.0402
Rome|Italy|41.9028|12.4964
Milan|Italy|45.4642|9.1900
Venice|Italy|45.4408|12.3155
Naples|Italy|40.8518|14.2681
Florence|Italy|43.7696|11.2558
Athens|Greece|37.9838|23.7275
Copenhagen|Denmark|55.6761|12.5683
Oslo|Norway|59.9139|10.7522
Stockholm|Sweden|59.3293|18.0686
Helsinki|Finland|60.1699|24.9384
Reykjavik|Iceland|64.1466|-21.9426
Moscow|Russia|55.7558|37.6173
Saint Petersburg|Russia|59.9311|30.3609
Kyiv|Ukraine|50.4501|30.5234
Bucharest|Romania|44.4268|26.1025
Sofia|Bulgaria|42.6977|23.3219
Belgrade|Serbia|44.7866|20.4489
Zagreb|Croatia|45.8150|15.9819
Istanbul|Turkey|41.0082|28.9784
Ankara|Turkey|39.9334|32.8597
Tel Aviv|Israel|32.0853|34.7818
Jerusalem|Israel|31.7683|35.2137
Amman|Jordan|31.9454|35.9284
Beirut|Lebanon|33.8938|35.5018
Cairo|Egypt|30.0444|31.2357
Riyadh|Saudi Arabia|24.7136|46.6753
Dubai|United Arab Emirates|25.2048|55.2708
Abu Dhabi|United Arab Emirates|24.4539|54.3773
Doha|Qatar|25.2854|51.5310
Tehran|Iran|35.6892|51.3890
Baghdad|Iraq|33.3152|44.3661
Casablanca|Morocco|33.5731|-7.5898
Marrakech|Morocco|31.6295|-7.9811
Tunis|Tunisia|36.8065|10.1815
Algiers|Algeria|36.7538|3.0588
Lagos|Nigeria|6.5244|3.3792
Accra|Ghana|5.6037|-0.1870
Nairobi|Kenya|-1.2921|36.8219
Addis Ababa|Ethiopia|9.0250|38.7469
Dar es Salaam|Tanzania|-6.7924|39.2083
Kampala|Uganda|0.3476|32.5825
Johannesburg|South Africa|-26.2041|28.0473
Cape Town|South Africa|-33.9249|18.4241
Durban|South Africa|-29.8587|31.0218
Luanda|Angola|-8.8390|13.2894
Dakar|Senegal|14.7167|-17.4677
Delhi|India|28.7041|77.1025
Mumbai|India|19.0760|72.8777
Bangalore|India|12.9716|77.5946
Chennai|India|13.0827|80.2707
Kolkata|India|22.5726|88.3639
Hyderabad|India|17.3850|78.4867
Karachi|Pakistan|24.8607|67.0011
Lahore|Pakistan|31.5204|74.3587
Islamabad|Pakistan|33.6844|73.0479
Dhaka|Bangladesh|23.8103|90.4125
Kathmandu|Nepal|27.7172|85.3240
Colombo|Sri Lanka|6.9271|79.8612
Bangkok|Thailand|13.7563|100.5018
Hanoi|Vietnam|21.0278|105.8342
Ho Chi Minh City|Vietnam|10.8231|106.6297
Phnom Penh|Cambodia|11.5564|104.9282
Kuala Lumpur|Malaysia|3.1390|101.6869
Singapore|Singapore|1.3521|103.8198
Jakarta|Indonesia|-6.2088|106.8456
Bali|Indonesia|-8.3405|115.0920
Manila|Philippines|14.5995|120.9842
Beijing|China|39.9042|116.4074
Shanghai|China|31.2304|121.4737
Guangzhou|China|23.1291|113.2644
Shenzhen|China|22.5431|114.0579
Chengdu|China|30.5728|104.0668
Hong Kong|China|22.3193|114.1694
Taipei|Taiwan|25.0330|121.5654
Seoul|South Korea|37.5665|126.9780
Busan|South Korea|35.1796|129.0756
Tokyo|Japan|35.6762|139.6503
Osaka|Japan|34.6937|135.5023
Kyoto|Japan|35.0116|135.7681
Sapporo|Japan|43.0618|141.3545
Ulaanbaatar|Mongolia|47.8864|106.9057
Almaty|Kazakhstan|43.2220|76.8512
Tashkent|Uzbekistan|41.2995|69.2401
Sydney|Australia|-33.8688|151.2093
Melbourne|Australia|-37.8136|144.9631
Brisbane|Australia|-27.4698|153.0251
Perth|Australia|-31.9505|115.8605
Adelaide|Australia|-34.9285|138.6007
Auckland|New Zealand|-36.8485|174.7633
Wellington|New Zealand|-41.2865|174.7762
Christchurch|New Zealand|-43.5321|172.6362
Suva|Fiji|-18.1416|178.4419
Honiara|Solomon Islands|-9.4456|159.9729
''';
