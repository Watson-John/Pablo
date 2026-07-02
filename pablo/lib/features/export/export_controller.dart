// export_controller.dart — pure batch-export logic (Picasa parity §10 Export).
//
// The dialog resolves WHICH photos to export (tray, else the current photo)
// and the destination folder; this file owns everything testable without an
// engine: collision-safe destination naming, watermark colour math, and the
// request-id bookkeeping that turns N async PHOTO_EVT_EXPORT_COMPLETE events
// into one "Exported N of M" result. The native submit itself is injected, so
// tests drive the tracker with a plain stream.

import 'dart:async';
import 'dart:io';

/// User-facing options captured by the export dialog (persisted in AppConfig
/// between runs). `maxDim` bounds the long edge (0 = original size); the
/// watermark applies when `watermarkText` is non-empty.
class ExportSettings {
  const ExportSettings({
    required this.folder,
    this.maxDim = 0,
    this.quality = 92,
    this.watermarkText = '',
    this.watermarkOpacityPct = 50,
  });

  final String folder;
  final int maxDim;
  final int quality;
  final String watermarkText;
  final int watermarkOpacityPct;
}

/// White watermark colour with [opacityPct] (0..100) in the alpha byte —
/// the 0xAARRGGBB form photo_export_options_t expects.
int watermarkArgb(int opacityPct) {
  final a = ((opacityPct.clamp(0, 100)) * 255 / 100).round();
  return (a << 24) | 0x00FFFFFF;
}

/// Destination `<folder>/<stem>.jpg` for [srcPath], suffixing `-1`, `-2`, …
/// when the name is already claimed — batch exports flatten many source
/// folders into one destination, so basename collisions are routine. A name is
/// claimed when it is in [taken] (this batch) or [exists] says it's on disk.
/// The chosen path is added to [taken].
String exportDestination({
  required String folder,
  required String srcPath,
  required Set<String> taken,
  bool Function(String path)? exists,
}) {
  final fileExists = exists ?? (p) => File(p).existsSync();
  final base = srcPath.split(Platform.pathSeparator).last;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final sep = folder.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator;
  var candidate = '$folder$sep$stem.jpg';
  var n = 1;
  while (taken.contains(candidate) || fileExists(candidate)) {
    candidate = '$folder$sep$stem-$n.jpg';
    n++;
  }
  taken.add(candidate);
  return candidate;
}

class ExportBatchResult {
  const ExportBatchResult({
    required this.total,
    required this.ok,
    required this.failed,
  });

  final int total;
  final int ok;
  final int failed;

  bool get allOk => ok == total;
}

/// Turns N submitted export requests + the engine's completion events into one
/// awaitable result with running progress. Feed it a stream of
/// `(requestId, status)` records filtered to PHOTO_EVT_EXPORT_COMPLETE
/// (status 0 = OK); [run] subscribes BEFORE submitting so no event can be
/// missed, and requests the engine rejected outright (id 0) count as failures.
class ExportBatchTracker {
  ExportBatchTracker({required this.completions, this.onProgress});

  final Stream<({int requestId, int status})> completions;

  /// Called after every settled item with (done, total).
  final void Function(int done, int total)? onProgress;

  final Set<int> _pending = <int>{};
  int _ok = 0;
  int _failed = 0;
  int _total = 0;
  bool _submitted = false;
  StreamSubscription<({int requestId, int status})>? _sub;
  Timer? _timer;
  final Completer<ExportBatchResult> _done = Completer<ExportBatchResult>();

  /// Submit [count] items via [submit] (index → native request id, 0 =
  /// rejected) and complete when every accepted request has reported, or when
  /// [timeout] elapses (still-pending items count as failed).
  Future<ExportBatchResult> run(
    int count,
    int Function(int index) submit, {
    Duration timeout = const Duration(minutes: 10),
  }) {
    _total = count;
    _sub = completions.listen(_onEvent);
    for (var i = 0; i < count; i++) {
      final req = submit(i);
      if (req == 0) {
        _failed++;
      } else {
        _pending.add(req);
      }
    }
    _submitted = true;
    _report();
    _timer = Timer(timeout, _finish);
    _maybeFinish();
    return _done.future;
  }

  void _onEvent(({int requestId, int status}) e) {
    if (!_pending.remove(e.requestId)) return;
    if (e.status == 0) {
      _ok++;
    } else {
      _failed++;
    }
    _report();
    _maybeFinish();
  }

  void _report() => onProgress?.call(_ok + _failed, _total);

  void _maybeFinish() {
    if (_submitted && _pending.isEmpty) _finish();
  }

  void _finish() {
    if (_done.isCompleted) return;
    _failed += _pending.length; // timeout: whatever never reported
    _pending.clear();
    _timer?.cancel();
    unawaited(_sub?.cancel());
    _done.complete(
        ExportBatchResult(total: _total, ok: _ok, failed: _failed));
  }
}
