// Regression: the justified gallery + section header must not overflow (or
// throw RenderFlex/hit-test errors) when the content width is squeezed narrow
// — e.g. a small window, or the sidebar + inspector eating the width. Before
// the fix, a ragged last row rendered at the target height (and long folder-
// path subtitles wrapping past the fixed header extent) overflowed, and the
// resulting "no size" render boxes ate pointer events.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/features/gallery/section_scroll_view.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // A folder with a deliberately long path (its name is the section subtitle,
    // which used to wrap past the fixed 64px header extent at narrow widths).
    tempDir = Directory.systemTemp
        .createTempSync('pablo_narrow_gallery_with_a_long_folder_name');
    for (var i = 0; i < 23; i++) {
      File('${tempDir.path}/img_${i.toString().padLeft(4, '0')}.jpg')
          .writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }
    Library.instance = Library.scan(tempDir.path);
  });

  tearDownAll(() {
    Library.instance = Library.empty();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget harness(PabloAppState st) => MaterialApp(
        home: AppScope(
          notifier: st,
          child: Scaffold(
            body: SectionScrollView(sections: [
              for (final f in Library.instance.folderSections)
                GallerySectionData(id: f.id, title: f.name, subtitle: f.path),
            ]),
          ),
        ),
      );

  // Well below any real gallery content width: the macOS/Win/Linux runners now
  // enforce a 960px window minimum, so even with the sidebar + inspector open
  // the grid never gets narrower than ~540px. 240px proves graceful degradation
  // far past that. (Below ~200px the fixed section-count badge alone can't fit,
  // which the enforced window minimum makes unreachable.)
  for (final width in <double>[240, 360, 520, 760, 960]) {
    testWidgets('no overflow / layout errors at ${width.toInt()}px wide',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final st = PabloAppState();
      await tester.pumpWidget(harness(st));
      await tester.pump();

      // Any RenderFlex overflow / "no size" / hit-test error surfaces here.
      expect(tester.takeException(), isNull,
          reason: 'gallery threw a layout error at ${width}px wide');
    });
  }
}
