// caption_store.dart — user-authored captions, read from the native catalog
// off the build path and cached.
//
// Captions live catalog-only (Decision D1): `engine.organize(assetId).caption`
// reads them, `engine.setCaption(assetId, text)` writes them. Like the star
// state in library.dart they are kept OFF the immutable [Photo] (mutable
// catalog state). This store mirrors [AspectStore]'s background-read pattern:
// the gallery prioritizes the photos it's about to paint, captions resolve in
// small batches, and a coalesced [captionRevision] tells the grid to repaint.
//
// `captionOf` distinguishes three states:
//   • null  — not read yet (caller should [prioritize] it)
//   • ''     — read, no caption (don't show, don't re-read)
//   • text   — the caption to display
//
// With no native engine (tests, backend disabled) every read is a no-op and
// captions simply never appear.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart' show Engine;

class CaptionStore {
  CaptionStore._();
  static final CaptionStore instance = CaptionStore._();

  Engine? _engine;

  /// Wire up the live engine (called once at startup). Idempotent.
  void attach(Engine engine) => _engine = engine;

  final Map<int, String> _caption = <int, String>{};

  /// Bumps (coalesced) whenever a batch of captions lands or one is edited, so
  /// the grid + lightbox repaint.
  final ValueNotifier<int> captionRevision = ValueNotifier<int>(0);

  /// Caption for [assetId]: the text, '' when read-but-empty, or null when not
  /// read yet.
  String? captionOf(int assetId) => _caption[assetId];

  final List<int> _queue = <int>[];
  final Set<int> _queued = <int>{};
  Timer? _drain;
  Timer? _coalesce;

  /// Enqueue background reads for [assetIds] not already read/queued. Cheap to
  /// call with whole rows on every build.
  void prioritize(Iterable<int> assetIds) {
    if (_engine == null) return;
    var added = false;
    for (final id in assetIds) {
      if (_caption.containsKey(id) || !_queued.add(id)) continue;
      _queue.add(id);
      added = true;
    }
    if (added) _scheduleDrain();
  }

  void _scheduleDrain() {
    _drain ??= Timer(const Duration(milliseconds: 16), _drainBatch);
  }

  void _drainBatch() {
    _drain = null;
    final engine = _engine;
    if (engine == null) {
      _queue.clear();
      _queued.clear();
      return;
    }
    const batchCap = 64;
    var read = 0;
    var changed = false;
    while (read < batchCap && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _queued.remove(id);
      final org = engine.organize(id);
      _caption[id] = org?.caption ?? '';
      if ((org?.caption ?? '').isNotEmpty) changed = true;
      read++;
    }
    if (changed) _bump();
    if (_queue.isNotEmpty) _scheduleDrain();
  }

  /// Persist [text] for [assetId] (empty clears it) and update the cache.
  /// Returns the native status (0 == OK), or -1 with no engine.
  int setCaption(int assetId, String text) {
    final engine = _engine;
    if (engine == null) return -1;
    final status = engine.setCaption(assetId, text);
    _caption[assetId] = text;
    _bump();
    return status;
  }

  void _bump() {
    _coalesce ??= Timer(const Duration(milliseconds: 24), () {
      _coalesce = null;
      captionRevision.value++;
    });
  }
}
