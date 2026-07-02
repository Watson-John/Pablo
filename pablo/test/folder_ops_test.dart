// folder_ops_test.dart — split-target selection (pure) + the filesystem folder
// ops (split end-to-end, delete-if-empty, rename collision) over temp dirs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/organize/folder_ops.dart';

void main() {
  Photo p(String id) => Photo(id: id, label: id, filePath: id);

  group('splitTargetIds', () {
    final photos = [p('/f/a'), p('/f/b'), p('/f/c'), p('/f/d')];

    test('no selection → clicked photo and everything after it', () {
      expect(splitTargetIds({}, photos, '/f/b'), ['/f/b', '/f/c', '/f/d']);
    });

    test('honors the visible order (sort is baked into [photos])', () {
      final reversed = photos.reversed.toList();
      expect(splitTargetIds({}, reversed, '/f/c'), ['/f/c', '/f/b', '/f/a']);
    });

    test('multi-selection containing the clicked photo → the selection', () {
      expect(
        splitTargetIds({'/f/a', '/f/c'}, photos, '/f/c'),
        ['/f/a', '/f/c'],
      );
    });

    test('clicked photo not in the list → empty', () {
      expect(splitTargetIds({}, photos, '/f/zzz'), isEmpty);
    });
  });

  group('filesystem ops', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_folder_ops'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<BuildContext> pumpCtx(WidgetTester tester, PabloAppState st) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: AppScope(
          notifier: st,
          child: Scaffold(body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          })),
        ),
      ));
      return ctx;
    }

    testWidgets('deleteFolderIfEmpty removes an empty dir, refuses a full one',
        (tester) async {
      final empty = Directory('${tmp.path}/empty')..createSync();
      final full = Directory('${tmp.path}/full')..createSync();
      File('${full.path}/x.jpg').writeAsBytesSync([1]);

      final st = PabloAppState();
      final ctx = await pumpCtx(tester, st);

      await deleteFolderIfEmpty(ctx, st, empty.path);
      await tester.pump();
      expect(empty.existsSync(), isFalse);

      await deleteFolderIfEmpty(ctx, st, full.path);
      await tester.pump();
      expect(full.existsSync(), isTrue, reason: 'non-empty dir is kept');
      await tester.pump(const Duration(seconds: 5)); // drain snackbars
    });

    testWidgets('splitFolderAt moves the trailing photos into a new sibling',
        (tester) async {
      final src = Directory('${tmp.path}/2024')..createSync();
      for (final n in ['a', 'b', 'c', 'd']) {
        File('${src.path}/$n.jpg').writeAsBytesSync([1]);
      }
      Library.instance = Library.scan(tmp.path);
      addTearDown(() => Library.instance = Library.empty());

      final st = PabloAppState()..setSelectedItem(src.path, NavSection.folders);
      final photos = photosFor(src.path);
      expect(photos.length, 4);
      final clicked = photos[2].id; // split at the 3rd → moves c, d

      final ctx = await pumpCtx(tester, st);
      // ignore: unawaited_futures — the dialog is driven below.
      splitFolderAt(ctx, st, src.path, clicked);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Split Out');
      await tester.tap(find.text('Split'));
      await tester.pumpAndSettle();

      final newDir = Directory('${tmp.path}/Split Out');
      expect(newDir.existsSync(), isTrue);
      final moved = newDir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();
      // The last two visible photos moved; the first two stayed.
      expect(moved.length, 2);
      expect(st.undoStack.length, 1);
      expect(st.undoStack.top!.label, 'Split folder');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('renameFolder refuses a colliding name, leaves disk untouched',
        (tester) async {
      final a = Directory('${tmp.path}/alpha')..createSync();
      Directory('${tmp.path}/beta').createSync();
      File('${a.path}/x.jpg').writeAsBytesSync([1]);

      final st = PabloAppState();
      final ctx = await pumpCtx(tester, st);
      // ignore: unawaited_futures
      renameFolder(ctx, st, a.path);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'beta'); // already exists
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(a.existsSync(), isTrue, reason: 'original dir untouched');
      expect(File('${a.path}/x.jpg').existsSync(), isTrue);
      expect(st.undoStack.isEmpty, isTrue, reason: 'no undo pushed on refusal');
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
