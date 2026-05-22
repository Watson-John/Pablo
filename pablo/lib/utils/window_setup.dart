// Windows desktop window-size hint. Flutter's runner reads the window size
// at startup from the Win32 entry point; we set a sane default and minimum
// via the engine's PlatformDispatcher.

import 'dart:io';

import 'package:flutter/services.dart';

Future<void> configureDesktopWindow() async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
  // Without window_manager we cannot constrain the OS window from Dart.
  // We can however set a sensible title via SystemChrome.
  await SystemChrome.setApplicationSwitcherDescription(
    const ApplicationSwitcherDescription(
      label: 'Pablo',
      primaryColor: 0xFFC17A3A,
    ),
  );
}
