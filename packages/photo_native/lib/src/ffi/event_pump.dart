// event_pump.dart — drains photo_poll_events into Dart Streams.
//
// Pull-based per the C ABI: Dart polls on its own schedule rather than the
// native side calling back into Dart. M1 drains via Timer.periodic; M2 may
// move the drain into a worker isolate via SendPort if main-isolate latency
// becomes an issue.

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'core_api.dart';

abstract final class PhotoEventKind {
  static const int stageReady = 1;
  static const int stageFailed = 2;
  static const int importProgress = 3;
  static const int importComplete = 4;
  static const int scanProgress = 5;
  static const int clusterUpdated = 6;
  static const int providerProbed = 7;
  static const int log = 8;
  static const int maintenanceComplete = 9;
}

/// Immutable Dart-side projection of a native [NativeEvent].
final class PhotoEvent {
  const PhotoEvent({
    required this.kind,
    required this.stage,
    required this.status,
    required this.width,
    required this.height,
    required this.requestId,
    required this.assetId,
    required this.slotId,
    required this.generation,
    required this.aux64,
    required this.aux64B,
    this.reserved0 = 0,
    this.reserved1 = 0,
  });

  final int kind;
  final int stage;
  final int status;
  final int width;
  final int height;
  final int requestId;
  final int assetId;
  final int slotId;
  final int generation;
  final int aux64;
  final int aux64B;
  final int reserved0;
  final int reserved1;

  // ── Incremental-rescan summary on an importComplete event ──
  // (aux64 = added, aux64B = updated, reserved0 = skipped, reserved1 = removed)
  int get importAdded => aux64;
  int get importUpdated => aux64B;
  int get importSkipped => reserved0;
  int get importRemoved => reserved1;
}

final class EventPump {
  EventPump(this._engine, {Duration interval = const Duration(milliseconds: 8)})
    : _interval = interval;

  final Engine _engine;
  final Duration _interval;

  static const int _batchSize = 64;
  Pointer<NativeEvent>? _buffer;

  final _controller = StreamController<PhotoEvent>.broadcast();
  Timer? _timer;

  Stream<PhotoEvent> get stream => _controller.stream;

  void start() {
    if (_timer != null) return;
    _buffer ??= calloc<NativeEvent>(_batchSize);
    _timer = Timer.periodic(_interval, (_) => _drain());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    _controller.close();
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
    }
  }

  void _drain() {
    final buf = _buffer;
    if (buf == null) return;
    // Drain the ENTIRE ring each tick. The native event ring is bounded and
    // drops events when full; polling a single batch let the backlog grow during
    // scroll bursts until it overflowed, silently losing STAGE_READY upgrades —
    // so thumbnails stayed stuck on the low-res placeholder and never sharpened.
    // Looping until a short read empties the ring every tick. Each event comes
    // from a multi-ms decode, so producers can't refill a full batch between our
    // back-to-back polls; the loop always terminates promptly.
    int n;
    do {
      n = _engine.pollEvents(buf, _batchSize);
      for (var i = 0; i < n; i++) {
        final e = buf[i];
        _controller.add(
          PhotoEvent(
            kind: e.kind,
            stage: e.stage,
            status: e.status,
            width: e.width,
            height: e.height,
            requestId: e.request_id,
            assetId: e.asset_id,
            slotId: e.slot_id,
            generation: e.generation,
            aux64: e.aux64,
            aux64B: e.aux64_b,
            reserved0: e.reserved[0],
            reserved1: e.reserved[1],
          ),
        );
      }
    } while (n == _batchSize);
  }
}
