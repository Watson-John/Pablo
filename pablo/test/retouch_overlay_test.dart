// Widget test for RetouchOverlay: a tap places a dab at the tapped normalized
// position with the current brush size, and the S/M/L + Undo chips work. The
// overlay writes straight into the injected EditSession, so we assert on its
// spec.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/edit_session.dart';
import 'package:pablo/features/editor/edit_spec.dart';
import 'package:pablo/features/editor/retouch_overlay.dart';

void main() {
  EditSession session() => EditSession(
        engine: null,
        assetId: 1,
        path: '/lib/a.jpg',
        saved: EditSpec(),
        contentRev: 0,
      );

  // The real lightbox image box is wide; use a comparable size so the tool bar
  // lays out without overflow and the chips are tappable.
  Widget host(EditSession s, String tool) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 700,
              height: 400,
              child: RetouchOverlay(session: s, tool: tool),
            ),
          ),
        ),
      );

  testWidgets('tap places a red-eye dab at the normalized position',
      (tester) async {
    final s = session();
    await tester.pumpWidget(host(s, 'redeye'));

    // Tap the centre of the 200x100 overlay.
    await tester.tapAt(tester.getCenter(find.byType(RetouchOverlay)));
    await tester.pump();

    expect(s.spec.redeye.length, 1);
    expect(s.spec.redeye[0].x, closeTo(0.5, 0.02));
    expect(s.spec.redeye[0].y, closeTo(0.5, 0.02));
    // Default red-eye brush.
    expect(s.spec.redeye[0].r, closeTo(0.035, 1e-3));
  });

  testWidgets('S/M/L chips set the brush size for the next dab',
      (tester) async {
    final s = session();
    await tester.pumpWidget(host(s, 'heal'));

    await tester.tap(find.text('L'));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byType(RetouchOverlay)));
    await tester.pump();

    expect(s.spec.heal.length, 1);
    expect(s.spec.heal[0].r, closeTo(0.09, 1e-3)); // 'L' size
  });

  testWidgets('tap on an existing dab removes it (per-eye veto)',
      (tester) async {
    final s = session();
    await tester.pumpWidget(host(s, 'redeye'));
    final center = tester.getCenter(find.byType(RetouchOverlay));

    // Place a dab, then tap the same spot: the dab is removed, not doubled.
    await tester.tapAt(center);
    await tester.pump();
    expect(s.spec.redeye.length, 1);
    await tester.tapAt(center);
    await tester.pump();
    expect(s.spec.redeye, isEmpty);

    // Two dabs; removing the first leaves the second untouched.
    await tester.tapAt(center);
    await tester.pump();
    await tester.tapAt(center + const Offset(120, 0));
    await tester.pump();
    expect(s.spec.redeye.length, 2);
    await tester.tapAt(center);
    await tester.pump();
    expect(s.spec.redeye.length, 1);
    expect(s.spec.redeye.single.x, greaterThan(0.5)); // the right-hand dab
  });

  testWidgets('Undo removes the last dab, Clear removes all', (tester) async {
    final s = session();
    await tester.pumpWidget(host(s, 'heal'));

    final center = tester.getCenter(find.byType(RetouchOverlay));
    await tester.tapAt(center);
    await tester.pump();
    // Outside the first dab's radius — a tap inside would REMOVE it (veto).
    await tester.tapAt(center + const Offset(120, 0));
    await tester.pump();
    expect(s.spec.heal.length, 2);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.spec.heal.length, 1);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(s.spec.heal, isEmpty);
  });
}
