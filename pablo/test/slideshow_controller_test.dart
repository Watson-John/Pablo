// slideshow_controller_test.dart — the pure playback state machine: interval
// auto-advance (fakeAsync), seeded shuffle, loop vs stop-at-end, pause, and
// manual-nav timer reset.

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/slideshow/slideshow_controller.dart';

void main() {
  test('auto-advances on the interval while playing', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 3, interval: const Duration(seconds: 2));
      expect(c.currentIndex, 0);
      c.play();
      async.elapse(const Duration(seconds: 2));
      expect(c.currentIndex, 1);
      async.elapse(const Duration(seconds: 2));
      expect(c.currentIndex, 2);
      c.dispose();
    });
  });

  test('loops past the end when loop is on', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 2, interval: const Duration(seconds: 1), loop: true);
      c.play();
      async.elapse(const Duration(seconds: 1)); // 0 -> 1
      async.elapse(const Duration(seconds: 1)); // 1 -> 0 (wrap)
      expect(c.currentIndex, 0);
      c.dispose();
    });
  });

  test('stops on the last slide when loop is off', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 2, interval: const Duration(seconds: 1), loop: false);
      c.play();
      async.elapse(const Duration(seconds: 1)); // 0 -> 1 (last)
      expect(c.currentIndex, 1);
      async.elapse(const Duration(seconds: 5)); // auto-advance paused at end
      expect(c.currentIndex, 1);
      expect(c.playing, isFalse);
      expect(c.atEnd, isTrue);
      c.dispose();
    });
  });

  test('pause suppresses further ticks', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 5, interval: const Duration(seconds: 1));
      c.play();
      async.elapse(const Duration(seconds: 1)); // -> 1
      c.pause();
      async.elapse(const Duration(seconds: 10));
      expect(c.currentIndex, 1);
      c.dispose();
    });
  });

  test('manual next while playing resets the auto-advance timer', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 5, interval: const Duration(seconds: 4));
      c.play();
      async.elapse(const Duration(seconds: 3)); // almost due
      c.next(); // -> 1, timer re-armed
      async.elapse(const Duration(seconds: 3)); // 3s < 4s: no auto tick yet
      expect(c.currentIndex, 1);
      async.elapse(const Duration(seconds: 1)); // now 4s since manual -> 2
      expect(c.currentIndex, 2);
      c.dispose();
    });
  });

  test('previous wraps to the last slide when looping', () {
    final c = SlideshowController(count: 3, loop: true);
    expect(c.currentIndex, 0);
    c.previous();
    expect(c.currentIndex, 2);
    c.dispose();
  });

  test('shuffle is deterministic for a fixed seed and starts on start index',
      () {
    final a = SlideshowController(
        count: 6, shuffle: true, start: 2, random: Random(42));
    final b = SlideshowController(
        count: 6, shuffle: true, start: 2, random: Random(42));
    expect(a.currentIndex, 2); // start photo first
    final seqA = <int>[a.currentIndex];
    final seqB = <int>[b.currentIndex];
    for (var i = 0; i < 5; i++) {
      a.next();
      b.next();
      seqA.add(a.currentIndex);
      seqB.add(b.currentIndex);
    }
    expect(seqA, seqB); // same seed → same order
    expect(seqA.toSet(), {0, 1, 2, 3, 4, 5}); // a permutation of all indices
    a.dispose();
    b.dispose();
  });

  test('setInterval re-arms a running timer', () {
    fakeAsync((async) {
      final c = SlideshowController(
          count: 4, interval: const Duration(seconds: 5));
      c.play();
      c.setInterval(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      expect(c.currentIndex, 1);
      c.dispose();
    });
  });
}
