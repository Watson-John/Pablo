// aspect_store.dart — real per-photo aspect ratios (width / height), read from
// file headers off the UI thread.
//
// The justified gallery grid needs each image's TRUE aspect to size tiles
// without cropping. Reading 31k headers on the main isolate (even chunked)
// would jank; reading them at boot would freeze the first frame. So a single
// long-lived background isolate reads headers via the pure [readImageDimensions]
// and streams results back in batches. The grid prioritizes the photos it's
// about to paint so the visible rows resolve first; the rest backfill.
//
// Until a photo's real aspect is known, callers use a neutral 1.0 placeholder
// (NOT a hash guess) so the layout is complete and only corrects in magnitude,
// never flipping portrait↔landscape.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../utils/image_dims.dart';

class AspectStore {
  AspectStore._();
  static final AspectStore instance = AspectStore._();

  final Map<String, double> _aspect = {};

  /// Bumps (coalesced) whenever a batch of aspects lands, so the grid re-packs.
  final ValueNotifier<int> aspectRevision = ValueNotifier<int>(0);

  /// Real aspect (w/h) for [path], or null if not read yet.
  double? aspectOf(String path) => _aspect[path];

  SendPort? _toIsolate;
  bool _started = false;
  final List<Object> _pending = []; // commands queued before the handshake
  final Set<String> _prioritized = {};
  Timer? _coalesce;

  /// Begin reading aspects for [paths] in the background. Idempotent: a second
  /// call just enqueues more paths.
  Future<void> start(Iterable<String> paths) async {
    final list = paths.toList(growable: false);
    if (_started) {
      _send({'enqueue': list});
      return;
    }
    _started = true;
    final fromIsolate = ReceivePort();
    fromIsolate.listen((msg) {
      if (msg is SendPort) {
        _toIsolate = msg;
        for (final c in _pending) {
          msg.send(c);
        }
        _pending.clear();
        msg.send({'enqueue': list});
        return;
      }
      if (msg is Map) {
        msg.forEach((k, v) {
          if (k is String && v is num) _aspect[k] = v.toDouble();
        });
        _coalesce ??= Timer(const Duration(milliseconds: 24), () {
          _coalesce = null;
          aspectRevision.value++;
        });
      }
    });
    try {
      await Isolate.spawn(_isolateEntry, fromIsolate.sendPort);
    } catch (e) {
      debugPrint('[pablo] aspect isolate spawn failed: $e');
      _started = false;
      fromIsolate.close();
    }
  }

  /// Ask the isolate to read [paths] next (front of queue). Already-known or
  /// already-requested paths are skipped, so callers can pass whole rows cheaply
  /// on every build.
  void prioritize(List<String> paths) {
    List<String>? fresh;
    for (final p in paths) {
      if (_aspect.containsKey(p)) continue;
      if (_prioritized.add(p)) (fresh ??= []).add(p);
    }
    if (fresh != null) _send({'prioritize': fresh});
  }

  void _send(Object cmd) {
    final to = _toIsolate;
    if (to == null) {
      _pending.add(cmd);
    } else {
      to.send(cmd);
    }
  }
}

// ── Background isolate ───────────────────────────────────────────────────────

void _isolateEntry(SendPort toMain) {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  final processed = <String>{};
  final backlog = <String>[]; // sequential backfill
  var cursor = 0;
  final front =
      <String>[]; // priority (FIFO from the end via removeAt(0) is O(n);
  // kept small since callers only push unknown rows)
  var draining = false;

  Future<void> drain() async {
    if (draining) return;
    draining = true;
    const batchCap = 256;
    while (true) {
      final batch = <String, double>{};
      var read = 0;
      while (read < batchCap) {
        String? p;
        if (front.isNotEmpty) {
          p = front.removeAt(0);
        } else if (cursor < backlog.length) {
          p = backlog[cursor++];
        } else {
          break;
        }
        if (!processed.add(p)) continue; // already done
        final dims = readImageDimensions(p);
        if (dims != null && dims.height > 0) batch[p] = dims.aspect;
        read++;
      }
      if (batch.isNotEmpty) toMain.send(batch);
      if (front.isEmpty && cursor >= backlog.length) break;
      // Yield so incoming enqueue/prioritize messages are processed, then loop.
      await Future<void>.delayed(Duration.zero);
    }
    draining = false;
  }

  fromMain.listen((msg) {
    if (msg is! Map) return;
    final enqueue = msg['enqueue'];
    if (enqueue is List) {
      for (final p in enqueue) {
        if (p is String) backlog.add(p);
      }
    }
    final prioritize = msg['prioritize'];
    if (prioritize is List) {
      for (final p in prioritize) {
        if (p is String && !processed.contains(p)) front.add(p);
      }
    }
    drain();
  });
}
