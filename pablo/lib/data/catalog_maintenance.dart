// catalog_maintenance.dart — drives the native catalog VACUUM off the UI
// thread, surfacing it as a background activity task that retires when the
// PHOTO_EVT_MAINTENANCE_COMPLETE event arrives.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../app/app_state.dart';
import '../backend/native_backend.dart';
import 'models.dart';

class CatalogMaintenance {
  static const _taskId = 'compact';

  /// Checkpoint + VACUUM the catalog on the native idle lane. Drives a
  /// "Compacting database" activity task until the completion event fires, then
  /// logs the reclaimed bytes. No-op without a native backend.
  static Future<void> compact({
    required NativeBackend? backend,
    required PabloAppState appState,
  }) async {
    if (backend == null) return;
    final before = backend.engine.catalogStats();
    final req = backend.engine.compactCatalog();
    if (req == 0) return; // no catalog (e.g. SQLite-less build)

    appState.startTask(
        TaskInfo(id: _taskId, name: 'Compacting database', percent: 30));

    final done = Completer<void>();
    final sub = backend.events.listen((e) {
      if (e.kind == PhotoEventKind.maintenanceComplete &&
          e.requestId == req &&
          !done.isCompleted) {
        done.complete();
      }
    });
    try {
      await done.future.timeout(const Duration(minutes: 5), onTimeout: () {});
    } finally {
      await sub.cancel();
    }
    appState.updateTaskPercent(_taskId, 100); // tickTasks() retires it

    final after = backend.engine.catalogStats();
    if (before != null && after != null) {
      debugPrint('[pablo] catalog compacted: ${before.sizeBytes} -> '
          '${after.sizeBytes} bytes (${before.reclaimableBytes} reclaimable)');
    }
  }
}
