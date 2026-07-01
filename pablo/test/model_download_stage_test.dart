// ModelDownloadStage: progress rows + MB counters, the error state with a
// working Retry, and the Skip escape hatch.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/model_fetcher.dart';
import 'package:pablo/features/search/model_download_stage.dart';

const _specs = [
  ModelSpec(
    assetName: 'semantic_image.fp16.onnx',
    destName: 'semantic_image.onnx',
    sha256: 'PENDING',
    bytes: 10 * 1024 * 1024,
  ),
  ModelSpec(
    assetName: 'semantic_tokenizer.model',
    destName: 'semantic_tokenizer.model',
    sha256: 'PENDING',
    bytes: 1024 * 1024,
  ),
];

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('renders the title, per-file bars and MB counters', (t) async {
    final gate = Completer<void>();
    late ModelProgress report;
    await t.pumpWidget(_host(ModelDownloadStage(
      specs: _specs,
      download: (p) {
        report = p;
        return gate.future;
      },
      onComplete: () {},
      onSkip: () {},
    )));

    expect(find.text('Downloading search model'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    // Before any progress the counters show 0 against the estimated size.
    expect(find.text('0.0 / 10.0 MB'), findsOneWidget);

    report('semantic_image.onnx', 5 * 1024 * 1024, 10 * 1024 * 1024);
    await t.pump();
    expect(find.text('5.0 / 10.0 MB'), findsOneWidget);
    expect(
      find.text('Skip — search works without it, with reduced quality'),
      findsOneWidget,
    );

    gate.complete();
    await t.pump();
  });

  testWidgets('shows the error state and Retry restarts the download',
      (t) async {
    var calls = 0;
    var completed = false;
    await t.pumpWidget(_host(ModelDownloadStage(
      specs: _specs,
      download: (p) async {
        calls++;
        if (calls == 1) throw ModelFetchException('connection reset');
      },
      onComplete: () => completed = true,
      onSkip: () {},
    )));
    await t.pump();

    expect(find.text('Download failed'), findsOneWidget);
    expect(find.textContaining('connection reset'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await t.tap(find.text('Retry'));
    await t.pump();
    expect(calls, 2);
    await t.pump();
    expect(completed, isTrue);
    expect(find.text('Download failed'), findsNothing);
  });

  testWidgets('the Skip button invokes onSkip', (t) async {
    var skipped = false;
    final gate = Completer<void>();
    await t.pumpWidget(_host(ModelDownloadStage(
      specs: _specs,
      download: (_) => gate.future,
      onComplete: () {},
      onSkip: () => skipped = true,
    )));

    await t.tap(find.textContaining('Skip — search works without it'));
    expect(skipped, isTrue);

    gate.complete();
    await t.pump();
  });
}
