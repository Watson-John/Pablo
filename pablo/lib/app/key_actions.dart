// key_actions.dart — app-shell keyboard bindings for file-operation undo
// (Cmd+Z on macOS, Ctrl+Z elsewhere).
//
// Uses a HardwareKeyboard handler rather than a Shortcuts widget on purpose:
// a shell-level Shortcuts map sits between the focus tree's text fields and
// their DefaultTextEditingShortcuts, stealing ⌘Z from typing. Here we
// explicitly YIELD whenever focus sits inside an EditableText (search field,
// editor text inputs), so text undo stays native and only gallery-level ⌘Z
// reverses file operations.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class KeyActions extends StatefulWidget {
  const KeyActions({required this.onUndo, required this.child, super.key});

  /// Invoked on Cmd/Ctrl+Z when no text field owns focus.
  final VoidCallback onUndo;
  final Widget child;

  @override
  State<KeyActions> createState() => _KeyActionsState();
}

class _KeyActionsState extends State<KeyActions> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  bool _handle(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyZ) return false;
    final kb = HardwareKeyboard.instance;
    final primary = defaultTargetPlatform == TargetPlatform.macOS
        ? kb.isMetaPressed
        : kb.isControlPressed;
    if (!primary || kb.isShiftPressed || kb.isAltPressed) return false;
    if (_focusInsideEditableText()) return false; // let text undo happen
    widget.onUndo();
    return true; // consumed
  }

  static bool _focusInsideEditableText() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
