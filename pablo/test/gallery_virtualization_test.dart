// Gallery layout tests: the section grid virtualizes (builds only on-screen
// cells) and the grid ⇄ masonry toggle swaps the underlying sliver. These run
// headless over a real (temp-folder) Library so they exercise the v4 gallery
// rebuild without a GPU/native run.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
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
    // A real folder of (empty) image files — enough photos to prove laziness.
    tempDir = Directory.systemTemp.createTempSync('pablo_gallery_test');
    for (var i = 0; i < 300; i++) {
      File('${tempDir.path}/img_${i.toString().padLeft(4, '0')}.jpg')
          .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }
    Library.instance = Library.scan(tempDir.path);
  });

  tearDownAll(() {
    Library.instance = Library.empty();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<GallerySectionData> folderSections() => [
        for (final f in Library.instance.folderSections)
          GallerySectionData(id: f.id, title: f.name, subtitle: f.path),
      ];

  int totalPhotos(List<GallerySectionData> sections) =>
      sections.fold(0, (n, s) => n + photosFor(s.id).length);

  Widget harness(PabloAppState st, List<GallerySectionData> sections) {
    return MaterialApp(
      home: AppScope(
        notifier: st,
        child: Scaffold(body: SectionScrollView(sections: sections)),
      ),
    );
  }

  testWidgets('grid mode virtualizes — builds far fewer cells than exist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sections = folderSections();
    final total = totalPhotos(sections);
    expect(total, greaterThan(200), reason: 'need enough photos to test laziness');

    final st = PabloAppState()..gridMode = GridMode.grid;
    await tester.pumpWidget(harness(st, sections));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    // Grid mode is now a justified SliverList-of-rows, not a masonry grid.
    expect(find.byType(SliverMasonryGrid), findsNothing);

    final built = find.byType(PhotoThumb).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(total),
        reason: 'only on-screen + cacheExtent cells should be built ($built/$total)');
  });

  testWidgets('masonry mode swaps the sliver and still builds lazily',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sections = folderSections();
    final total = totalPhotos(sections);

    final st = PabloAppState()..gridMode = GridMode.masonry;
    await tester.pumpWidget(harness(st, sections));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    expect(find.byType(SliverMasonryGrid), findsWidgets);
    expect(find.byType(SliverGrid), findsNothing);

    final built = find.byType(PhotoThumb).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(total));
  });

  testWidgets('scrolling reveals later sections without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sections = folderSections();
    final st = PabloAppState()..gridMode = GridMode.grid;
    await tester.pumpWidget(harness(st, sections));
    await tester.pump();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byType(PhotoThumb), findsWidgets);
  });
}
