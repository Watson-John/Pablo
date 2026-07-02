// Widget test for CurvesEditor — in particular that it re-syncs its displayed
// control points when the session's curve is cleared externally (footer Reset /
// Revert to Original), rather than lingering on a stale bent curve. A live GUI
// smoke surfaced the stale-display bug this guards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/curves_editor.dart';
import 'package:pablo/features/editor/edit_session.dart';
import 'package:pablo/features/editor/edit_spec.dart';

void main() {
  EditSession session() => EditSession(
        engine: null,
        assetId: 1,
        path: '/lib/a.jpg',
        saved: EditSpec(),
        contentRev: 0,
      );

  Widget host(EditSession s) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: CurvesEditor(session: s),
            ),
          ),
        ),
      );

  testWidgets('bending the curve writes control points to the session',
      (tester) async {
    final s = session();
    await tester.pumpWidget(host(s));
    // Drag from the centre downward to add + pull a midtone point below the
    // diagonal (non-identity).
    await tester.dragFrom(
        tester.getCenter(find.byType(CurvesEditor)), const Offset(0, 30));
    await tester.pump();
    expect(s.spec.curve.length, 3); // 2 endpoints + 1 dragged point
    expect(s.spec.curveIsIdentity, isFalse);
    await tester.pump(const Duration(milliseconds: 400)); // flush double-tap timer
  });

  testWidgets('re-syncs to identity after an external reset (no stale points)',
      (tester) async {
    final s = session();
    await tester.pumpWidget(host(s));

    // Bend the curve.
    await tester.dragFrom(
        tester.getCenter(find.byType(CurvesEditor)), const Offset(0, 30));
    await tester.pump();
    expect(s.spec.curve.length, 3);

    // The footer's Reset clears the working spec out from under the editor.
    s.resetAdjustments();
    await tester.pump();
    expect(s.spec.curve, isEmpty);

    // Adding a fresh point must now start from the identity diagonal (2 points)
    // → yielding exactly 3. If the editor had NOT re-synced, its stale 3 points
    // plus the new one would commit 4 — which is the bug this asserts against.
    final box = tester.getRect(find.byType(CurvesEditor));
    await tester.dragFrom(
        Offset(box.left + box.width * 0.25, box.center.dy), const Offset(0, 20));
    await tester.pump();
    expect(s.spec.curve.length, 3);
    await tester.pump(const Duration(milliseconds: 400)); // flush double-tap timer
  });
}
