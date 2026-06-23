// library_import.dart — drives the native catalog import and hydrates the
// stable path → asset_id mapping the rest of the app keys off.
//
// The native engine assigns each asset a stable id (a catalog rowid) that
// survives restarts, unlike the per-run path hash. Importing on boot and
// hydrating that mapping is what makes face data and the thumbnail cache
// persist across launches. [run] does the import + hydrate; [refresh] also
// re-walks the Dart library and rebuilds the gallery (wired to the Import
// button / "Scan for Faces" menu).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../app/app_state.dart';
import '../backend/native_backend.dart';
import '../utils/asset_id.dart';
import 'aspect_store.dart';
import 'library.dart';
import 'models.dart';

class LibraryImport {
  static const _taskId = 'import';

  /// Import [root] into the catalog, wait for completion, then install the
  /// stable path → asset_id mapping via [hydrateCatalogIds]. Returns the
  /// catalog asset count (0 when there is no catalog, e.g. a SQLite-less
  /// build). When [appState] is supplied, drives an "Importing photos"
  /// activity task.
  static Future<int> run({
    required NativeBackend backend,
    required String root,
    PabloAppState? appState,
  }) async {
    final req = backend.engine.importPath(root);
    if (req == 0) return 0; // no catalog — keep the hash-based fallback ids

    appState?.startTask(
        TaskInfo(id: _taskId, name: 'Importing photos', percent: 1));

    final done = Completer<void>();
    final sub = backend.events.listen((e) {
      if (e.requestId != req) return;
      if (e.kind == PhotoEventKind.importProgress) {
        if (e.aux64B > 0) {
          appState?.updateTaskPercent(
              _taskId, (e.aux64 / e.aux64B * 99).clamp(1, 99));
        }
      } else if (e.kind == PhotoEventKind.importComplete && !done.isCompleted) {
        done.complete();
      }
    });
    try {
      await done.future.timeout(const Duration(minutes: 10), onTimeout: () {});
    } finally {
      await sub.cancel();
    }

    final assets = backend.engine.listAssets();
    hydrateCatalogIds({for (final a in assets) a.path: a.assetId});
    appState?.updateTaskPercent(_taskId, 100); // tickTasks() retires it
    debugPrint('[pablo] catalog hydrated: ${assets.length} assets');
    return assets.length;
  }

  /// Re-walk the Dart library and re-import the catalog, then refresh the
  /// gallery (and re-arm the face auto-scan via [libraryRevision]). Wired to
  /// the Import button.
  static Future<void> refresh({
    required NativeBackend backend,
    required String root,
    required PabloAppState appState,
  }) async {
    final libFuture = Library.scanAsync(root);
    await run(backend: backend, root: root, appState: appState);
    Library.instance = await libFuture;
    libraryScanning = false;
    libraryRevision.value++;
    unawaited(AspectStore.instance
        .start(Library.instance.allPhotos.map((p) => p.filePath)));
  }
}
