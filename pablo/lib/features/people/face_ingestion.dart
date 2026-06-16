// FaceIngestion — drives a live face scan over a folder of images.
//
// For each image it enqueues a path-based scan (detect → align → embed →
// store, on the face job lane), then enqueues one cluster rebuild (lowest
// lane, so it runs after the scans drain). Progress is surfaced on the
// existing PabloAppState.tasks list, which the ActivityIndicator renders, by
// counting PHOTO_EVT_SCAN_PROGRESS / PHOTO_EVT_CLUSTER_UPDATED events. The
// repo's `changes` stream (fed by the same events) refreshes the People views
// as faces and clusters land.
//
// Live only — a no-op when the controller is backed by the mock repository.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/boot.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../utils/asset_id.dart';
import 'people_controller.dart';

class FaceIngestion {
  FaceIngestion({
    required this.backend,
    required this.controller,
    required this.appState,
  });

  final NativeBackend backend;
  final PeopleController controller;
  final PabloAppState appState;

  static const _taskId = 'face-scan';

  bool _running = false;

  /// The one eligibility predicate + construction shared by the auto-scan hook
  /// and the "Scan for Faces" menu action. Returns a callback that scans the
  /// imported library, or null when faces can't run live (no backend / mock /
  /// empty library) — so callers gate enablement on the null check alone.
  static VoidCallback? scanLibraryAction({
    required NativeBackend? backend,
    required PeopleController controller,
    required PabloAppState appState,
  }) {
    if (backend == null || !controller.isLive || Library.instance.isEmpty) {
      return null;
    }
    return () => FaceIngestion(
          backend: backend,
          controller: controller,
          appState: appState,
        ).ingestLibrary(cap: BootConfig.instance.faceScanCap);
  }

  /// Scan up to [cap] images from the imported library. Returns immediately if
  /// already running, the library is empty, or the controller isn't live.
  Future<void> ingestLibrary({int cap = 600}) async {
    if (_running || !controller.isLive) return;
    final all = Library.instance.allPhotos;
    final files = [
      for (final p in all.take(cap < 0 ? all.length : cap)) p.filePath,
    ];
    if (files.isEmpty) return;
    _running = true;
    final total = files.length;

    appState.startTask(TaskInfo(id: _taskId, name: 'Scanning faces', percent: 1));

    // Face scans run on the engine's idle lane, but each is long (~hundreds of
    // ms) and workers don't preempt. Submitting all at once lets the scan grab
    // every worker, so an interactive thumbnail (e.g. a photo just added to the
    // tray) waits for a worker to finish its current scan — a visible ~0.5s
    // lag. Keep only a window of scans in flight so ≥2 workers stay free to
    // satisfy thumbnail requests instantly.
    final maxInFlight = (Platform.numberOfProcessors - 3).clamp(2, 8);

    var scanned = 0; // completed (one per scanProgress)
    var submitted = 0; // requests sent
    var rebuilt = false;
    var done = false;
    StreamSubscription<PhotoEvent>? sub;
    Timer? quiesce; // debounce: have the scans stopped arriving?
    Timer? watchdog; // overall / post-rebuild safety timer

    void terminate() {
      if (done) return;
      done = true;
      quiesce?.cancel();
      watchdog?.cancel();
      sub?.cancel();
      _running = false;
    }

    // Re-cluster once, after the whole scan batch lands. The job lanes alone
    // don't guarantee ordering (a scan can finish after an eagerly-enqueued
    // rebuild), so we rebuild when every asset has reported — with a debounce
    // fallback if some emit no progress event. If the rebuild can't run (no
    // engine / request id 0) or clusterUpdated never arrives, a watchdog still
    // tears down so a later scan isn't blocked by a stuck `_running`.
    void finishRebuild() {
      if (rebuilt || done) return;
      rebuilt = true;
      quiesce?.cancel();
      final req = controller.rebuildClusters();
      appState.updateTaskPercent(_taskId, req == 0 ? 100 : 96);
      watchdog?.cancel();
      watchdog = Timer(Duration(seconds: req == 0 ? 0 : 30), () {
        appState.updateTaskPercent(_taskId, 100);
        terminate();
      });
    }

    // Top up the in-flight window: submit until [maxInFlight] are outstanding.
    void submitMore() {
      while (submitted < total && (submitted - scanned) < maxInFlight) {
        final path = files[submitted++];
        controller.scan(assetId: assetIdFor(path), path: path);
      }
    }

    sub = backend.events.listen((e) {
      if (done) return;
      if (e.kind == PhotoEventKind.scanProgress) {
        scanned++;
        submitMore(); // replace the finished scan, keeping the window full
        // Scans take 0..95%; the cluster rebuild finishes the bar.
        appState.updateTaskPercent(_taskId, (scanned / total * 95).clamp(1, 95));
        quiesce?.cancel();
        if (scanned >= total) {
          finishRebuild();
        } else {
          quiesce = Timer(const Duration(seconds: 3), finishRebuild);
        }
      } else if (e.kind == PhotoEventKind.clusterUpdated && rebuilt) {
        appState.updateTaskPercent(_taskId, 100); // tickTasks() retires it
        terminate();
      }
    });

    submitMore(); // prime the window

    // Safety net: if no scanProgress ever arrives, still rebuild + tear down.
    watchdog = Timer(const Duration(minutes: 10), finishRebuild);
  }
}
