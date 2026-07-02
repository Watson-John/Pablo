// Tests for the catalog relocate file ops: copy-verify-atomic-swap of
// catalog.db (+ sidecars), source preserved, dest-exists guard, overwrite, and
// the missing-source error. These touch a real temp filesystem (cross-OS
// behavior — path separators, rename-replace — differs by platform, so this
// runs on every CI OS).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/app_config.dart';
import 'package:pablo/data/library_location.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pablo_loc_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String p(String sub) => '${tmp.path}${Platform.pathSeparator}$sub';

  test('copies catalog.db only (not sidecars), source intact, no .tmp residue',
      () async {
    final sep = Platform.pathSeparator;
    final src = p('src');
    Directory(src).createSync();
    File('$src${sep}catalog.db').writeAsBytesSync(List.filled(100, 7));
    // A leftover WAL sidecar must NOT be copied — a checkpointed DB is
    // self-contained and copying a stale sidecar would risk corruption.
    File('$src${sep}catalog.db-wal').writeAsBytesSync(List.filled(10, 1));
    final dest = p('dest');

    await LibraryLocation.copyCatalog(src, dest);

    expect(File('$dest${sep}catalog.db').lengthSync(), 100);
    expect(File('$dest${sep}catalog.db-wal').existsSync(), isFalse);
    expect(File('$dest${sep}catalog.db.tmp').existsSync(), isFalse);
    // Source is preserved (copy, not move).
    expect(File('$src${sep}catalog.db').existsSync(), isTrue);
  });

  test('refuses to clobber an existing catalog unless overwrite', () async {
    final sep = Platform.pathSeparator;
    final src = p('src');
    Directory(src).createSync();
    File('$src${sep}catalog.db').writeAsBytesSync([1, 2, 3]);
    final dest = p('dest');
    Directory(dest).createSync();
    File('$dest${sep}catalog.db').writeAsBytesSync([9]);

    await expectLater(
        LibraryLocation.copyCatalog(src, dest), throwsStateError);
    expect(File('$dest${sep}catalog.db').lengthSync(), 1); // untouched

    await LibraryLocation.copyCatalog(src, dest, overwrite: true);
    expect(File('$dest${sep}catalog.db').lengthSync(), 3); // replaced
  });

  test('throws when there is no source catalog', () async {
    final src = p('empty');
    Directory(src).createSync();
    await expectLater(
        LibraryLocation.copyCatalog(src, p('dest')), throwsStateError);
  });

  test('relocate preserves the other persisted settings (regression)', () {
    // The bug: relocate wrote `AppConfig(catalogDir: dest).save()` — a FRESH
    // config — silently resetting editSaveMode/export prefs. It must copyWith.
    final cfgDir = p('cfg');
    Directory(cfgDir).createSync();
    AppConfig.configDirOverride = cfgDir;
    addTearDown(() => AppConfig.configDirOverride = null);

    AppConfig(
      catalogDir: p('old_catalog'),
      editSaveMode: EditSaveMode.layeredTiff,
      exportQuality: 77,
      exportWatermarkText: 'wm',
    ).save();

    LibraryLocation.persistCatalogDir(p('new_catalog'));

    final after = AppConfig.load();
    expect(after.catalogDir, p('new_catalog'));
    expect(after.editSaveMode, EditSaveMode.layeredTiff);
    expect(after.exportQuality, 77);
    expect(after.exportWatermarkText, 'wm');
  });
}
