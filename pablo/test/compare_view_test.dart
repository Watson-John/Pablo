// Widget tests for Compare: the tray's "Compare" action opens the 2-up view,
// and CompareView renders two panes with a working synced/independent toggle.
// Runs headless over a temp-folder Library; PhotoSurface degrades to its
// fallback with no native backend.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/features/gallery/compare_view.dart';
import 'package:pablo/features/photo_tray/photo_tray.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    tempDir = Directory.systemTemp.createTempSync('pablo_compare_test');
    for (final n in ['a', 'b', 'c']) {
      File('${tempDir.path}/$n.jpg')
          .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }
    Library.instance = Library.scan(tempDir.path);
  });

  tearDownAll(() {
    Library.instance = Library.empty();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('tray Compare opens compare over the first two photos',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ids = Library.instance.allPhotos.map((p) => p.id).toList();
    final st = PabloAppState();
    st.trayPhotos.addAll([ids[0], ids[1]]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppScope(
          notifier: st,
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: FloatingPhotoTray(),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Compare'), findsOneWidget);
    await tester.tap(find.text('Compare'));
    await tester.pump();

    expect(st.compareIds, [ids[0], ids[1]]);
  });

  testWidgets('CompareView renders and toggles synced ⇄ independent',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ids = Library.instance.allPhotos.map((p) => p.id).toList();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CompareView(ids: [ids[0], ids[1]], onClose: () {}),
      ),
    ));
    await tester.pump();

    expect(find.byType(CompareView), findsOneWidget);
    // Two panes.
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
    // Link toggle defaults to synced; tapping unlinks.
    expect(find.text('Synced'), findsOneWidget);
    await tester.tap(find.text('Synced'));
    await tester.pump();
    expect(find.text('Independent'), findsOneWidget);
  });
}
