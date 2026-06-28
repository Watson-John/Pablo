// Headless widget test for the Find Duplicates flow: verifies the scope stage
// renders and advancing to review shows the exact/similar sections, the
// similarity slider, the keeper-rule controls, and the quarantine action.
//
// A golden ("screenshot") of the review stage is generated when run with
// --dart-define=GOLDEN=true (kept out of normal CI runs, which are cross-OS and
// would mismatch a single platform's golden).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/components/pablo_button.dart';
import 'package:pablo/components/pablo_slider.dart';
import 'package:pablo/features/find_duplicates/find_duplicates_flow.dart';

Widget _harness() => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: AppScope(
          notifier: PabloAppState(),
          child: const FindDuplicatesFlow(),
        ),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('scope → review shows exact, similar, slider, controls', (tester) async {
    tester.view.physicalSize = const Size(1280, 820); // the app runs ≥1280 wide
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Stage 1 — scope picker.
    expect(find.textContaining('Where should we look'), findsOneWidget);
    expect(find.text('Entire library'), findsOneWidget);
    expect(find.text('Specific folders'), findsOneWidget);

    // Run the scan (entire library is the default scope).
    final scanBtn = find.widgetWithText(PabloButton, 'Find Duplicates');
    await tester.ensureVisible(scanBtn);
    await tester.tap(scanBtn);
    await tester.pumpAndSettle();

    // Stage 2 — review chrome (always on screen).
    expect(find.text('Exact duplicates'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget); // keeper-rule control bar
    expect(find.text('Highest res'), findsOneWidget); // a keeper rule chip
    expect(find.text('Auto-select duplicates'), findsOneWidget);
    expect(find.textContaining('Quarantine'), findsWidgets); // apply bar

    // The slider then the similar section live further down the lazy list. The
    // slider row precedes the similar header, so reveal it first.
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byType(PabloSlider), 400, scrollable: list);
    expect(find.byType(PabloSlider), findsOneWidget); // similarity slider
    await tester.scrollUntilVisible(find.text('Similar images'), 400, scrollable: list);
    expect(find.text('Similar images'), findsOneWidget);
  });

  testWidgets('golden: review stage', (tester) async {
    tester.view.physicalSize = const Size(1280, 820); // matches the app window
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PabloButton, 'Find Duplicates'));
    await tester.pumpAndSettle();

    // Mark a few non-keepers for removal so the discard overlay shows.
    await tester.tap(find.text('Auto-select duplicates'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(FindDuplicatesFlow),
      matchesGoldenFile('goldens/find_duplicates_review.png'),
    );
  }, skip: !const bool.fromEnvironment('GOLDEN'));
}
