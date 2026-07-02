// print_service_test.dart — the pure PDF builder (pdf is pure Dart, no AppKit).
// Uses the committed real JPEG fixture for valid image bytes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/print/print_layouts.dart';
import 'package:pablo/features/print/print_service.dart';

void main() {
  final sep = Platform.pathSeparator;
  final fixture =
      '..${sep}native${sep}core${sep}tests${sep}fixtures${sep}exif_full.jpg';

  List<PrintItem> items(int n) => [
        for (var i = 0; i < n; i++)
          PrintItem(path: fixture, caption: 'photo_$i.jpg'),
      ];

  setUpAll(() {
    if (!File(fixture).existsSync()) {
      fail('print fixture missing: $fixture');
    }
  });

  test('builds a non-empty PDF for a single full-page photo', () async {
    final doc = buildPrintDocument(items(1), PrintLayout.full);
    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
    // A real PDF starts with "%PDF".
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('a 2-page job saves to more bytes than a 1-page job', () async {
    final one = await buildPrintDocument(items(1), PrintLayout.full).save();
    // 5 photos at 4-up = 2 pages.
    final two = await buildPrintDocument(items(5), PrintLayout.fourUp).save();
    expect(two.length, greaterThan(one.length));
  });

  test('contact sheet with captions builds without error', () async {
    final doc = buildPrintDocument(items(12), PrintLayout.contactSheet);
    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
  });

  test('an unreadable image path yields a blank cell, not a crash', () async {
    final mixed = [
      PrintItem(path: fixture, caption: 'ok.jpg'),
      const PrintItem(path: '/nope/missing.jpg', caption: 'missing.jpg'),
    ];
    final doc = buildPrintDocument(mixed, PrintLayout.twoUp);
    final bytes = await doc.save();
    expect(bytes, isNotEmpty);
  });
}
