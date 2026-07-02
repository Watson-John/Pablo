// pinned_folders_test.dart — the move palette surfaces pinned folders first,
// and a pin appears/disappears in the palette ordering as FolderPrefs changes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/folder_prefs.dart';
import 'package:pablo/features/organize/move_palette.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pablo_pinned');
    FolderPrefs.configDirOverride = tmp.path;
    FolderPrefs.instance.resetForTest();
  });
  tearDown(() {
    FolderPrefs.configDirOverride = null;
    FolderPrefs.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FolderCandidate fc(String path) =>
      FolderCandidate(path: path, name: path.split('/').last);

  test('rankFolders puts a pinned folder ahead of an alphabetical one', () {
    final all = [fc('/lib/apple'), fc('/lib/zebra')];
    // Empty query: zebra is pinned so it leads despite alphabetical order.
    final ranked = rankFolders('', all, pinned: ['/lib/zebra']);
    expect(ranked.first.path, '/lib/zebra');
  });

  testWidgets('palette lists pinned folder first for an empty query',
      (tester) async {
    final pinned = Directory('${tmp.path}/zebra')..createSync();
    FolderPrefs.instance.togglePin(pinned.path);

    MoveDestination? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              picked = await showMovePalette(
                context,
                folders: [
                  fc('${tmp.path}/apple'),
                  fc(pinned.path),
                ],
                photoCount: 1,
                pinned: FolderPrefs.instance.pins,
                libraryRoot: tmp.path,
              );
            },
            child: const Text('open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The first row is the pinned folder → Enter picks it.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked!.dir, pinned.path);
  });
}
