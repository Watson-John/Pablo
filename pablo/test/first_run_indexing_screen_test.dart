// Safe first-launch indexing screen: shows per-phase progress with the four
// completed/pending/skipped/failed counts (Stage 9).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/indexing/indexing_controller.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/search/first_run_indexing_screen.dart';
import 'package:photo_native/photo_native.dart'
    show EmbeddingCounts, PhotoEvent, PhotoEventKind;

class _Fake implements EmbeddingBackend {
  _Fake(this.pending);
  List<int> pending;
  final _ctrl = StreamController<PhotoEvent>.broadcast();
  @override
  List<int> pendingIds() => List.of(pending);
  @override
  int scan(int assetId) => assetId;
  @override
  void retryFailed() {}
  @override
  EmbeddingCounts counts() => const EmbeddingCounts.empty();
  @override
  Stream<PhotoEvent> get events => _ctrl.stream;
  void emit(int id, int status) => _ctrl.add(PhotoEvent(
        kind: PhotoEventKind.embedProgress,
        stage: 0,
        status: status,
        width: 0,
        height: 0,
        requestId: 0,
        assetId: id,
        slotId: 0,
        generation: 0,
        aux64: 1,
        aux64B: 0,
      ));
  Future<void> close() => _ctrl.close();
}

void main() {
  testWidgets('renders both phases and the four embedding counts', (t) async {
    final backend = _Fake([1, 2, 3, 4]);
    addTearDown(backend.close);
    final indexing = IndexingController(backend, maxInFlight: 4);
    // Drive the controller with REAL async (broadcast-stream delivery) outside
    // the widget test's FakeAsync clock, then pump.
    await t.runAsync(() async {
      indexing.start();
      backend.emit(1, 0); // done
      backend.emit(2, 7); // skipped
      backend.emit(3, 4); // failed
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    final state = PabloAppState()
      ..indexing = indexing
      ..startTask(
          TaskInfo(id: 'face-scan', name: 'Scanning faces', percent: 60));

    await t.pumpWidget(MaterialApp(
      home: AppScope(
        notifier: state,
        child: const Scaffold(body: FirstRunIndexingScreen()),
      ),
    ));
    await t.pump();

    expect(find.text('Preparing your library'), findsOneWidget);
    expect(find.text('Facial recognition'), findsOneWidget);
    expect(find.text('Semantic index'), findsOneWidget);
    // Four counts surfaced (completed 1, skipped 1, failed 1, pending 1).
    expect(
      find.textContaining('Completed 1'),
      findsOneWidget,
    );
    expect(find.textContaining('Failed 1'), findsOneWidget);
    expect(find.text('Continue in background →'), findsOneWidget);
  });

  testWidgets('shows the model download stage before the indexing phases',
      (t) async {
    final state = PabloAppState();
    final gate = Completer<void>();
    var ready = false;
    await t.pumpWidget(MaterialApp(
      home: AppScope(
        notifier: state,
        child: Scaffold(
          body: FirstRunIndexingScreen(
            needsModelDownload: true,
            modelDownload: (_) => gate.future,
            onModelsReady: () => ready = true,
          ),
        ),
      ),
    ));

    // Download stage renders ABOVE the two indexing phases.
    expect(find.text('Downloading search model'), findsOneWidget);
    expect(find.text('Facial recognition'), findsOneWidget);
    expect(find.text('Semantic index'), findsOneWidget);

    gate.complete();
    await t.pump();
    expect(find.text('Downloading search model'), findsNothing);
    expect(ready, isTrue);
  });
}
