// trim_controller.dart — pure clamp/loop logic for non-destructive video trim
// (Picasa parity §11 moviestart/movieend). No player import: the lightbox video
// widget owns the VideoPlayerController and calls into this for the trim window,
// seek clamping, and end-of-range looping, so the arithmetic is unit-testable.

/// Trim window in milliseconds. [endMs] 0 means "to the end of the clip".
class TrimRange {
  const TrimRange({this.startMs = 0, this.endMs = 0});
  final int startMs;
  final int endMs;

  bool get isSet => startMs > 0 || endMs > 0;

  TrimRange copyWith({int? startMs, int? endMs}) =>
      TrimRange(startMs: startMs ?? this.startMs, endMs: endMs ?? this.endMs);
}

class TrimController {
  TrimController({required this.durationMs, this.range = const TrimRange()});

  /// Full clip length (ms).
  final int durationMs;

  /// The current trim window (mutable; also settable directly, e.g. on Clear).
  TrimRange range;

  int get startMs => range.startMs.clamp(0, durationMs);

  /// Effective end (ms): the set end, or the full duration when end is 0.
  int get endMs {
    final e = range.endMs <= 0 ? durationMs : range.endMs;
    return e.clamp(startMs, durationMs);
  }

  void setStart(int ms) {
    var s = ms.clamp(0, durationMs);
    // Keep start strictly before the effective end.
    if (range.endMs > 0 && s >= range.endMs) s = range.endMs - 1;
    range = range.copyWith(startMs: s < 0 ? 0 : s);
  }

  void setEnd(int ms) {
    final e = ms.clamp(startMs + 1, durationMs);
    // An end at the full duration is stored as 0 ("to the end").
    range = range.copyWith(endMs: e >= durationMs ? 0 : e);
  }

  /// Clamp a raw playback position into the trim window.
  int clampPosition(int posMs) => posMs.clamp(startMs, endMs);

  /// Given the current position, the next position after a tick: when playback
  /// reaches the trim end it wraps to the start ([loop]) or stops there.
  /// Returns (position, atEnd).
  ({int posMs, bool atEnd}) onTick(int posMs, {bool loop = true}) {
    if (posMs >= endMs) {
      return loop ? (posMs: startMs, atEnd: false) : (posMs: endMs, atEnd: true);
    }
    if (posMs < startMs) return (posMs: startMs, atEnd: false);
    return (posMs: posMs, atEnd: false);
  }
}
