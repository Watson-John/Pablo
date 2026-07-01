// models_dir.dart — resolves the user-writable models directory and merges
// the bundled (read-only, inside the app) face models into it.
//
// The engine takes ONE models path. Downloaded semantic models (see
// model_fetcher.dart) must live somewhere user-writable, while the face
// `*.onnx` files ship inside the app bundle — so boot points the engine at a
// MERGED dir: the per-platform app-data location holding the downloads plus a
// symlink to each bundled model (copied on platforms where linking fails).

import 'dart:io';

/// Resolve (and create) the user-writable merged models directory.
///
/// Order: `PABLO_MODELS_DIR` process-environment override → per-platform app
/// data dir (macOS `~/Library/Application Support/Pablo/models`, Linux
/// `$XDG_DATA_HOME|~/.local/share` + `/pablo/models`, Windows
/// `%APPDATA%/Pablo/models`). Forward slashes are used everywhere — Windows
/// file APIs accept them. [env] and [os] are injectable for tests and default
/// to the real process environment / platform. Throws [FileSystemException]
/// when the directory cannot be created (callers fall back to bundled).
Directory resolveMergedModelsDir({Map<String, String>? env, String? os}) {
  final e = env ?? Platform.environment;
  final platform = os ?? Platform.operatingSystem;
  final override = e['PABLO_MODELS_DIR'];

  final String path;
  if (override != null && override.isNotEmpty) {
    path = override;
  } else if (platform == 'macos') {
    path = '${_home(e)}/Library/Application Support/Pablo/models';
  } else if (platform == 'windows') {
    final appData = e['APPDATA'] ?? '${_home(e)}/AppData/Roaming';
    path = '$appData/Pablo/models';
  } else {
    final xdg = e['XDG_DATA_HOME'];
    final base =
        (xdg != null && xdg.isNotEmpty) ? xdg : '${_home(e)}/.local/share';
    path = '$base/pablo/models';
  }
  return Directory(path)..createSync(recursive: true);
}

String _home(Map<String, String> env) =>
    env['HOME'] ?? env['USERPROFILE'] ?? '';

/// Make every bundled `*.onnx` reachable from [merged]: create a symlink per
/// file, copying instead where symlinks fail (e.g. Windows without developer
/// mode). Entries already resolving to a real file — prior links or files the
/// user placed there — are left untouched; broken links are replaced. A
/// missing [bundled] dir is a no-op.
void mergeBundledModels(Directory merged, Directory bundled) {
  if (!bundled.existsSync()) return;
  for (final entry in bundled.listSync()) {
    if (entry is! File || !entry.path.endsWith('.onnx')) continue;
    final name = entry.uri.pathSegments.last;
    final target = '${merged.path}${Platform.pathSeparator}$name';
    // Present and resolvable (real file or live link) → leave it alone.
    if (FileSystemEntity.typeSync(target) == FileSystemEntityType.file) {
      continue;
    }
    // A dangling symlink (e.g. the app bundle moved) — replace it.
    if (FileSystemEntity.typeSync(target, followLinks: false) ==
        FileSystemEntityType.link) {
      Link(target).deleteSync();
    }
    final source = entry.absolute.path;
    try {
      Link(target).createSync(source);
    } on FileSystemException {
      File(source).copySync(target);
    }
  }
}
