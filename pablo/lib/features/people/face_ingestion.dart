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
import 'dart:io';

import 'package:photo_native/photo_native.dart';

import '../../app/app_state.dart';
import '../../backend/native_backend.dart';
import '../../data/models.dart';
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
  static const _exts = {'.jpg', '.jpeg', '.png', '.webp'};

  bool _running = false;

  /// Scan up to [cap] images from [dir]. Returns immediately if already
  /// running, the folder is empty/unreadable, or the controller isn't live.
  Future<void> ingestFolder(String dir, {int cap = 300}) async {
    if (_running || !controller.isLive) return;
    final files = _listImages(dir, cap);
    if (files.isEmpty) return;
    _running = true;
    final total = files.length;

    appState.startTask(TaskInfo(id: _taskId, name: 'Scanning faces', percent: 1));

    var scanned = 0;
    var rebuilt = false;
    StreamSubscription<PhotoEvent>? sub;
    Timer? quiesce;

    // Re-cluster once, after the whole scan batch lands. We can't rely on the
    // job lanes alone (a scan can complete after an eagerly-enqueued rebuild,
    // leaving it unclustered), so we trigger the rebuild when every asset has
    // reported, with a debounce fallback in case some emit no progress event.
    void finishRebuild() {
      if (rebuilt) return;
      rebuilt = true;
      controller.rebuildClusters();
    }

    sub = backend.events.listen((e) {
      if (e.kind == PhotoEventKind.scanProgress) {
        scanned++;
        // Scans take 0..95%; the cluster rebuild finishes the bar.
        appState.updateTaskPercent(_taskId, scanned / total * 95);
        quiesce?.cancel();
        if (scanned >= total) {
          finishRebuild();
        } else {
          quiesce = Timer(const Duration(seconds: 3), finishRebuild);
        }
      } else if (e.kind == PhotoEventKind.clusterUpdated) {
        appState.updateTaskPercent(_taskId, 100); // tickTasks() retires it
        sub?.cancel();
        _running = false;
      }
    });

    for (final path in files) {
      controller.scan(assetId: path.hashCode.abs(), path: path);
    }

    // Safety net: stop listening after a generous window even if the final
    // clusterUpdated never arrives.
    Timer(const Duration(minutes: 10), () {
      finishRebuild();
      sub?.cancel();
      _running = false;
    });
  }

  List<String> _listImages(String dir, int cap) {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return const [];
      final out = <String>[];
      for (final e in d.listSync(followLinks: false)) {
        if (e is! File) continue;
        final lower = e.path.toLowerCase();
        if (_exts.any(lower.endsWith)) {
          out.add(e.path);
          if (out.length >= cap) break;
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }
}
