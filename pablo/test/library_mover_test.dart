// Tests for in-app reorganize moves against a real temp filesystem: relocation,
// collision suffixing, same-folder skip, and undo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/library_mover.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_mover_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File mk(String rel, List<int> bytes) =>
      File('${tmp.path}/$rel')..createSync(recursive: true)..writeAsBytesSync(bytes);

  test('moves a file into another folder', () {
    final a = mk('A/p.jpg', [1, 2, 3]);
    Directory('${tmp.path}/B').createSync();
    final batch = LibraryMover.moveInto([a.path], '${tmp.path}/B');

    expect(batch.movedCount, 1);
    expect(File('${tmp.path}/B/p.jpg').existsSync(), isTrue);
    expect(a.existsSync(), isFalse);
  });

  test('collision in the destination gets a -NN suffix', () {
    final a = mk('A/p.jpg', [1]);
    mk('B/p.jpg', [9]); // occupies the target name
    final batch = LibraryMover.moveInto([a.path], '${tmp.path}/B');

    expect(batch.movedCount, 1);
    expect(batch.moves.single.toPath, endsWith('/B/p-01.jpg'));
    expect(File('${tmp.path}/B/p.jpg').readAsBytesSync(), [9]); // original kept
    expect(File('${tmp.path}/B/p-01.jpg').readAsBytesSync(), [1]);
  });

  test('files already in the destination are skipped', () {
    final a = mk('B/p.jpg', [1]);
    final batch = LibraryMover.moveInto([a.path], '${tmp.path}/B');

    expect(batch.moves, isEmpty);
    expect(a.existsSync(), isTrue);
  });

  test('undo returns files to their origin', () {
    final a = mk('A/p.jpg', [7, 7]);
    Directory('${tmp.path}/B').createSync();
    final batch = LibraryMover.moveInto([a.path], '${tmp.path}/B');
    expect(File('${tmp.path}/B/p.jpg').existsSync(), isTrue);

    final undo = LibraryMover.undo(batch);
    expect(undo.movedCount, 1);
    expect(File('${tmp.path}/A/p.jpg').existsSync(), isTrue);
    expect(File('${tmp.path}/B/p.jpg').existsSync(), isFalse);
  });
}
