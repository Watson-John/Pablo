// Background embedding runner lifecycle: throttle window, resume, pause/resume,
// cancel, retry, duplicate-worker prevention, failure handling (Stage 9).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/indexing/indexing_controller.dart';
import 'package:photo_native/photo_native.dart'
    show EmbeddingCounts, PhotoEvent, PhotoEventKind;

PhotoEvent _embed(int assetId, int status) => PhotoEvent(
      kind: PhotoEventKind.embedProgress,
      stage: 0,
      status: status,
      width: 0,
      height: 0,
      requestId: 0,
      assetId: assetId,
      slotId: 0,
      generation: 0,
      aux64: 1,
      aux64B: 0,
    );

class FakeBackend implements EmbeddingBackend {
  FakeBackend(this._pending);
  List<int> _pending;
  final _ctrl = StreamController<PhotoEvent>.broadcast();
  final scanned = <int>[];
  int retryCalls = 0;

  @override
  List<int> pendingIds() => List.of(_pending);
  @override
  int scan(int assetId) {
    scanned.add(assetId);
    return assetId;
  }

  @override
  void retryFailed() => retryCalls++;
  @override
  EmbeddingCounts counts() => const EmbeddingCounts.empty();
  @override
  Stream<PhotoEvent> get events => _ctrl.stream;

  void emit(int assetId, {int status = 0}) => _ctrl.add(_embed(assetId, status));
  void setPending(List<int> p) => _pending = p;
  Future<void> close() => _ctrl.close();
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('throttles submissions to maxInFlight and refills on completion',
      () async {
    final b = FakeBackend([1, 2, 3, 4, 5]);
    final c = IndexingController(b, maxInFlight: 2);
    addTearDown(b.close);

    expect(c.start(), isTrue);
    expect(b.scanned, [1, 2]); // window of 2

    b.emit(1);
    await _tick();
    expect(b.scanned, [1, 2, 3]); // refilled one

    b.emit(2);
    b.emit(3);
    await _tick();
    expect(b.scanned, [1, 2, 3, 4, 5]);
    expect(c.isRunning, isTrue);

    b.emit(4);
    b.emit(5);
    await _tick();
    expect(c.phase, IndexPhase.done);
    expect(c.progress.completed, 5);
    expect(c.progress.isDone, isTrue);
  });

  test('counts skipped and failed without wedging the run', () async {
    final b = FakeBackend([1, 2, 3]);
    final c = IndexingController(b, maxInFlight: 3);
    addTearDown(b.close);
    c.start();

    b.emit(1, status: 0); // done
    b.emit(2, status: 7); // skipped (unsupported)
    b.emit(3, status: 4); // failed (decode error)
    await _tick();

    expect(c.progress.completed, 1);
    expect(c.progress.skipped, 1);
    expect(c.progress.failed, 1);
    expect(c.phase, IndexPhase.done); // finished despite the failure
  });

  test('start is a no-op while running (no duplicate worker)', () async {
    final b = FakeBackend([1, 2, 3, 4]);
    final c = IndexingController(b, maxInFlight: 2);
    addTearDown(b.close);

    expect(c.start(), isTrue);
    expect(c.start(), isFalse); // second call rejected
    expect(b.scanned, [1, 2]); // not double-submitted
  });

  test('pause halts new submissions; resume continues', () async {
    final b = FakeBackend([1, 2, 3, 4]);
    final c = IndexingController(b, maxInFlight: 1);
    addTearDown(b.close);
    c.start();
    expect(b.scanned, [1]);

    c.pause();
    b.emit(1);
    await _tick();
    expect(b.scanned, [1]); // paused → no refill
    expect(c.phase, IndexPhase.paused);

    c.resume();
    await _tick();
    expect(b.scanned, [1, 2]); // resumed → one more
  });

  test('cancel clears the queue and returns to idle', () async {
    final b = FakeBackend([1, 2, 3, 4, 5]);
    final c = IndexingController(b, maxInFlight: 2);
    addTearDown(b.close);
    c.start();
    c.cancel();
    expect(c.phase, IndexPhase.idle);

    // Late events after cancel don't advance progress.
    b.emit(1);
    await _tick();
    expect(c.progress.completed, 0);
  });

  test('resumes from the native pending set after an interruption', () async {
    final b = FakeBackend([1, 2, 3]);
    final c = IndexingController(b, maxInFlight: 3);
    addTearDown(b.close);
    c.start();
    b.emit(1);
    b.emit(2);
    await _tick();
    c.cancel();

    // Two were completed + persisted; only 3 remains pending on resume.
    b.scanned.clear();
    b.setPending([3]);
    expect(c.start(), isTrue);
    expect(b.scanned, [3]); // does NOT re-embed 1 and 2
  });

  test('retryFailed re-queues failed rows and restarts', () async {
    final b = FakeBackend([]);
    final c = IndexingController(b, maxInFlight: 2);
    addTearDown(b.close);
    // Nothing pending initially → start is a no-op/done.
    c.start();
    expect(c.phase, IndexPhase.done);

    b.setPending([9]); // a previously-failed row, now flipped to pending
    c.retryFailed();
    expect(b.retryCalls, 1);
    expect(b.scanned, [9]);
  });

  test('safe-mode recommendation is threshold-based', () {
    expect(IndexingController.recommendSafeMode(10), isFalse);
    expect(
        IndexingController.recommendSafeMode(
            IndexingController.safeModeThreshold + 1),
        isTrue);
  });

  test('onDrained fires when the run finishes and when cancelled', () async {
    final b = FakeBackend([1, 2]);
    var drained = 0;
    final c = IndexingController(b, maxInFlight: 2, onDrained: () => drained++);
    addTearDown(b.close);
    expect(c.start(), isTrue);
    expect(drained, 0); // still running
    b.emit(1, status: 0);
    b.emit(2, status: 0);
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, IndexPhase.done);
    expect(drained, 1); // queue drained → image tower released

    // A cancelled run also releases (indexing stopped, tower not needed).
    b.setPending([3]);
    expect(c.start(), isTrue);
    c.cancel();
    expect(drained, 2);
  });
}
