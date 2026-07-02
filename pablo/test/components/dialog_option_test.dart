// Widget tests for DialogOptionTile + PabloRadioDot: the tile renders its
// label and detail text, reflects selection in the border colour and the
// radio dot fill, and forwards taps.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pablo/components/dialog_option.dart';
import 'package:pablo/theme/tokens.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host({required bool selected, VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: DialogOptionTile(
              label: 'Save a copy',
              detail: 'Writes edits to a new file next to the original.',
              selected: selected,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      );

  // The tile's outer card is the first Container under DialogOptionTile
  // (the radio dot's Containers come later in the same subtree).
  BoxDecoration cardDecoration(WidgetTester tester) {
    final card = tester.widget<Container>(find
        .descendant(
            of: find.byType(DialogOptionTile), matching: find.byType(Container))
        .first);
    return card.decoration! as BoxDecoration;
  }

  testWidgets('renders label and detail text', (tester) async {
    await tester.pumpWidget(host(selected: false));
    expect(find.text('Save a copy'), findsOneWidget);
    expect(find.text('Writes edits to a new file next to the original.'),
        findsOneWidget);
  });

  testWidgets('selected tile shows the accent border and a filled radio dot',
      (tester) async {
    await tester.pumpWidget(host(selected: true));

    final deco = cardDecoration(tester);
    expect((deco.border! as Border).top.color, PabloColors.accentPrimary);
    expect(deco.color, PabloColors.accentBackground);

    // Selected dot: accent ring + an inner accent fill.
    final dotContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(PabloRadioDot), matching: find.byType(Container)))
        .toList();
    expect(dotContainers, hasLength(2));
    final ring = dotContainers[0].decoration! as BoxDecoration;
    expect((ring.border! as Border).top.color, PabloColors.accentPrimary);
    final fill = dotContainers[1].decoration! as BoxDecoration;
    expect(fill.color, PabloColors.accentPrimary);
  });

  testWidgets('unselected tile shows the neutral border and an empty dot',
      (tester) async {
    await tester.pumpWidget(host(selected: false));

    final deco = cardDecoration(tester);
    expect((deco.border! as Border).top.color, PabloColors.borderStrong);
    expect(deco.color, PabloColors.backgroundSurfaceAlt);

    // Unselected dot: neutral ring only, no inner fill.
    final dotContainers = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(PabloRadioDot), matching: find.byType(Container)))
        .toList();
    expect(dotContainers, hasLength(1));
    final ring = dotContainers[0].decoration! as BoxDecoration;
    expect((ring.border! as Border).top.color, PabloColors.borderStrong);
  });

  testWidgets('onTap fires when the tile is tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(selected: false, onTap: () => taps++));

    await tester.tap(find.byType(DialogOptionTile));
    await tester.pump();
    expect(taps, 1);
  });
}
