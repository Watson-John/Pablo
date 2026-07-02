// export_dialog_test.dart — the export options dialog. Injects an AppConfig so
// the test never reads or writes the machine's persisted settings.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/app_config.dart';
import 'package:pablo/features/export/export_controller.dart';
import 'package:pablo/features/export/export_dialog.dart';

AppConfig _cfg({String folder = ''}) =>
    AppConfig(catalogDir: '/tmp/cat', exportFolder: folder);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Export is disabled until a folder is chosen', (t) async {
    await t.pumpWidget(_host(ExportDialog(count: 3, initialConfig: _cfg())));
    await t.pump();

    // The header reflects the batch count.
    expect(find.text('Export 3 photos'), findsOneWidget);
    expect(find.text('No folder chosen'), findsOneWidget);

    // Export button is present but non-functional (onPressed null).
    final exportBtn = find.widgetWithText(GestureDetector, 'Export');
    // Tapping does nothing → the dialog stays open (no pop).
    await t.tap(find.text('Export'));
    await t.pump();
    expect(find.text('Export 3 photos'), findsOneWidget);
    expect(exportBtn, findsWidgets);
  });

  testWidgets('with a folder, Export returns settings', (t) async {
    ExportSettings? result;
    await t.pumpWidget(_host(Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          result = await showDialog<ExportSettings>(
            context: context,
            builder: (_) =>
                ExportDialog(count: 1, initialConfig: _cfg(folder: '/out')),
          );
        },
        child: const Text('open'),
      );
    })));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Header singular; the chosen folder shows instead of the empty hint.
    expect(find.text('Export photo'), findsOneWidget);
    expect(find.text('/out'), findsOneWidget);

    await t.tap(find.text('Export'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.folder, '/out');
    expect(result!.watermarkText, ''); // watermark off by default
  });

  testWidgets('enabling the watermark reveals the text + opacity controls',
      (t) async {
    await t.pumpWidget(
        _host(ExportDialog(count: 1, initialConfig: _cfg(folder: '/out'))));
    await t.pump();

    expect(find.text('Watermark text'), findsNothing);
    await t.tap(find.text('Add text watermark'));
    await t.pump();
    expect(find.text('Watermark text'), findsOneWidget);
    expect(find.text('White text, bottom-right corner.'), findsOneWidget);
  });

  testWidgets('carries a persisted watermark through on confirm', (t) async {
    ExportSettings? result;
    final cfg = AppConfig(
      catalogDir: '/tmp/cat',
      exportFolder: '/out',
      exportWatermarkText: '© Pablo',
      exportWatermarkOpacity: 40,
    );
    await t.pumpWidget(_host(Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          result = await showDialog<ExportSettings>(
            context: context,
            builder: (_) => ExportDialog(count: 2, initialConfig: cfg),
          );
        },
        child: const Text('open'),
      );
    })));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Watermark section is pre-expanded because the persisted text is non-empty.
    expect(find.text('Watermark text'), findsOneWidget);

    await t.tap(find.text('Export'));
    await t.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.watermarkText, '© Pablo');
    expect(result!.watermarkOpacityPct, 40);
  });
}
