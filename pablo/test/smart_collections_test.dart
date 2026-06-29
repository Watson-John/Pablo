// Unit tests for smart-collection dispatch: photosFor() resolves `smart:*`
// keys from the map reloadSmartCollections() builds, and the hide filter
// applies to them just like albums/folders.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/data/models.dart';

Photo _p(String path) => Photo(id: path, label: path, filePath: path);

void main() {
  tearDown(() {
    setSmartSectionPhotos(const {});
    setAlbumSectionPhotos(const {});
    hydrateHidden(const {});
    setLibraryShowHidden(false);
  });

  test('photosFor resolves smart-collection keys', () {
    setSmartSectionPhotos({
      'smart:all': [_p('/r/a.jpg'), _p('/r/b.jpg'), _p('/r/c.jpg')],
      'smart:recent': [_p('/r/c.jpg'), _p('/r/b.jpg')],
      'smart:starred': [_p('/r/a.jpg')],
    });

    expect(photosFor('smart:all').length, 3);
    expect(photosFor('smart:recent').map((p) => p.id).toList(),
        ['/r/c.jpg', '/r/b.jpg']);
    expect(photosFor('smart:starred').single.id, '/r/a.jpg');
  });

  test('hidden photos drop out of smart collections', () {
    setSmartSectionPhotos({
      'smart:recent': [_p('/r/a.jpg'), _p('/r/b.jpg')],
    });
    hydrateHidden({'/r/a.jpg'});
    expect(photosFor('smart:recent').map((p) => p.id).toList(), ['/r/b.jpg']);

    setLibraryShowHidden(true);
    expect(photosFor('smart:recent').length, 2);
  });

  test('smart keys take precedence over album keys', () {
    // Disjoint key spaces, but smart is checked first in photosFor.
    setSmartSectionPhotos({'smart:all': [_p('/s/x.jpg')]});
    setAlbumSectionPhotos({'album:1': [_p('/a/y.jpg')]});
    expect(photosFor('smart:all').single.id, '/s/x.jpg');
    expect(photosFor('album:1').single.id, '/a/y.jpg');
  });
}
