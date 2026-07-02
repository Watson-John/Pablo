// render_service_test.dart — the pure passthrough decision: when a file can be
// shared/printed as-is vs. when a render is required. (The async render path
// itself needs a real Engine + dylib; it's covered by the FFI export test and
// the ExportBatchTracker unit tests.)

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/export/render_service.dart';

void main() {
  test('unedited full-size JPEG passes through as its original path', () {
    expect(
      passthroughPath(filePath: '/a/photo.jpg', spec: '', maxDim: 0),
      '/a/photo.jpg',
    );
    expect(
      passthroughPath(filePath: '/a/PHOTO.JPEG', spec: '', maxDim: 0),
      '/a/PHOTO.JPEG',
    );
  });

  test('an edited asset must be rendered (null)', () {
    expect(
      passthroughPath(
          filePath: '/a/photo.jpg', spec: 'saturation=30;', maxDim: 0),
      isNull,
    );
  });

  test('a resize request must be rendered (null)', () {
    expect(
      passthroughPath(filePath: '/a/photo.jpg', spec: '', maxDim: 2048),
      isNull,
    );
  });

  test('a non-JPEG must be rendered to JPEG (null)', () {
    expect(passthroughPath(filePath: '/a/photo.png', spec: '', maxDim: 0),
        isNull);
    expect(passthroughPath(filePath: '/a/photo.heic', spec: '', maxDim: 0),
        isNull);
  });

  test('isJpeg is case-insensitive on the extension', () {
    expect(isJpeg('/x/a.JPG'), isTrue);
    expect(isJpeg('/x/a.jpeg'), isTrue);
    expect(isJpeg('/x/a.png'), isFalse);
  });
}
