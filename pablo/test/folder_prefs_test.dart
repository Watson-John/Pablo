// folder_prefs_test.dart — pins + recents round-trip through folder_prefs.json,
// cap/dedupe, prune-missing on load, and malformed-JSON fallback.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/folder_prefs.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pablo_folder_prefs');
    FolderPrefs.configDirOverride = tmp.path;
    FolderPrefs.instance.resetForTest();
  });

  tearDown(() {
    FolderPrefs.configDirOverride = null;
    FolderPrefs.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String dir(String name) {
    final d = Directory('${tmp.path}/$name')..createSync();
    return d.path;
  }

  test('togglePin adds then removes, and persists across a reload', () {
    final p = dir('pinme');
    final fp = FolderPrefs.instance;
    fp.togglePin(p);
    expect(fp.isPinned(p), isTrue);

    // Reload a fresh view of the same file.
    fp.resetForTest();
    fp.ensureLoaded();
    expect(fp.isPinned(p), isTrue);

    fp.togglePin(p);
    expect(fp.isPinned(p), isFalse);
  });

  test('recents are MRU, deduped, and capped at 8', () {
    final fp = FolderPrefs.instance;
    final dirs = [for (var i = 0; i < 10; i++) dir('r$i')];
    for (final d in dirs) {
      fp.noteRecent(d);
    }
    // Re-note an older one → it jumps to front.
    fp.noteRecent(dirs[0]);
    final recents = fp.recents;
    expect(recents.length, 8);
    expect(recents.first, dirs[0]);
    // Deduped: dirs[0] appears once.
    expect(recents.where((r) => r == dirs[0]).length, 1);
  });

  test('load prunes entries whose folder no longer exists', () {
    final keep = dir('keep');
    final gone = dir('gone');
    final fp = FolderPrefs.instance;
    fp.togglePin(keep);
    fp.togglePin(gone);
    fp.noteRecent(gone);

    Directory(gone).deleteSync();
    fp.resetForTest();
    fp.ensureLoaded();

    expect(fp.pins, [keep]);
    expect(fp.recents, isEmpty);
  });

  test('malformed JSON falls back to empty without throwing', () {
    File('${tmp.path}/folder_prefs.json').writeAsStringSync('{ not json');
    final fp = FolderPrefs.instance;
    expect(fp.ensureLoaded, returnsNormally);
    expect(fp.pins, isEmpty);
    expect(fp.recents, isEmpty);
  });
}
