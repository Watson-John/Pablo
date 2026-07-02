// show_in_pablo_test.dart — a pending scroll request drives the gallery's
// ScrollController to the target section/photo, is consumed exactly once, and
// the flash highlight reaches the target thumb.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/features/gallery/photo_thumb.dart';
import 'package:pablo/features/gallery/section_scroll_view.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    tempDir = Directory.systemTemp.createTempSync('pablo_show_in_pablo');
    for (final sub in ['a', 'b', 'c']) {
      Directory('${tempDir.path}/$sub').createSync(recursive: true);
      for (var i = 0; i < 60; i++) {
        File('${tempDir.path}/$sub/img_${i.toString().padLeft(3, '0')}.jpg')
            .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
      }
    }
    Library.instance = Library.scan(tempDir.path);
  });

  tearDownAll(() {
    Library.instance = Library.empty();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<GallerySectionData> sections() => [
        for (final f in Library.instance.folderSections)
          GallerySectionData(id: f.id, title: f.name, subtitle: f.path),
      ];

  Widget harness(PabloAppState st) => MaterialApp(
        home: AppScope(
          notifier: st,
          child: Scaffold(body: SectionScrollView(sections: sections())),
        ),
      );

  testWidgets('scroll request jumps to a deep photo and is consumed once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final all = sections();
    expect(all.length, 3, reason: 'three folder sections');
    final lastSection = all.last;
    final photos = photosFor(lastSection.id);
    final target = photos[photos.length - 5];

    final st = PabloAppState()..gridMode = GridMode.grid;
    await tester.pumpWidget(harness(st));
    await tester.pump();

    // Nothing scrolled yet.
    final scrollable = find.byType(Scrollable).first;
    expect(tester.widget<Scrollable>(scrollable).controller!.offset, 0);

    st.requestGalleryScroll(lastSection.id, photoId: target.id);
    st.flashPhoto(target.id);
    await tester.pump(); // rebuild consumes the request, schedules the jump
    // Request consumed exactly once.
    expect(st.pendingGalleryScroll, isNull);
    await tester.pumpAndSettle(); // run the animateTo

    final offset = tester.widget<Scrollable>(scrollable).controller!.offset;
    expect(offset, greaterThan(300),
        reason: 'scrolled well past the first section');

    // The flashed target thumb is now built and flagged.
    final flashed = tester
        .widgetList<PhotoThumb>(find.byType(PhotoThumb))
        .where((t) => t.flash)
        .toList();
    expect(flashed.length, 1);
    expect(flashed.single.photo.id, target.id);

    // Let the flash timer fire so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('a section-only request (no photo) still scrolls to the section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final all = sections();
    final st = PabloAppState()..gridMode = GridMode.grid;
    await tester.pumpWidget(harness(st));
    await tester.pump();

    st.requestGalleryScroll(all.last.id);
    await tester.pump();
    await tester.pumpAndSettle();

    final offset = tester
        .widget<Scrollable>(find.byType(Scrollable).first)
        .controller!
        .offset;
    expect(offset, greaterThan(300));
  });
}
