// Regression test for the right-click context menu (PabloContextMenu.show).
//
// The menu is shown via an OverlayEntry whose body is a Stack with a
// Positioned(left, top, child: _MenuSurface). A Positioned with no `width`
// (and no `right`) lays its child out with `const BoxConstraints()` — fully
// UNBOUNDED width — so the inner _MenuRow's Row/Expanded threw
// "RenderFlex children have non-zero flex but incoming width constraints are
// unbounded", taking down the render tree (subsequent hit-tests then failed
// with "Cannot hit test a render box with no size"). The fix gives the
// Positioned a bounded width, mirroring the menu bar's dropdown panel.
//
// This locks the regression: showing the menu must not throw.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/components/context_menu.dart';

void main() {
  testWidgets('PabloContextMenu.show renders without an unbounded-width '
      'layout exception', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          ctx = context;
          return const SizedBox.expand();
        }),
      ),
    ));

    final entry = PabloContextMenu.show(
      ctx,
      position: const Offset(100, 100),
      items: [
        ContextMenuItem(label: 'Open', onPressed: () {}),
        ContextMenuItem.separator(),
        ContextMenuItem(label: 'Delete', destructive: true, onPressed: () {}),
      ],
    );
    await tester.pump();

    // Before the fix this rebuild threw a FlutterError during layout; takeException
    // would return it here. After the fix the menu lays out cleanly.
    expect(tester.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    entry.remove();
    await tester.pump();
  });
}
