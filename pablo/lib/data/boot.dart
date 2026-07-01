// boot.dart — resolves what to import and how to render it, before runApp.
//
// Zero-config by default: Pablo locates the in-repo Flickr30k folder and the
// face models by walking up from the working directory, turns the native
// texture pipeline on, and auto-scans faces in the background. Every choice can
// be overridden with a --dart-define so a real install can point elsewhere.

import 'dart:io';

import 'models_dir.dart';

class BootConfig {
  BootConfig({
    required this.libraryRoot,
    required this.modelsDir,
    required this.nativeThumbs,
    required this.autoScan,
    required this.faceScanCap,
  });

  /// Folder to import as the photo library ('' if none was found).
  final String libraryRoot;

  /// Folder holding the face ONNX models ('' if none was found → faces report
  /// unavailable).
  final String modelsDir;

  /// Render thumbnails through the native libvips → GPU-texture pipeline.
  final bool nativeThumbs;

  /// Kick off a background face scan of the library on first frame.
  final bool autoScan;

  /// Cap on how many images the boot face-scan touches (a full 31k scan would
  /// take far too long for a dry run; raise via --dart-define for a real run).
  final int faceScanCap;

  bool get hasLibrary => libraryRoot.isNotEmpty;

  /// The resolved boot config, set in main(). Conservative defaults (no
  /// library, native off) keep widget tests — which pump the app without a
  /// boot — from touching the filesystem or the native engine.
  static BootConfig instance = BootConfig(
    libraryRoot: '',
    modelsDir: '',
    nativeThumbs: false,
    autoScan: false,
    faceScanCap: 0,
  );

  static BootConfig resolve() {
    const envLibrary = String.fromEnvironment('PABLO_LIBRARY_DIR',
        defaultValue: String.fromEnvironment('PABLO_DATASET_DIR'));
    const envModels = String.fromEnvironment('PABLO_MODELS_DIR');
    const nativeThumbs =
        bool.fromEnvironment('PABLO_NATIVE_THUMBS', defaultValue: true);
    const autoScan = bool.fromEnvironment('PABLO_AUTOSCAN', defaultValue: true);
    // -1 = scan the whole library. ingestLibrary treats a negative cap as "all".
    const scanCap =
        int.fromEnvironment('PABLO_FACE_SCAN_CAP', defaultValue: -1);

    final libraryRoot = envLibrary.isNotEmpty
        ? envLibrary
        : (_findUp('flickr30k_images') ?? '');
    final bundledModels = envModels.isNotEmpty
        ? envModels
        : (_findUp('native${Platform.pathSeparator}models') ?? '');
    final modelsDir =
        _mergedOrBundled(bundledModels, explicit: envModels.isNotEmpty);

    return BootConfig(
      libraryRoot: libraryRoot,
      modelsDir: modelsDir,
      nativeThumbs: nativeThumbs,
      autoScan: autoScan,
      faceScanCap: scanCap,
    );
  }
}

/// The engine takes one models path. First-run-downloaded semantic models
/// live in the user-writable merged dir (models_dir.dart) alongside symlinks
/// to the bundled face models, so prefer the merged dir. An [explicit]
/// --dart-define override (which may hold non-`.onnx` extras a merge would
/// not carry over) or a merge failure keeps the old behavior byte-identical:
/// the bundled/override dir passes through untouched.
String _mergedOrBundled(String bundled, {required bool explicit}) {
  if (explicit) return bundled;
  try {
    final merged = resolveMergedModelsDir();
    if (bundled.isNotEmpty) mergeBundledModels(merged, Directory(bundled));
    return merged.path;
  } catch (_) {
    return bundled;
  }
}

/// Locate [rel] by walking up from a few plausible roots. A launched macOS
/// `.app` runs with a CWD of `/`, so we also climb from the executable path
/// (which lives deep inside `pablo/build/...`) up to the repo root.
String? _findUp(String rel) {
  final starts = <String>{
    Directory.current.absolute.path,
    File(Platform.resolvedExecutable).parent.path,
  };
  for (final start in starts) {
    var dir = Directory(start).absolute;
    for (var i = 0; i < 14; i++) {
      final candidate = '${dir.path}${Platform.pathSeparator}$rel';
      if (Directory(candidate).existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}
