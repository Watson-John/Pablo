import 'dart:async';

import 'package:flutter/material.dart';

import 'app/pablo_app.dart';
import 'backend/native_backend.dart';
import 'data/aspect_store.dart';
import 'data/caption_store.dart';
import 'data/boot.dart';
import 'data/library.dart';
import 'data/library_import.dart';
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
  if (backend != null) CaptionStore.instance.attach(backend.engine);

  runApp(
    NativeBackendScope(
      backend: backend,
      child: const PabloApp(),
    ),
  );

  if (config.hasLibrary) {
    unawaited(_scanLibrary(config.libraryRoot, backend));
  }
}

/// Scan the library off the first-frame path, then swap it in and notify the
/// app to rebuild (and kick off the face scan) against the real data.
///
/// The Dart filesystem walk (for the gallery) and the native catalog import
/// (for stable asset ids) run in parallel; the catalog ids are hydrated BEFORE
/// the gallery + face auto-scan see the library, so faces and the thumbnail
/// cache key off ids that survive a restart.
Future<void> _scanLibrary(String root, NativeBackend? backend) async {
  final libFuture = Library.scanAsync(root);
  final importFuture = backend == null
      ? Future<int>.value(0)
      : LibraryImport.run(backend: backend, root: root);
  final lib = await libFuture;
  await importFuture;
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
