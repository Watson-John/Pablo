import 'dart:async';

import 'package:flutter/material.dart';

import 'app/pablo_app.dart';
import 'backend/native_backend.dart';
import 'data/aspect_store.dart';
import 'data/boot.dart';
import 'data/library.dart';
import 'utils/window_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDesktopWindow();

  // Resolve what to import (default: the in-repo Flickr30k set).
  final config = BootConfig.resolve();
  BootConfig.instance = config;
  debugPrint(
    '[pablo] library root="${config.libraryRoot}" '
    'models="${config.modelsDir.isEmpty ? "(none)" : config.modelsDir}"',
  );

  // The library is scanned in the BACKGROUND (after runApp) so the first frame
  // paints immediately instead of freezing on a tens-of-thousands-of-files walk.
  Library.instance = Library.empty();
  libraryScanning = config.hasLibrary;

  // Initialize the native photo backend (on by default). Returns null when
  // disabled or the engine fails to boot; either way the app still runs and
  // unloaded thumbnails show a neutral loading surface.
  final backend = await NativeBackend.initialize(config);

  runApp(
    NativeBackendScope(
      backend: backend,
      child: const PabloApp(),
    ),
  );

  if (config.hasLibrary) {
    unawaited(_scanLibrary(config.libraryRoot));
  }
}

/// Scan the library off the first-frame path, then swap it in and notify the
/// app to rebuild (and kick off the face scan) against the real data.
Future<void> _scanLibrary(String root) async {
  final lib = await Library.scanAsync(root);
  Library.instance = lib;
  libraryScanning = false;
  libraryRevision.value++;
  // Read real aspect ratios in the background so the justified grid lays tiles
  // out at their true shape (off the UI thread; never blocks the first frame).
  unawaited(AspectStore.instance.start(lib.allPhotos.map((p) => p.filePath)));
  debugPrint(
    '[pablo] library ready: photos=${lib.allPhotos.length} '
    'folders=${lib.folderSections.length}',
  );
}
