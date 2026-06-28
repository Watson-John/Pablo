// End-to-end test for the reorganize controller against a temp filesystem, with
// the library refresh injected. Covers the pipeline the live run exercised:
// move on disk → stale selection/tray cleared → refresh invoked → snackbar with
// Undo → Undo reverses the move.

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

  testWidgets('move clears selection, refreshes, snackbars; Undo reverses',
      (tester) async {
    final a = File('${tmp.path}/A/p.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
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
    // Stale id dropped from selection + tray.
    expect(st.selectedPhotos.contains(a.path), isFalse);
    expect(st.trayPhotos.contains(a.path), isFalse);
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

    // The first snackbar dismisses (via the action) before "Move undone"
    // presents; pump through that transition.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Move undone'), findsOneWidget);

    // Drain snackbar auto-dismiss timers so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
  });
}
