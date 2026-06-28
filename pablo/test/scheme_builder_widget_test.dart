// Widget-level checks for the storage-scheme builder: the live preview renders
// the engine's output, and the builder presents the folder-structure and
// file-name stages as two distinct, separately-titled cards.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/scheme_engine.dart';
import 'package:pablo/features/organize/scheme_presets.dart';
import 'package:pablo/features/organize/scheme_preview_tree.dart';
import 'package:pablo/features/organize/storage_scheme_modal.dart';

void main() {
  testWidgets('preview tree renders folders and the file name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SchemePreviewTree(
            scheme: byYearMonthDay(),
            samples: [
              PhotoMeta(
                fileMtime: DateTime(2024, 3, 15),
                captureDate: DateTime(2024, 3, 15),
                originalName: 'IMG_1',
                ext: '.jpg',
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('2024'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget); // the highlighted leaf
  });

  testWidgets('builder shows the two distinct stages', (tester) async {
    final state = PabloAppState()
      ..schemes.addAll(buildPresetSchemes());
    state.activeSchemeId = state.schemes.first.id;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StorageSchemeModal(appState: state, onClose: () {}),
      ),
    ));
    await tester.pump();

    expect(find.text('Organization scheme'), findsOneWidget);
    expect(find.text('Folder structure'), findsOneWidget);
    expect(find.text('File name'), findsOneWidget);
  });
}
