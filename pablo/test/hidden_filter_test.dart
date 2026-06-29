// Unit tests for the gallery-side hide filter: photosFor() must drop hidden
// photos (keyed by path == Photo.id) unless "Show Hidden" is on. These exercise
// the top-level shims in library.dart that the sidebar/menu toggles drive.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/data/models.dart';

Photo _p(String path) => Photo(id: path, label: path, filePath: path);

void main() {
  tearDown(() {
    setAlbumSectionPhotos(const {});
    setSmartSectionPhotos(const {});
    hydrateHidden(const {});
    setLibraryShowHidden(false);
  });

  test('photosFor hides photos in the hide set unless Show Hidden is on', () {
    setAlbumSectionPhotos({
      'album:1': [_p('/lib/a.jpg'), _p('/lib/b.jpg')],
    });

    // Nothing hidden → both visible.
    expect(photosFor('album:1').length, 2);

    // Hide b → only a remains.
    hydrateHidden({'/lib/b.jpg'});
    expect(photosFor('album:1').map((p) => p.id).toList(), ['/lib/a.jpg']);

    // Show Hidden → b reappears.
    setLibraryShowHidden(true);
    expect(photosFor('album:1').length, 2);
  });

  test('setHiddenLocal toggles a single path in the hide set', () {
    setAlbumSectionPhotos({
      'album:1': [_p('/x.jpg'), _p('/y.jpg')],
    });

    setHiddenLocal('/x.jpg', true);
    expect(isHiddenPhoto('/x.jpg'), isTrue);
    expect(photosFor('album:1').map((p) => p.id).toList(), ['/y.jpg']);

    setHiddenLocal('/x.jpg', false);
    expect(isHiddenPhoto('/x.jpg'), isFalse);
    expect(photosFor('album:1').length, 2);
  });
}
