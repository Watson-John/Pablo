// End-to-end test for the reorganize controller against a temp filesystem, with
// the library refresh injected. Covers the pipeline the live run exercised:
// move on disk → selection/tray REMAPPED to the new paths → refresh invoked →
// snackbar with Undo → Undo reverses the move (and remaps back).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/features/organize/reorganize_controller.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_reorg_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('move remaps selection, refreshes, snackbars; Undo reverses',
      (tester) async {
    final a = File('${tmp.path}/A/p.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    // A sibling stays behind so /A isn't emptied — this test focuses on the
    // move + undo snackbars, not the empty-folder cleanup offer.
    File('${tmp.path}/A/keep.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([9]);
    Directory('${tmp.path}/B').createSync();

    final st = PabloAppState()
      ..selectedPhotos.add(a.path)
      ..trayPhotos.add(a.path);

    var refreshCalls = 0;
    Future<void> fakeRefresh() async => refreshCalls++;

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        }),
      ),
    ));

    await reorganizeMove(ctx, st, [a.path], '${tmp.path}/B',
        refresh: fakeRefresh);
    await tester.pump(); // build the snackbar

    // Moved on disk.
    expect(File('${tmp.path}/B/p.jpg').existsSync(), isTrue);
    expect(a.existsSync(), isFalse);
    // Selection + tray FOLLOW the moved file (remapped, not dropped).
    expect(st.selectedPhotos, {'${tmp.path}/B/p.jpg'});
    expect(st.trayPhotos, ['${tmp.path}/B/p.jpg']);
    // The batch is undoable via Cmd+Z too.
    expect(st.undoStack.length, 1);
    // Library refresh was invoked.
    expect(refreshCalls, 1);
    // Result snackbar with an Undo action.
    expect(find.text('Moved 1 photo'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Undo reverses the move. Let the snackbar finish sliding in first so the
    // action button is at a tappable position.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(File('${tmp.path}/A/p.jpg').existsSync(), isTrue);
    expect(File('${tmp.path}/B/p.jpg').existsSync(), isFalse);
    expect(refreshCalls, 2);
    // Consumed off the stack (a later Cmd+Z must not double-reverse) and the
    // selection followed the file back home.
    expect(st.undoStack.isEmpty, isTrue);
    expect(st.selectedPhotos, {'${tmp.path}/A/p.jpg'});

    // The first snackbar dismisses (via the action) before the undo result
    // presents; pump through that transition.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Undid Move 1 photo'), findsOneWidget);

    // Drain snackbar auto-dismiss timers so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
  });
}
