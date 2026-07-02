// photo_context_menu_test.dart — target computation + selection-aware labels.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/features/gallery/photo_context_menu.dart';

void main() {
  PhotoMenuActions noopActions() => PhotoMenuActions(
        onView: (_) {},
        onToggleStar: (_) {},
        onToggleHidden: (_) {},
        onAddToAlbum: (_) {},
        onMoveToFolder: (_) {},
        onSetAlbumCover: (_) {},
        onRemoveFromAlbum: (_) {},
        onShowInPablo: (_) {},
        isStarred: (_) => false,
        isHidden: (_) => false,
      );

  group('menuTargets', () {
    test('clicking outside a selection targets only the clicked photo', () {
      final st = PabloAppState()..selectedPhotos.addAll({'/a', '/b'});
      expect(menuTargets(st, '/c'), ['/c']);
    });

    test('clicking inside a multi-selection targets the whole selection', () {
      final st = PabloAppState()..selectedPhotos.addAll({'/a', '/b'});
      expect(menuTargets(st, '/a').toSet(), {'/a', '/b'});
    });

    test('a single-photo selection still targets just the clicked photo', () {
      final st = PabloAppState()..selectedPhotos.add('/a');
      expect(menuTargets(st, '/a'), ['/a']);
    });
  });

  List<String> labels(PabloAppState st, String clickedId, {int? albumId}) =>
      buildPhotoMenuItems(
        st: st,
        clickedId: clickedId,
        albumId: albumId,
        actions: noopActions(),
      ).map((i) => i.label).toList();

  test('labels carry the count for a multi-selection', () {
    final st = PabloAppState()..selectedPhotos.addAll({'/a', '/b', '/c'});
    final ls = labels(st, '/a');
    expect(ls, contains('Move 3 Photos to Folder…'));
    expect(ls, contains('Star 3 Photos'));
    expect(ls, contains('Copy 3 Paths'));
  });

  test('single target uses unnumbered labels', () {
    final ls = labels(PabloAppState(), '/a');
    expect(ls, contains('Move to Folder…'));
    expect(ls, contains('Star'));
    expect(ls, contains('Copy'));
  });

  test('album items appear only when viewing an album', () {
    final st = PabloAppState();
    expect(labels(st, '/a'), isNot(contains('Set as Album Cover')));
    expect(labels(st, '/a', albumId: 7), contains('Set as Album Cover'));
  });
}
