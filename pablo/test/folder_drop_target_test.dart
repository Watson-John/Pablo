// Widget tests for the in-app reorganize drop targets: a photo payload dragged
// onto a FolderLeaf / FolderGroup reports the correct destination directory.
// Uses a plain Draggable<List<String>> as the source (matching the DragTarget
// type) so the gesture is deterministic — the long-press source is exercised
// manually/live, here we lock the acceptance wiring.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/sidebar/folder_group.dart';
import 'package:pablo/features/sidebar/folder_leaf.dart';

Widget _harness(Widget target) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Draggable<List<String>>(
              data: const ['/src/a.jpg'],
              feedback: const SizedBox(width: 20, height: 20),
              child: Container(
                key: const Key('src'),
                width: 60,
                height: 40,
                color: const Color(0xFF888888),
              ),
            ),
            target,
          ],
        ),
      ),
    );

Future<void> _dragOnto(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('src'))));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 30));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('FolderLeaf reports the dropped paths', (tester) async {
    List<String>? got;
    await tester.pumpWidget(_harness(FolderLeaf(
      folder: const FolderNode(id: '/lib/B', name: 'B'),
      selected: false,
      onSelect: () {},
      onDropPaths: (p) => got = p,
    )));

    await _dragOnto(tester, find.text('B'));
    expect(got, ['/src/a.jpg']);
  });

  testWidgets('FolderGroup header and child report their own directory',
      (tester) async {
    const node = FolderNode(
      id: '/lib/parent',
      name: 'parent',
      children: [FolderNode(id: '/lib/parent/child', name: 'child')],
    );
    String? destDir;
    await tester.pumpWidget(_harness(FolderGroup(
      folder: node,
      selectedId: null,
      onSelect: (_) {},
      defaultOpen: true,
      onDropPaths: (d, _) => destDir = d,
    )));

    await _dragOnto(tester, find.text('parent'));
    expect(destDir, '/lib/parent');

    await _dragOnto(tester, find.text('child'));
    expect(destDir, '/lib/parent/child');
  });
}
