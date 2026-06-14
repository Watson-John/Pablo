// Tests for the pure-Dart image-header dimension reader. Synthetic headers
// cover the formats; a guarded block validates against real Flickr30k JPEGs
// when the dataset is present on disk.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/image_dims.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_dims'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final p = '${tmp.path}/$name';
    File(p).writeAsBytesSync(Uint8List.fromList(bytes));
    return p;
  }

  test('PNG IHDR width/height', () {
    // signature(8) + chunk len(4) + 'IHDR' + width(4 BE=640) + height(4 BE=480)
    final b = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
      0x00, 0x00, 0x02, 0x80, // width 640
      0x00, 0x00, 0x01, 0xE0, // height 480
      0x08, 0x06, 0x00, 0x00, 0x00,
    ];
    final d = readImageDimensions(write('a.png', b))!;
    expect(d.width, 640);
    expect(d.height, 480);
    expect(d.aspect, closeTo(640 / 480, 1e-9));
  });

  test('JPEG SOF0 width/height (with an APP0 segment to skip)', () {
    final b = <int>[
      0xFF, 0xD8, // SOI
      0xFF, 0xE0, 0x00, 0x06, 0x4A, 0x46, 0x49, 0x46, // APP0 len=6 + 4 bytes
      0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, len=17, precision=8
      0x02, 0x58, // height 600
      0x03, 0x20, // width 800
      0x03, 0x00, 0x21, 0x00, // (component data, ignored)
    ];
    final d = readImageDimensions(write('a.jpg', b))!;
    expect(d.width, 800);
    expect(d.height, 600);
  });

  test('GIF logical screen size (little-endian)', () {
    final b = <int>[
      0x47, 0x49, 0x46, 0x38, 0x39, 0x61, // "GIF89a"
      0x20, 0x03, // width 800 LE
      0x58, 0x02, // height 600 LE
      0x00, 0x00,
    ];
    final d = readImageDimensions(write('a.gif', b))!;
    expect(d.width, 800);
    expect(d.height, 600);
  });

  test('WebP VP8X canvas size (24-bit, width-1/height-1)', () {
    final b = <int>[
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      0x00, 0x00, 0x00, 0x00, // file size (ignored)
      0x57, 0x45, 0x42, 0x50, // "WEBP"
      0x56, 0x50, 0x38, 0x58, // "VP8X"
      0x0A, 0x00, 0x00, 0x00, // chunk size
      0x10, 0x00, 0x00, 0x00, // flags + reserved
      0x1F, 0x03, 0x00, // width-1 = 799  -> 800
      0x57, 0x02, 0x00, // height-1 = 599 -> 600
    ];
    final d = readImageDimensions(write('a.webp', b))!;
    expect(d.width, 800);
    expect(d.height, 600);
  });

  test('unrecognized / truncated returns null', () {
    expect(readImageDimensions(write('x.bin', [1, 2, 3, 4, 5])), isNull);
    expect(readImageDimensions('${tmp.path}/does_not_exist.jpg'), isNull);
  });

  // Ground truth captured with `sips` on the local Flickr30k set. Skipped
  // automatically where the dataset isn't present (e.g. CI).
  const datasetDir =
      '/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images';
  const realCases = {
    '2609797461.jpg': [500, 332],
    '1788892671.jpg': [500, 299],
    '129860826.jpg': [500, 333],
  };
  final haveDataset = Directory(datasetDir).existsSync();

  test('real Flickr30k JPEG dimensions match sips ground truth', () {
    realCases.forEach((name, wh) {
      final d = readImageDimensions('$datasetDir/$name');
      expect(d, isNotNull, reason: name);
      expect([d!.width, d.height], wh, reason: name);
    });
  }, skip: haveDataset ? false : 'Flickr30k dataset not present');
}
