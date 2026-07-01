// indexing_controller.dart — the resumable, throttled semantic-embedding runner
// (Stage 9).
//
// This is the "background worker" for embedding generation. It mirrors the face
// ingestion windowing but for the embedding phase, and adds explicit lifecycle
// control (pause / resume / cancel / retry) and DB-persisted resumability.
//
// Scheduling contract (the Stage-9 requirements):
//   • Resumable: the work list is (re)built from the native `pending` queue, so
//     an interrupted run picks up exactly where it left off — completed rows are
//     persisted and never re-embedded.
//   • Throttled: at most [maxInFlight] embeds are in flight at once, and every
//     job runs on the native IDLE lane (thumbnails/interaction always preempt),
//     so the UI stays responsive.
//   • Faces-then-embeddings: the app starts this controller only AFTER the face
//     pass, so the two heavy ML passes never run at full tilt together.
//   • No duplicate workers: [start] is a no-op while already running; the native
//     `pending` query + single-writer catalog make a second process idempotent.
//   • Fails safe: a corrupt/unsupported image is counted (skipped/failed) and the
//     run continues — one bad image can never wedge indexing.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart'
    show EmbeddingCounts, PhotoEvent, PhotoEventKind;

/// The backend the controller drives. The app wires [NativeEmbeddingBackend]
/// over the Engine; tests inject a fake.
abstract class EmbeddingBackend {
  /// Asset ids still needing embedding for the active model (the resume queue).
  List<int> pendingIds();

  /// Schedule embedding for one asset (idle lane). Returns a request id.
  int scan(int assetId);

  /// Flip failed rows back to pending (so the next [start] re-queues them).
  void retryFailed();

  /// Progress counts for the UI (done/pending/failed/skipped/total).
  EmbeddingCounts counts();

  /// PHOTO_EVT_EMBED_PROGRESS events fire here as each embed finishes.
  Stream<PhotoEvent> get events;
}

enum IndexPhase { idle, running, paused, done }

/// Immutable progress snapshot for the UI.
@immutable
class IndexingProgress {
  const IndexingProgress({
    required this.phase,
    required this.completed,
    required this.failed,
    required this.skipped,
    required this.total,
  });

  final IndexPhase phase;
  final int completed;
  final int failed;
  final int skipped;
  final int total;

  int get settled => completed + failed + skipped;
  int get pending => (total - settled).clamp(0, total);
  double get fraction => total == 0 ? 1.0 : settled / total;
  bool get isDone => phase == IndexPhase.done || (total > 0 && settled >= total);
}

class IndexingController extends ChangeNotifier {
  IndexingController(this._backend, {this.maxInFlight = 3, this.onDrained});

  final EmbeddingBackend _backend;

  /// Concurrency cap. Small by default so embedding never saturates the box.
  final int maxInFlight;

  /// Fired when the run drains (finished or cancelled) — the app hooks this to
  /// `Engine.releaseSemanticSessions(releaseImageTower)` so the image encoder's
  /// ~hundreds of MB are reclaimed the moment indexing stops. The next run
  /// transparently reloads it (~1 s).
  final void Function()? onDrained;

  /// Libraries with more than this many pending items use the safe first-launch
  /// indexing screen instead of rendering the full grid mid-index.
  static const int safeModeThreshold = 400;

  /// Pure helper: should the app show the blocking safe-indexing screen?
  static bool recommendSafeMode(int pendingCount) =>
      pendingCount > safeModeThreshold;

  IndexPhase _phase = IndexPhase.idle;
  final _queue = <int>[];
  int _inFlight = 0;
  int _completed = 0, _failed = 0, _skipped = 0, _total = 0;
  StreamSubscription<PhotoEvent>? _sub;

  IndexPhase get phase => _phase;
  bool get isRunning => _phase == IndexPhase.running;

  IndexingProgress get progress => IndexingProgress(
        phase: _phase,
        completed: _completed,
        failed: _failed,
        skipped: _skipped,
        total: _total,
      );

  /// Begin (or resume) indexing. Returns false (no-op) if already running
  /// (duplicate-worker prevention) or nothing is pending.
  bool start() {
    if (_phase == IndexPhase.running) return false; // no duplicate worker
    final ids = _backend.pendingIds();
    _queue
      ..clear()
      ..addAll(ids);
    if (_queue.isEmpty) {
      _phase = IndexPhase.done;
      _total = _completed = _failed = _skipped = 0;
      notifyListeners();
      return false;
    }
    _total = _queue.length;
    _completed = _failed = _skipped = _inFlight = 0;
    _phase = IndexPhase.running;
    _sub ??= _backend.events
        .where((e) => e.kind == PhotoEventKind.embedProgress)
        .listen(_onProgress);
    _pump();
    notifyListeners();
    return true;
  }

  /// Suspend submission (in-flight jobs still land; no new ones start).
  void pause() {
    if (_phase != IndexPhase.running) return;
    _phase = IndexPhase.paused;
    notifyListeners();
  }

  void resume() {
    if (_phase != IndexPhase.paused) return;
    _phase = IndexPhase.running;
    _pump();
    notifyListeners();
  }

  /// Stop and clear the queue. Completed rows stay persisted, so a later
  /// [start] resumes from the native pending set.
  void cancel() {
    _queue.clear();
    _teardown();
    _phase = IndexPhase.idle;
    onDrained?.call();
    notifyListeners();
  }

  /// Re-queue failed rows and (re)start.
  void retryFailed() {
    _backend.retryFailed();
    if (_phase != IndexPhase.running) start();
  }

  void _pump() {
    if (_phase != IndexPhase.running) return;
    while (_inFlight < maxInFlight && _queue.isNotEmpty) {
      _backend.scan(_queue.removeAt(0));
      _inFlight++;
    }
    if (_inFlight == 0 && _queue.isEmpty) _finish();
  }

  void _onProgress(PhotoEvent e) {
    if (_phase == IndexPhase.idle) return; // cancelled
    if (_inFlight > 0) _inFlight--;
    // status: 0=OK(done), 7=UNSUPPORTED(skipped), else failed (see engine).
    if (e.status == 0) {
      _completed++;
    } else if (e.status == 7) {
      _skipped++;
    } else {
      _failed++;
    }
    notifyListeners();
    _pump();
  }

  void _finish() {
    _teardown();
    _phase = IndexPhase.done;
    onDrained?.call();
    notifyListeners();
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _inFlight = 0;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

/// [EmbeddingBackend] over the native Engine + its event stream.
class NativeEmbeddingBackend implements EmbeddingBackend {
  NativeEmbeddingBackend({
    required int Function(int assetId) scanFn,
    required List<int> Function() pendingFn,
    required void Function() retryFn,
    required EmbeddingCounts Function() countsFn,
    required Stream<PhotoEvent> eventStream,
  })  : _scan = scanFn,
        _pending = pendingFn,
        _retry = retryFn,
        _counts = countsFn,
        _events = eventStream;

  final int Function(int) _scan;
  final List<int> Function() _pending;
  final void Function() _retry;
  final EmbeddingCounts Function() _counts;
  final Stream<PhotoEvent> _events;

  @override
  List<int> pendingIds() => _pending();
  @override
  int scan(int assetId) => _scan(assetId);
  @override
  void retryFailed() => _retry();
  @override
  EmbeddingCounts counts() => _counts();
  @override
  Stream<PhotoEvent> get events => _events;
}
