// slideshow_controller.dart — pure playback state for the fullscreen slideshow
// (Picasa parity §10 Slideshow). No widgets: index, play/pause, interval, loop,
// and (seeded) shuffle live here so the timing logic is unit-testable under
// fakeAsync. The view listens and paints the current index; it owns nothing but
// pixels.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

class SlideshowController extends ChangeNotifier {
  SlideshowController({
    required this.count,
    this.interval = const Duration(seconds: 4),
    bool loop = true,
    bool shuffle = false,
    int start = 0,
    Random? random,
  })  : assert(count > 0),
        _loop = loop,
        _shuffle = shuffle,
        _random = random ?? Random() {
    _rebuildOrder(startAt: start);
  }

  /// Number of photos in the show.
  final int count;

  /// Auto-advance interval (mutable; a change re-arms the running timer).
  Duration interval;

  final Random _random;
  bool _loop;
  bool _shuffle;

  // The play order (identity or a shuffle) and our position within it. The
  // current photo is `_order[_pos]`.
  late List<int> _order;
  int _pos = 0;
  bool _playing = false;
  Timer? _timer;

  int get currentIndex => _order[_pos];
  bool get playing => _playing;
  bool get loop => _loop;
  bool get shuffle => _shuffle;

  /// True when a non-looping show has reached its final slide.
  bool get atEnd => !_loop && _pos >= count - 1;

  void _rebuildOrder({required int startAt}) {
    _order = List<int>.generate(count, (i) => i);
    if (_shuffle) {
      _order.shuffle(_random);
      // Put the requested start photo first so shuffle doesn't jump away from
      // whatever the user launched on.
      final at = _order.indexOf(startAt.clamp(0, count - 1));
      if (at > 0) {
        _order.removeAt(at);
        _order.insert(0, startAt.clamp(0, count - 1));
      }
      _pos = 0;
    } else {
      _pos = startAt.clamp(0, count - 1);
    }
  }

  void play() {
    if (_playing) return;
    _playing = true;
    _arm();
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  /// (Re)start the auto-advance timer. Called on play, on a manual nav while
  /// playing (so the user gets a full interval on the new slide), and on an
  /// interval change.
  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _advance(manual: false));
  }

  void setInterval(Duration value) {
    if (value == interval) return;
    interval = value;
    if (_playing) _arm();
    notifyListeners();
  }

  void setShuffle(bool value) {
    if (value == _shuffle) return;
    _shuffle = value;
    _rebuildOrder(startAt: currentIndex);
    if (_playing) _arm();
    notifyListeners();
  }

  void setLoop(bool value) {
    if (value == _loop) return;
    _loop = value;
    notifyListeners();
  }

  /// Advance one slide. Manual calls (arrow keys) re-arm the timer; auto ticks
  /// don't. At the end of a non-looping show, auto-advance pauses on the last
  /// slide.
  void _advance({required bool manual}) {
    if (_pos >= count - 1) {
      if (_loop) {
        _pos = 0;
      } else {
        // Reached the end of a one-shot show: stop here.
        pause();
        return;
      }
    } else {
      _pos++;
    }
    if (manual && _playing) _arm();
    notifyListeners();
  }

  void _retreat({required bool manual}) {
    if (_pos <= 0) {
      _pos = _loop ? count - 1 : 0;
    } else {
      _pos--;
    }
    if (manual && _playing) _arm();
    notifyListeners();
  }

  void next() => _advance(manual: true);
  void previous() => _retreat(manual: true);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
