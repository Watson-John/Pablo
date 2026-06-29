// Unit tests for the gallery sort applied in photosFor(): Name / Date / Size /
// Rating + reverse. Exercises the setLibrarySort shim + comparator over the
// same top-level section path the View menu drives.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/utils/asset_id.dart';

Photo _p(String path, {DateTime? modified, int size = 0}) => Photo(
      id: path,
      label: path.split('/').last,
      filePath: path,
      modified: modified,
      sizeBytes: size,
    );

void main() {
  tearDown(() {
    setAlbumSectionPhotos(const {});
    setLibrarySort(PhotoSort.name, false);
    hydrateStarred(const {});
    setLibraryShowHidden(false);
    hydrateHidden(const {});
  });

  List<String> labels(String section) =>
      photosFor(section).map((p) => p.label).toList();

  test('default sort is Name A→Z by label', () {
    setAlbumSectionPhotos({
      'album:1': [_p('/d/c.jpg'), _p('/d/a.jpg'), _p('/d/b.jpg')],
    });
    setLibrarySort(PhotoSort.name, false);
    expect(labels('album:1'), ['a.jpg', 'b.jpg', 'c.jpg']);
  });

  test('reverse flips the order', () {
    setAlbumSectionPhotos({
      'album:1': [_p('/d/a.jpg'), _p('/d/b.jpg'), _p('/d/c.jpg')],
    });
    setLibrarySort(PhotoSort.name, true);
    expect(labels('album:1'), ['c.jpg', 'b.jpg', 'a.jpg']);
  });

  test('Date sort orders oldest→newest; unknown dates sort last', () {
    setAlbumSectionPhotos({
      'album:1': [
        _p('/d/c.jpg'), // no date
        _p('/d/b.jpg', modified: DateTime(2022, 5, 1)),
        _p('/d/a.jpg', modified: DateTime(2020, 1, 1)),
      ],
    });
    setLibrarySort(PhotoSort.date, false);
    expect(labels('album:1'), ['a.jpg', 'b.jpg', 'c.jpg']);
  });

  test('Size sort orders smallest→largest', () {
    setAlbumSectionPhotos({
      'album:1': [
        _p('/d/big.jpg', size: 9000),
        _p('/d/small.jpg', size: 10),
        _p('/d/mid.jpg', size: 500),
      ],
    });
    setLibrarySort(PhotoSort.size, false);
    expect(labels('album:1'), ['small.jpg', 'mid.jpg', 'big.jpg']);
  });

  test('Rating sort puts starred photos first', () {
    final starred = _p('/d/b.jpg');
    setAlbumSectionPhotos({
      'album:1': [_p('/d/a.jpg'), starred, _p('/d/c.jpg')],
    });
    hydrateStarred({assetIdFor(starred.id): true});
    setLibrarySort(PhotoSort.rating, false);
    expect(labels('album:1').first, 'b.jpg');
  });

  test('sort change invalidates the memo (re-orders immediately)', () {
    setAlbumSectionPhotos({
      'album:1': [_p('/d/a.jpg'), _p('/d/b.jpg'), _p('/d/c.jpg')],
    });
    setLibrarySort(PhotoSort.name, false);
    expect(labels('album:1'), ['a.jpg', 'b.jpg', 'c.jpg']);
    setLibrarySort(PhotoSort.name, true);
    expect(labels('album:1'), ['c.jpg', 'b.jpg', 'a.jpg']);
  });
}
