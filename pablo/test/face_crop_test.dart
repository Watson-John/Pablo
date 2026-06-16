// Locks faceCropRect — the source-pixel → normalized [0,1) crop math that puts
// a detected face into a FaceThumb. Fragile (normalize + pad + clamp) and now
// pure, so cheap to pin down.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/people/face_thumb.dart';

void main() {
  group('faceCropRect', () {
    test('returns null for degenerate dimensions', () {
      expect(
        faceCropRect(boxX: 10, boxY: 10, boxW: 50, boxH: 50, imgW: 0, imgH: 100),
        isNull,
      );
      expect(
        faceCropRect(boxX: 10, boxY: 10, boxW: 50, boxH: 50, imgW: 100, imgH: 0),
        isNull,
      );
    });

    test('normalizes a centered box and applies padding', () {
      // 100x100 image, 20x20 box at (40,40), pad 0.15 → grows 3px each side.
      final r = faceCropRect(
        boxX: 40, boxY: 40, boxW: 20, boxH: 20, imgW: 100, imgH: 100, pad: 0.15,
      )!;
      expect(r.left, closeTo(0.37, 1e-9)); // (40 - 3) / 100
      expect(r.top, closeTo(0.37, 1e-9));
      expect(r.width, closeTo(0.26, 1e-9)); // 20 * 1.3 / 100
      expect(r.height, closeTo(0.26, 1e-9));
    });

    test('clamps to the image at the top-left corner', () {
      final r = faceCropRect(
        boxX: 0, boxY: 0, boxW: 40, boxH: 40, imgW: 100, imgH: 100,
      )!;
      expect(r.left, 0.0);
      expect(r.top, 0.0);
      expect(r.left + r.width, lessThanOrEqualTo(1.0));
      expect(r.top + r.height, lessThanOrEqualTo(1.0));
    });

    test('a full-image box stays within [0,1]', () {
      final r = faceCropRect(
        boxX: 0, boxY: 0, boxW: 100, boxH: 100, imgW: 100, imgH: 100,
      )!;
      expect(r.left, 0.0);
      expect(r.left + r.width, lessThanOrEqualTo(1.0));
      expect(r.top + r.height, lessThanOrEqualTo(1.0));
    });
  });
}
