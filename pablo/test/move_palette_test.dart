// move_palette_test.dart — the palette's pure ranking + new-folder resolution,
// plus a widget smoke of filter → Enter → returned destination.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/organize/move_palette.dart';

void main() {
  final sep = Platform.pathSeparator;

  FolderCandidate fc(String path) =>
      FolderCandidate(path: path, name: path.split(RegExp(r'[/\\]')).last);

  group('rankFolders', () {
    final all = [fc('/lib/beach'), fc('/lib/city'), fc('/lib/mountains')];

    test('empty query = pins, then recents, then alphabetical rest', () {
      final r = rankFolders('', all,
          pinned: ['/lib/mountains'], recents: ['/lib/city']);
      expect(r.map((f) => f.path).toList(),
          ['/lib/mountains', '/lib/city', '/lib/beach']);
    });

    test('a query fuzzy-filters and drops non-matches', () {
      final r = rankFolders('bea', all);
      expect(r.map((f) => f.path).toList(), ['/lib/beach']);
    });

    test('pins/recents that are not real folders are ignored', () {
      final r = rankFolders('', all, pinned: ['/gone']);
      expect(r.map((f) => f.path), isNot(contains('/gone')));
      expect(r.length, 3);
    });
  });

  group('resolveNewFolderPath', () {
    test('joins hardened components under the library root', () {
      expect(resolveNewFolderPath('Trips/2024', '/lib'),
          '/lib${sep}Trips${sep}2024');
    });

    test('drops empty components and trims', () {
      expect(resolveNewFolderPath('  //  a // ', '/lib'), '/lib${sep}a');
    });

    test('all-empty query resolves to null', () {
      expect(resolveNewFolderPath('   /  / ', '/lib'), isNull);
    });
  });

  testWidgets('type → Enter returns the highlighted folder', (tester) async {
    MoveDestination? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              picked = await showMovePalette(
                context,
                folders: [fc('/lib/beach'), fc('/lib/city')],
                photoCount: 2,
                libraryRoot: '/lib',
              );
            },
            child: const Text('open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Move 2 photos to…'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'city');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.dir, '/lib/city');
    expect(picked!.isNew, isFalse);
  });

  testWidgets('a novel name offers a create-folder row', (tester) async {
    MoveDestination? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              picked = await showMovePalette(
                context,
                folders: [fc('/lib/beach')],
                photoCount: 1,
                libraryRoot: '/lib',
              );
            },
            child: const Text('open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Sunsets');
    await tester.pump();
    expect(find.textContaining('Create folder'), findsOneWidget);

    await tester.tap(find.textContaining('Create folder'));
    await tester.pumpAndSettle();
    expect(picked!.isNew, isTrue);
    expect(picked!.dir, '/lib${sep}Sunsets');
  });
}
