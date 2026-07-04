// library_location.dart — relocate the catalog database to a new directory.
//
// Moving an open SQLite DB safely is delicate: the running engine holds the
// current catalog.db open for the whole session, so a true in-place move is not
// safe cross-platform (Windows locks the file). Instead we COPY the catalog to
// the new location (after flushing the WAL so the .db is self-contained), update
// [AppConfig], and the new location takes effect on the next launch. The copy is
// crash-safe: each file is copied to a `.tmp` sibling, length-verified, then
// atomically renamed into place; the source is left untouched.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../backend/native_backend.dart';
import 'app_config.dart';

class LibraryLocation {
  static const _dbName = 'catalog.db';

  /// Copy the catalog DB from [srcDir] to [destDir] using copy-to-temp → verify
  /// length → atomic rename, leaving [srcDir] intact. Throws (without leaving a
  /// partial catalog.db in [destDir]) on any failure. Refuses to clobber an
  /// existing catalog.db unless [overwrite].
  ///
  /// Only `catalog.db` is copied — NOT its `-wal`/`-shm` sidecars. The caller
  /// must checkpoint (TRUNCATE) the engine first, which folds the WAL into the
  /// main DB and empties it; the DB is then fully self-contained and SQLite
  /// recreates the sidecars at the destination on next open. (Copying a stale
  /// sidecar mismatched to the DB would risk corruption — hence single-file.)
  static Future<void> copyCatalog(
    String srcDir,
    String destDir, {
    bool overwrite = false,
  }) async {
    final sep = Platform.pathSeparator;
    final src = File('$srcDir$sep$_dbName');
    if (!src.existsSync()) {
      throw StateError('No catalog.db to move at $srcDir');
    }
    final dest = File('$destDir$sep$_dbName');
    if (dest.existsSync() && !overwrite) {
      throw StateError('A catalog already exists at $destDir');
    }
    Directory(destDir).createSync(recursive: true);

    // Copy to a `.tmp` sibling (the cross-device case is handled here by copy),
    // verify the length, then atomically rename into place (intra-dest, so
    // always same-filesystem). Clean up the temp on any failure so destDir is
    // never left with a partial catalog.db.
    final tmp = File('$destDir$sep$_dbName.tmp');
    try {
      await src.copy(tmp.path);
      if (tmp.lengthSync() != src.lengthSync()) {
        throw StateError('Short copy of catalog.db');
      }
      // Windows rename won't replace an existing file; remove it first (we are
      // committed here — the copy has been length-verified).
      if (dest.existsSync()) dest.deleteSync();
      tmp.renameSync(dest.path);
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Relocate the live library to [destDir]: checkpoint the WAL, copy the
  /// catalog there, and persist the new location in [AppConfig]. Returns true on
  /// success. The engine keeps using the old DB for the rest of the session;
  /// the new location is opened on the next launch (the caller should prompt for
  /// a restart). No-op (returns false) when [destDir] equals the current dir.
  static Future<bool> relocate({
    required NativeBackend backend,
    required String destDir,
    bool overwrite = false,
  }) async {
    final srcDir = AppConfig.load().catalogDir;
    if (_normalize(srcDir) == _normalize(destDir)) return false;

    backend.engine.catalogCheckpoint(); // flush WAL into catalog.db
    await copyCatalog(srcDir, destDir, overwrite: overwrite);
    persistCatalogDir(destDir);
    return true;
  }

  /// Point the persisted config at [destDir] — via copyWith, NOT a fresh
  /// AppConfig: a fresh one silently resets every other persisted setting
  /// (editSaveMode, export defaults) on relocate.
  @visibleForTesting
  static void persistCatalogDir(String destDir) =>
      AppConfig.load().copyWith(catalogDir: destDir).save();

  static String _normalize(String dir) {
    var d = dir;
    while (d.length > 1 &&
        (d.endsWith('/') || d.endsWith(Platform.pathSeparator))) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }
}
