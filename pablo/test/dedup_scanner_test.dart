// Verifies the real exact-duplicate scanner groups byte-identical files
// (size-prefilter + content hash) and leaves uniques alone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/find_duplicates/dedup_scanner.dart';

void main() {
  test('findExactGroups groups byte-identical files, skips uniques', () {
    final dir = Directory.systemTemp.createTempSync('dedup_scan');
    File w(String name, List<int> bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(bytes);

    final a = w('a.jpg', [1, 2, 3, 4, 5]);
    final b = w('b.jpg', [1, 2, 3, 4, 5]); // identical to a
    final c = w('c.jpg', [9, 9, 9]); // unique
    final d = w('d.jpg', [7, 7, 7, 7]);
    final e = w('e.jpg', [7, 7, 7, 7]); // identical to d
    // same SIZE as a/b (5 bytes) but different content — must NOT group with them
    final f = w('f.jpg', [5, 4, 3, 2, 1]);

    final groups = findExactGroups([
      (id: 'a', path: a.path),
      (id: 'b', path: b.path),
      (id: 'c', path: c.path),
      (id: 'd', path: d.path),
      (id: 'e', path: e.path),
      (id: 'f', path: f.path),
    ]);

    final sets = [for (final g in groups) g.toSet()];
    expect(groups.length, 2, reason: 'two duplicate groups expected');
    expect(sets.any((s) => s.length == 2 && s.containsAll({'a', 'b'})), isTrue);
    expect(sets.any((s) => s.length == 2 && s.containsAll({'d', 'e'})), isTrue);
    // c (unique) and f (same size, different bytes) are not in any group.
    final grouped = groups.expand((g) => g).toSet();
    expect(grouped.contains('c'), isFalse);
    expect(grouped.contains('f'), isFalse);

    dir.deleteSync(recursive: true);
  });
}
