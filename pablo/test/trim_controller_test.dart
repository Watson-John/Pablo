// trim_controller_test.dart — pure clamp/loop logic for video trim: effective
// end (0 = full duration), start/end clamping, position clamping, and the
// end-of-window loop vs stop.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/video/trim_controller.dart';

void main() {
  test('no trim: effective window is the whole clip', () {
    final c = TrimController(durationMs: 10000);
    expect(c.range.isSet, isFalse);
    expect(c.startMs, 0);
    expect(c.endMs, 10000); // end 0 → full duration
  });

  test('setStart / setEnd clamp into the clip and store end as 0 at duration',
      () {
    final c = TrimController(durationMs: 10000);
    c.setStart(2000);
    c.setEnd(8000);
    expect(c.startMs, 2000);
    expect(c.endMs, 8000);

    c.setEnd(10000); // end at the full duration is stored as 0 ("to the end")
    expect(c.range.endMs, 0);
    expect(c.endMs, 10000);

    c.setStart(-500); // clamps to 0
    expect(c.startMs, 0);
  });

  test('start is kept before the end', () {
    final c = TrimController(durationMs: 10000);
    c.setEnd(4000);
    c.setStart(9000); // past the end → pinned just before it
    expect(c.startMs, lessThan(4000));
  });

  test('clampPosition keeps playback inside the window', () {
    final c = TrimController(
        durationMs: 10000, range: const TrimRange(startMs: 3000, endMs: 7000));
    expect(c.clampPosition(1000), 3000);
    expect(c.clampPosition(5000), 5000);
    expect(c.clampPosition(9000), 7000);
  });

  test('onTick loops to start at the end when looping', () {
    final c = TrimController(
        durationMs: 10000, range: const TrimRange(startMs: 3000, endMs: 7000));
    final r = c.onTick(7000, loop: true);
    expect(r.posMs, 3000);
    expect(r.atEnd, isFalse);
  });

  test('onTick stops at the end when not looping', () {
    final c = TrimController(
        durationMs: 10000, range: const TrimRange(startMs: 3000, endMs: 7000));
    final r = c.onTick(7500, loop: false);
    expect(r.posMs, 7000);
    expect(r.atEnd, isTrue);
  });

  test('onTick with end=0 uses the full duration as the boundary', () {
    final c = TrimController(
        durationMs: 5000, range: const TrimRange(startMs: 1000));
    // Below the effective end (5000) → unchanged.
    expect(c.onTick(4000, loop: true).posMs, 4000);
    // At/after duration → wraps to start.
    expect(c.onTick(5000, loop: true).posMs, 1000);
  });
}
