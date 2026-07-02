// move_service_test.dart — MoveService keeps files, sidecars, and the undo
// record convergent (the catalog leg is exercised by test/ffi/ against the
// real dylib; here engine == null, the no-backend widget-test reality).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/move_service.dart';
import 'package:pablo/data/undo_stack.dart';
import 'package:pablo/utils/sidecar_paths.dart';

void main() {
  late Directory tmp;
  late String sep;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pablo_move_service_');
    sep = Platform.pathSeparator;
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String write(String rel, [String body = 'x']) {
    final p = '${tmp.path}$sep${rel.replaceAll('/', sep)}';
    File(p)
      ..createSync(recursive: true)
      ..writeAsStringSync(body);
    return p;
  }

  test('moveInto moves the photo AND its sidecars together', () {
    final photo = write('inbox/a.jpg');
    write('inbox/a.jpg.xmp');
    write('inbox/a.pablo.tif');
    final dest = '${tmp.path}${sep}sorted';

    final out = MoveService.moveInto([photo], dest);

    expect(out.movedCount, 1);
    final moved = '$dest${sep}a.jpg';
    expect(File(moved).existsSync(), isTrue);
    expect(File(xmpSidecarPathFor(moved)).existsSync(), isTrue);
    expect(File(layeredTiffPathFor(moved)).existsSync(), isTrue);
    expect(File(photo).existsSync(), isFalse);
    expect(File('$photo.xmp').existsSync(), isFalse);
    // A photo with no sidecars is the normal case — no error.
    final plain = write('inbox/b.jpg');
    expect(MoveService.moveInto([plain], dest).movedCount, 1);
  });

  test('name collision at the destination gets a -NN suffix', () {
    final photo = write('inbox/a.jpg', 'source');
    write('sorted/a.jpg', 'already there');
    final dest = '${tmp.path}${sep}sorted';

    final out = MoveService.moveInto([photo], dest);

    expect(out.movedCount, 1);
    expect(File('$dest${sep}a-01.jpg').readAsStringSync(), 'source');
    expect(File('$dest${sep}a.jpg').readAsStringSync(), 'already there');
  });

  test('same-dir sources are skipped (nothing to move)', () {
    final photo = write('sorted/a.jpg');
    final out = MoveService.moveInto([photo], '${tmp.path}${sep}sorted');
    expect(out.anyMoved, isFalse);
    expect(File(photo).existsSync(), isTrue);
  });

  test('partially-failed batch: ok rows move, undo records only them', () {
    final a = write('in/a.jpg', 'A');
    final b = write('in/b.jpg', 'B');
    write('out/b.jpg', 'blocker'); // b's exact destination already exists
    final undo = UndoStack();

    final out = MoveService.moveExact([
      PlannedMove(a, '${tmp.path}${sep}out${sep}a.jpg'),
      PlannedMove(b, '${tmp.path}${sep}out${sep}b.jpg'),
    ], undo: undo, label: 'Move 2 photos');

    expect(out.movedCount, 1);
    expect(out.failedCount, 1);
    expect(File(b).existsSync(), isTrue, reason: 'failed row untouched');
    expect(undo.top, isNotNull);
    expect(undo.top!.applied.length, 1);
    expect(undo.top!.applied.single.fromPath, a);
  });

  test('undo restores files + sidecars; already-deleted dest reports failure',
      () {
    final a = write('in/a.jpg', 'A');
    write('in/a.jpg.xmp');
    final b = write('in/b.jpg', 'B');
    final undo = UndoStack();
    final out = MoveService.moveInto([a, b], '${tmp.path}${sep}out', undo: undo);
    expect(out.movedCount, 2);

    // Sabotage one destination before undoing.
    File('${tmp.path}${sep}out${sep}b.jpg').deleteSync();

    final op = undo.pop()!;
    final result = MoveService.undoOp(op);
    expect(result.movedCount, 1, reason: 'a restored');
    expect(result.failedCount, 1, reason: 'b could not be restored');
    expect(File(a).existsSync(), isTrue);
    expect(File('$a.xmp').existsSync(), isTrue, reason: 'sidecar came back');
    expect(File(b).existsSync(), isFalse);
  });

  test('undo removes directories the op created — but only empty ones', () {
    final a = write('in/a.jpg');
    final createdDir = '${tmp.path}${sep}new';
    Directory(createdDir).createSync();
    final undo = UndoStack();
    MoveService.moveInto([a], createdDir,
        undo: undo, createdDirs: [createdDir]);

    // First undo: dir empties out and is removed.
    MoveService.undoOp(undo.pop()!);
    expect(Directory(createdDir).existsSync(), isFalse);

    // Second round: an unrelated file appears before undo → dir survives.
    final b = write('in/b.jpg');
    Directory(createdDir).createSync();
    MoveService.moveInto([b], createdDir,
        undo: undo, createdDirs: [createdDir]);
    write('new/unrelated.txt');
    MoveService.undoOp(undo.pop()!);
    expect(Directory(createdDir).existsSync(), isTrue);
  });

  test('unicode + spaces round-trip through move and undo', () {
    final a = write('déjà vu/фото 01 (копия).jpg', 'ü');
    final dest = '${tmp.path}$sep' 'новая папка';
    final undo = UndoStack();

    final out = MoveService.moveInto([a], dest, undo: undo);
    expect(out.movedCount, 1);
    final moved = '$dest$sep' 'фото 01 (копия).jpg';
    expect(File(moved).readAsStringSync(), 'ü');

    MoveService.undoOp(undo.pop()!);
    expect(File(a).readAsStringSync(), 'ü');
  });

  test('emptiedSourceDirs reports dirs left without images', () {
    final a = write('emptying/a.jpg');
    final b = write('staying/b.jpg');
    write('staying/keep.jpg');
    write('emptying/notes.txt'); // non-image leftovers don't count as photos

    final out =
        MoveService.moveInto([a, b], '${tmp.path}${sep}out');
    expect(out.movedCount, 2);
    expect(out.emptiedSourceDirs, ['${tmp.path}${sep}emptying']);
  });

  test('remapped exposes old→new for ok rows only', () {
    final a = write('in/a.jpg');
    final b = write('in/b.jpg');
    write('out/b.jpg'); // blocks b
    final out = MoveService.moveExact([
      PlannedMove(a, '${tmp.path}${sep}out${sep}a.jpg'),
      PlannedMove(b, '${tmp.path}${sep}out${sep}b.jpg'),
    ], label: 'test');
    expect(out.remapped, {a: '${tmp.path}${sep}out${sep}a.jpg'});
  });
}
