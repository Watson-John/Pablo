// key_actions_test.dart — Cmd/Ctrl+Z fires the file-op undo, but YIELDS to
// focused text fields so typing undo stays native.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/key_actions.dart';

void main() {
  Future<int> pumpAndPress(
    WidgetTester tester, {
    required TargetPlatform platform,
    required LogicalKeyboardKey modifier,
    bool focusTextField = false,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      var undos = 0;
      await tester.pumpWidget(MaterialApp(
        home: KeyActions(
          onUndo: () => undos++,
          child: const Scaffold(body: TextField()),
        ),
      ));
      if (focusTextField) {
        await tester.tap(find.byType(TextField));
        await tester.pump();
      }
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      return undos;
    } finally {
      // Must happen inside the test body — the binding asserts all foundation
      // debug variables are back to defaults before tearDowns run.
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('⌘Z triggers undo on macOS when no text field has focus',
      (tester) async {
    final undos = await pumpAndPress(tester,
        platform: TargetPlatform.macOS, modifier: LogicalKeyboardKey.metaLeft);
    expect(undos, 1);
  });

  testWidgets('Ctrl+Z triggers undo on Windows/Linux', (tester) async {
    final undos = await pumpAndPress(tester,
        platform: TargetPlatform.windows,
        modifier: LogicalKeyboardKey.controlLeft);
    expect(undos, 1);
  });

  testWidgets('yields to a focused text field (text undo stays native)',
      (tester) async {
    final undos = await pumpAndPress(tester,
        platform: TargetPlatform.macOS,
        modifier: LogicalKeyboardKey.metaLeft,
        focusTextField: true);
    expect(undos, 0);
  });

  testWidgets('ignores Z without the platform modifier and Shift+mod+Z',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      var undos = 0;
      await tester.pumpWidget(MaterialApp(
        home: KeyActions(
          onUndo: () => undos++,
          child: const Scaffold(body: SizedBox()),
        ),
      ));
      // Bare Z.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      // Shift+⌘Z (a redo chord elsewhere — not ours).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      // Ctrl+Z on macOS (wrong modifier for the platform).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(undos, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
