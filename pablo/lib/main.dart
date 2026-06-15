import 'package:flutter/material.dart';

import 'app/pablo_app.dart';
import 'backend/native_backend.dart';
import 'utils/window_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();

  // Initialize the native photo backend. Returns null when the
  // PABLO_NATIVE_THUMBS flag is off or the engine fails to boot — either
  // way, the rest of the app falls back to the gradient mockup path.
  final backend = await NativeBackend.initialize();

  runApp(
    NativeBackendScope(
      backend: backend,
      child: const PabloApp(),
    ),
  );
}
