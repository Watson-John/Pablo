// export_controller_test.dart — the pure export logic: collision-safe
// destination naming, watermark colour packing, and the async batch tracker
// that turns N submitted requests + a completion-event stream into one result.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/export/export_controller.dart';

void main() {
  group('exportDestination', () {
    test('maps to <folder>/<stem>.jpg', () {
      final taken = <String>{};
      final dst = exportDestination(
        folder: '/out',
        srcPath: '/lib/sub/photo.png',
        taken: taken,
        exists: (_) => false,
      );
      expect(dst, '/out/photo.jpg');
      expect(taken, contains('/out/photo.jpg'));
    });

    test('suffixes -1, -2 on within-batch collisions', () {
      final taken = <String>{};
      final a = exportDestination(
          folder: '/out', srcPath: '/a/photo.jpg', taken: taken, exists: (_) => false);
      final b = exportDestination(
          folder: '/out', srcPath: '/b/photo.jpg', taken: taken, exists: (_) => false);
      final c = exportDestination(
          folder: '/out', srcPath: '/c/photo.jpg', taken: taken, exists: (_) => false);
      expect(a, '/out/photo.jpg');
      expect(b, '/out/photo-1.jpg');
      expect(c, '/out/photo-2.jpg');
    });

    test('avoids names already on disk', () {
      final taken = <String>{};
      final dst = exportDestination(
        folder: '/out',
        srcPath: '/a/photo.jpg',
        taken: taken,
        exists: (p) => p == '/out/photo.jpg',
      );
      expect(dst, '/out/photo-1.jpg');
    });

    test('handles a stem with no extension', () {
      final dst = exportDestination(
        folder: '/out',
        srcPath: '/a/README',
        taken: <String>{},
        exists: (_) => false,
      );
      expect(dst, '/out/README.jpg');
    });
  });

  group('watermarkArgb', () {
    test('packs opacity percent into the alpha byte, white RGB', () {
      expect(watermarkArgb(100), 0xFFFFFFFF);
      expect(watermarkArgb(0), 0x00FFFFFF);
      expect(watermarkArgb(50), 0x80FFFFFF); // 128 = round(50*255/100)
    });

    test('clamps out-of-range percent', () {
      expect(watermarkArgb(150), 0xFFFFFFFF);
      expect(watermarkArgb(-10), 0x00FFFFFF);
    });
  });

  group('ExportBatchTracker', () {
    test('counts every accepted request as it completes', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final progress = <(int, int)>[];
      final tracker = ExportBatchTracker(
        completions: ctl.stream,
        onProgress: (d, t) => progress.add((d, t)),
      );
      // Submit ids 10,11,12.
      final future = tracker.run(3, (i) => 10 + i);
      ctl.add((requestId: 11, status: 0));
      ctl.add((requestId: 10, status: 0));
      ctl.add((requestId: 12, status: 0));
      final result = await future;
      expect(result.total, 3);
      expect(result.ok, 3);
      expect(result.failed, 0);
      expect(result.allOk, isTrue);
      expect(progress.last, (3, 3));
      await ctl.close();
    });

    test('counts a non-OK status as failed', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final tracker = ExportBatchTracker(completions: ctl.stream);
      final future = tracker.run(2, (i) => 100 + i);
      ctl.add((requestId: 100, status: 0));
      ctl.add((requestId: 101, status: 5)); // IO_ERROR
      final result = await future;
      expect(result.ok, 1);
      expect(result.failed, 1);
      expect(result.allOk, isFalse);
      await ctl.close();
    });

    test('a rejected submit (id 0) is an immediate failure', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final tracker = ExportBatchTracker(completions: ctl.stream);
      // index 1 rejected; only id 42 will report.
      final future = tracker.run(2, (i) => i == 0 ? 42 : 0);
      ctl.add((requestId: 42, status: 0));
      final result = await future;
      expect(result.total, 2);
      expect(result.ok, 1);
      expect(result.failed, 1);
      await ctl.close();
    });

    test('ignores completion events for unrelated request ids', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final tracker = ExportBatchTracker(completions: ctl.stream);
      final future = tracker.run(1, (_) => 7);
      ctl.add((requestId: 999, status: 0)); // not ours — ignored
      ctl.add((requestId: 7, status: 0));
      final result = await future;
      expect(result.ok, 1);
      expect(result.failed, 0);
      await ctl.close();
    });

    test('completes immediately when all submits are rejected', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final tracker = ExportBatchTracker(completions: ctl.stream);
      final result = await tracker.run(2, (_) => 0);
      expect(result.ok, 0);
      expect(result.failed, 2);
      await ctl.close();
    });

    test('timeout counts still-pending requests as failed', () async {
      final ctl = StreamController<({int requestId, int status})>();
      final tracker = ExportBatchTracker(completions: ctl.stream);
      final future = tracker.run(2, (i) => 200 + i,
          timeout: const Duration(milliseconds: 50));
      ctl.add((requestId: 200, status: 0)); // only one reports
      final result = await future;
      expect(result.ok, 1);
      expect(result.failed, 1); // 201 never reported
      await ctl.close();
    });
  });
}
