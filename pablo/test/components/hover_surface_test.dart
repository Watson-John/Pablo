// Widget tests for HoverSurface: the shared hover state machine. The builder
// must see hovered=true/false as a mouse pointer enters/exits, the gesture
// callbacks (tap / double-tap / right-click with global position) must fire,
// and onHoverChanged must report enter+exit for side-effect call sites.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/components/hover_surface.dart';

void main() {
  // A fixed-size host so the surface has a known hit area away from the
  // window edges (the mouse pointer starts at Offset.zero, outside it).
  Widget host(HoverSurface surface) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 200, height: 100, child: surface),
          ),
        ),
      );

  // A mouse pointer parked at the window origin, outside the centred surface.
  Future<TestGesture> mousePointer(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  testWidgets('builder receives hovered=true on enter and false on exit',
      (tester) async {
    await tester.pumpWidget(host(HoverSurface(
      builder: (context, hovered) => Text(hovered ? 'hover:on' : 'hover:off'),
    )));
    expect(find.text('hover:off'), findsOneWidget);

    final mouse = await mousePointer(tester);
    await mouse.moveTo(tester.getCenter(find.byType(HoverSurface)));
    await tester.pump();
    expect(find.text('hover:on'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('hover:off'), findsOneWidget);
  });

  testWidgets('onHoverChanged fires true on enter and false on exit',
      (tester) async {
    final events = <bool>[];
    await tester.pumpWidget(host(HoverSurface(
      onHoverChanged: events.add,
      builder: (context, hovered) => const SizedBox.expand(),
    )));

    final mouse = await mousePointer(tester);
    await mouse.moveTo(tester.getCenter(find.byType(HoverSurface)));
    await tester.pump();
    expect(events, [true]);

    // Moving within the surface must not re-fire.
    await mouse.moveTo(
        tester.getCenter(find.byType(HoverSurface)) + const Offset(10, 0));
    await tester.pump();
    expect(events, [true]);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(events, [true, false]);
  });

  testWidgets('onTap fires (after the double-tap window when both are set)',
      (tester) async {
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(host(HoverSurface(
      onTap: () => taps++,
      onDoubleTap: () => doubleTaps++,
      builder: (context, hovered) => const SizedBox.expand(),
    )));

    await tester.tap(find.byType(HoverSurface));
    // With onDoubleTap registered, the single tap is only confirmed once the
    // double-tap timeout expires.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(taps, 1);
    expect(doubleTaps, 0);
  });

  testWidgets('onDoubleTap fires on two quick taps', (tester) async {
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(host(HoverSurface(
      onTap: () => taps++,
      onDoubleTap: () => doubleTaps++,
      builder: (context, hovered) => const SizedBox.expand(),
    )));

    await tester.tap(find.byType(HoverSurface));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(HoverSurface));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(doubleTaps, 1);
    expect(taps, 0); // the pair resolved as a double tap, not two singles
  });

  testWidgets('onSecondaryTapDown receives the global position',
      (tester) async {
    Offset? received;
    await tester.pumpWidget(host(HoverSurface(
      onSecondaryTapDown: (globalPosition) => received = globalPosition,
      builder: (context, hovered) => const SizedBox.expand(),
    )));

    final center = tester.getCenter(find.byType(HoverSurface));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    addTearDown(gesture.removePointer);
    await tester.pump(kPressTimeout);
    await gesture.up();
    await tester.pump();

    expect(received, center);
  });
}
