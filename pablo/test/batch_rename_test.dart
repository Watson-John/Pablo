// batch_rename_test.dart — the pure rename planner: counter semantics,
// deterministic collision suffixing, extension preservation, unicode, and
// identity-drop. No filesystem — [metaOf] and [exists] are injected.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/data/storage_scheme.dart';
import 'package:pablo/features/organize/batch_rename.dart';

void main() {
  PhotoMeta meta(String path) {
    final base = path.split('/').last;
    final dot = base.lastIndexOf('.');
    return PhotoMeta(
      fileMtime: DateTime(2024, 3, 9),
      originalName: dot > 0 ? base.substring(0, dot) : base,
      ext: dot > 0 ? base.substring(dot).toLowerCase() : '.jpg',
    );
  }

  PatternLane counterLane(int pad) =>
      PatternLane([TokenSegment(TokenType.counter, pad: pad)]);

  List<RenamePreview> plan(
    List<String> paths,
    PatternLane lane, {
    int start = 1,
    bool Function(String)? exists,
  }) =>
      planRename(
        paths: paths,
        metaOf: meta,
        lane: lane,
        startCounter: start,
        exists: exists ?? (_) => false,
      );

  test('counter advances once per photo and pads', () {
    final p = plan(['/f/a.jpg', '/f/b.jpg', '/f/c.jpg'], counterLane(3));
    expect(p.map((r) => r.newName).toList(),
        ['001.jpg', '002.jpg', '003.jpg']);
  });

  test('extension is preserved from each source file', () {
    final p = plan(['/f/a.JPG', '/f/b.png'], counterLane(2));
    expect(p[0].newName, '01.jpg'); // ext lower-cased by the meta reader
    expect(p[1].newName, '02.png');
  });

  test('a fixed-name lane collides within the batch → deterministic -NN', () {
    // A literal name every photo shares.
    final lane = PatternLane([const LiteralSegment('IMG')]);

    // Different directories → each dir gets its own IMG.jpg, no collision.
    final crossDir = plan(['/f/a.jpg', '/g/b.jpg', '/h/c.jpg'], lane);
    expect(crossDir.every((r) => r.newName == 'IMG.jpg'), isTrue);

    // Same directory → 2nd and 3rd get suffixes.
    final same = plan(['/f/a.jpg', '/f/b.jpg', '/f/c.jpg'], lane);
    expect(same[0].newName, 'IMG.jpg');
    expect(same[1].newName, 'IMG-01.jpg');
    expect(same[2].newName, 'IMG-02.jpg');
    expect(same[1].conflictResolved, isTrue);
  });

  test('a target colliding with an unselected on-disk file is suffixed', () {
    // A literal name that already exists on disk (not part of the batch) forces
    // a real rename that must dodge the existing file.
    final p = plan(
      ['/f/src.jpg'],
      PatternLane([const LiteralSegment('taken')]),
      exists: (path) => path == '/f/taken.jpg',
    );
    expect(p.single.newName, 'taken-01.jpg');
  });

  test('identity renames are dropped from the applicable moves', () {
    final lane = PatternLane([const TokenSegment(TokenType.originalName)]);
    final p = plan(['/f/a.jpg', '/f/b.jpg'], lane);
    // Both render to their own name → identities.
    expect(p.every((r) => r.isIdentity), isTrue);
    expect(movesFrom(p), isEmpty);
  });

  test('movesFrom builds same-directory destinations for real renames', () {
    final p = plan(['/f/a.jpg', '/f/b.jpg'], counterLane(2));
    final moves = movesFrom(p);
    expect(moves.length, 2);
    expect(moves[0].from, '/f/a.jpg');
    expect(moves[0].to, '/f/01.jpg');
    expect(moves[1].to, '/f/02.jpg');
  });

  test('unicode original names round-trip', () {
    final lane = PatternLane([const TokenSegment(TokenType.originalName)]);
    final p = plan(['/f/déjà.jpg'], PatternLane([...lane.segments]));
    expect(p.single.newName, 'déjà.jpg');
  });
}
