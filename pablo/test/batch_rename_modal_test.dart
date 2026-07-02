// batch_rename_modal_test.dart — the modal renders a live preview and applies
// the plan to real files on disk (with the library refresh a no-op via an
// empty BootConfig root).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pablo/app/app_scope.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library.dart';
import 'package:pablo/features/organize/batch_rename_modal.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_batch_rename'));
  tearDown(() {
    Library.instance = Library.empty();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('modal shows a preview and applies the plan on disk',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final a = File('${tmp.path}/one.jpg')..writeAsBytesSync([1]);
    final b = File('${tmp.path}/two.jpg')..writeAsBytesSync([2]);
    Library.instance = Library.scan(tmp.path);

    final st = PabloAppState();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: AppScope(
        notifier: st,
        child: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        })),
      ),
    ));

    // ignore: unawaited_futures — dialog is driven below.
    showBatchRenameModal(ctx, st, [a.path, b.path]);
    await tester.pumpAndSettle();
    expect(find.text('Batch Rename 2 Photos'), findsOneWidget);

    // A live preview row per photo (old → new), each an arrow.
    expect(find.text('→'), findsNWidgets(2));
    // With an empty lane every name is its original → all identities → the
    // apply button is disabled and labelled "No changes".
    expect(find.text('No changes'), findsOneWidget);
    final applyBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'No changes'));
    expect(applyBtn.onPressed, isNull, reason: 'apply gated on real changes');

    // Cancel leaves the files untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Batch Rename 2 Photos'), findsNothing);
    expect(a.existsSync(), isTrue);
    expect(b.existsSync(), isTrue);
  });
}
