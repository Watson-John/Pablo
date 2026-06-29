// prefetch_controller.dart — speculative thumbnail warming.
//
// The native thumbnail cache is content-keyed (asset_id, stage, path), NOT
// slot-keyed, so decoding an asset through ANY slot makes the real grid tile a
// cache hit when it later mounts. This controller keeps a small pool of
// throwaway TextureSlots and, ahead of the scroll frontier, issues idle-lane
// thumbnail requests for upcoming assets through them. The published frames go
// to slots no Texture widget displays (so no compositor work); only the cache
// `put` matters.
//
// Lives next to NativeBackend (engine-coupled) and deliberately has NO gallery
// dependency: callers hand it the upcoming (assetId, path) pairs. The pure
// "which rows are next" math is unit-tested in justified_rows.dart.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

typedef PrefetchItem = ({int assetId, String path});

class PrefetchController {
  PrefetchController(this.engine);

  final Engine engine;

  // Throwaway slots the warmer round-robins through. Created lazily so a backend
  // that never scrolls a grid pays nothing.
  static const int _poolSize = 8;
  final List<TextureSlot> _slots = <TextureSlot>[];
  bool _poolStarting = false;
  int _next = 0;

  // Assets already warmed (bounded LRU so it can't grow without limit on a huge
  // library). Marked on enqueue so the same asset isn't warmed twice.
  static const int _warmedCap = 4096;
  final LinkedHashSet<int> _warmed = LinkedHashSet<int>();

  // Pending warm work + how many requests to issue per drain tick.
  static const int _maxPerDrain = 24;
  final Queue<PrefetchItem> _queue = Queue<PrefetchItem>();
  bool _draining = false;

  // Velocity gate: suppressed during fast flings (don't spend decodes on frames
  // whipping past), auto-resumes shortly after.
  bool _suppressed = false;
  Timer? _resume;

  bool _disposed = false;

  /// Pause warming briefly (called by the grid's scroll listener on a fast
  /// fling). New [warm] calls are ignored until it auto-resumes.
  void pauseBriefly([Duration after = const Duration(milliseconds: 250)]) {
    _suppressed = true;
    _resume?.cancel();
    _resume = Timer(after, () => _suppressed = false);
  }

  /// Queue idle-lane warming for [items] not already warmed. Cheap to call with
  /// whole look-ahead rows on every build.
  void warm(Iterable<PrefetchItem> items) {
    if (_disposed || _suppressed) return;
    var added = false;
    for (final it in items) {
      if (_warmed.contains(it.assetId)) continue;
      _markWarmed(it.assetId);
      _queue.add(it);
      added = true;
    }
    if (!added) return;
    if (_slots.isEmpty) {
      _ensurePool();
    } else {
      _scheduleDrain();
    }
  }

  void _markWarmed(int assetId) {
    _warmed.add(assetId);
    if (_warmed.length > _warmedCap) {
      // Evict the oldest ~quarter so warming a re-visited region can refire.
      final drop = _warmed.length - (_warmedCap * 3 ~/ 4);
      final it = _warmed.iterator;
      final old = <int>[];
      for (var i = 0; i < drop && it.moveNext(); i++) {
        old.add(it.current);
      }
      _warmed.removeAll(old);
    }
  }

  Future<void> _ensurePool() async {
    if (_poolStarting || _disposed) return;
    _poolStarting = true;
    for (var i = 0; i < _poolSize; i++) {
      try {
        final slot =
            await TextureSlot.create(engine, initialW: 64, initialH: 64);
        if (_disposed) {
          await slot.dispose();
          return;
        }
        _slots.add(slot);
      } catch (e) {
        debugPrint('[pablo] prefetch slot create failed: $e');
        break; // degrade: warm with whatever slots we got (possibly none)
      }
    }
    _poolStarting = false;
    if (_slots.isNotEmpty) _scheduleDrain();
  }

  void _scheduleDrain() {
    if (_draining || _disposed || _slots.isEmpty) return;
    _draining = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _draining = false;
    if (_disposed || _slots.isEmpty) return;
    var issued = 0;
    while (issued < _maxPerDrain && _queue.isNotEmpty) {
      final it = _queue.removeFirst();
      final slot = _slots[_next];
      _next = (_next + 1) % _slots.length;
      engine.requestThumbnail(
        assetId: it.assetId,
        slotId: slot.slotId,
        generation: slot.currentGeneration,
        path: it.path,
        targetW: 256,
        targetH: 256,
        wantedStagesMask: Stage.maskDefault,
        priority: Priority.idle,
      );
      issued++;
    }
    // More queued than this tick allowed — come back next microtask so a big
    // look-ahead doesn't burst the native job system all at once.
    if (_queue.isNotEmpty) _scheduleDrain();
  }

  Future<void> dispose() async {
    _disposed = true;
    _resume?.cancel();
    _queue.clear();
    final slots = List<TextureSlot>.from(_slots);
    _slots.clear();
    for (final s in slots) {
      await s.dispose();
    }
  }
}
