// Locks the pure id helpers the face pipeline keys off: assetIdFor must never
// produce a negative id (it's hashed into the native catalog), and hueForId
// must stay a valid hue.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/asset_id.dart';
import 'package:pablo/utils/hue.dart';

void main() {
  group('assetIdFor', () {
    test('is always non-negative, across adversarial keys', () {
      const keys = [
        '',
        'a',
        '/Users/x/IMG_0001.jpg',
        'φωτογραφία.png',
        '日本語のパス.webp',
        'x', // short
      ];
      for (final k in [...keys, 'y' * 2000]) {
        expect(assetIdFor(k), greaterThanOrEqualTo(0), reason: 'key=$k');
      }
    });

    test('equals hashCode with the sign bit cleared (the only transform)', () {
      const k = 'some/deterministic/path.jpg';
      expect(assetIdFor(k), k.hashCode & 0x7FFFFFFFFFFFFFFF);
    });

    test('is deterministic for equal keys', () {
      expect(assetIdFor('/p/q.jpg'), assetIdFor('/p/q.jpg'));
    });
  });

  group('hueForId', () {
    test('always in [0, 360)', () {
      for (final id in [0, 1, 47, 359, 360, -5, 1 << 40, -(1 << 40)]) {
        expect(hueForId(id), inInclusiveRange(0, 359), reason: 'id=$id');
      }
    });

    test('treats negatives like their magnitude and matches the formula', () {
      expect(hueForId(-7), hueForId(7));
      expect(hueForId(7), (7 * 47) % 360);
    });
  });
}
