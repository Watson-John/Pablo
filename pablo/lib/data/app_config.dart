// app_config.dart — the one persisted app-level setting Pablo needs so far:
// where the catalog database lives. Stored as a tiny config.json under the
// platform config dir (same location convention as scheme_store.dart), read
// with dart:io so it adds no package dependency.
//
// Until the user relocates the library, this resolves to the legacy default
// (a folder under the system temp dir), so existing installs are unaffected.

import 'dart:convert';
import 'dart:io';

/// How "Save Edits" persists a non-destructive edit (Settings → Edit save).
/// `catalog` (default) keeps the parametric spec in the app catalog and never
/// touches the file. `layeredTiff` additionally writes a self-contained layered
/// TIFF (edited render + embedded original + spec) beside the photo.
abstract final class EditSaveMode {
  static const String catalog = 'catalog';
  static const String layeredTiff = 'layeredTiff';
}

class AppConfig {
  AppConfig({
    required this.catalogDir,
    this.editSaveMode = EditSaveMode.catalog,
    this.exportFolder = '',
    this.exportMaxDim = 0,
    this.exportQuality = 92,
    this.exportWatermarkText = '',
    this.exportWatermarkOpacity = 50,
  });

  /// Directory holding `catalog.db` (and the thumbnail cache).
  final String catalogDir;

  /// How "Save Edits" persists edits (see [EditSaveMode]).
  final String editSaveMode;

  /// Export-to-Folder dialog defaults, remembered from the last run.
  /// [exportMaxDim] 0 = original size; [exportWatermarkText] empty = none;
  /// opacity is a 0..100 percentage.
  final String exportFolder;
  final int exportMaxDim;
  final int exportQuality;
  final String exportWatermarkText;
  final int exportWatermarkOpacity;

  AppConfig copyWith({
    String? catalogDir,
    String? editSaveMode,
    String? exportFolder,
    int? exportMaxDim,
    int? exportQuality,
    String? exportWatermarkText,
    int? exportWatermarkOpacity,
  }) =>
      AppConfig(
        catalogDir: catalogDir ?? this.catalogDir,
        editSaveMode: editSaveMode ?? this.editSaveMode,
        exportFolder: exportFolder ?? this.exportFolder,
        exportMaxDim: exportMaxDim ?? this.exportMaxDim,
        exportQuality: exportQuality ?? this.exportQuality,
        exportWatermarkText: exportWatermarkText ?? this.exportWatermarkText,
        exportWatermarkOpacity:
            exportWatermarkOpacity ?? this.exportWatermarkOpacity,
      );

  static const _fileName = 'config.json';

  /// The default catalog directory (the pre-AppConfig hardcoded location).
  static String get defaultCatalogDir =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}pablo_native_backend';

  /// Load the saved config, or the default on first run / any read error.
  static AppConfig load() {
    try {
      final f = _file();
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final dir = j['catalogDir'] as String?;
        final mode = j['editSaveMode'] as String?;
        return AppConfig(
          catalogDir: (dir != null && dir.isNotEmpty) ? dir : defaultCatalogDir,
          editSaveMode: mode == EditSaveMode.layeredTiff
              ? EditSaveMode.layeredTiff
              : EditSaveMode.catalog,
          exportFolder: (j['exportFolder'] as String?) ?? '',
          exportMaxDim: (j['exportMaxDim'] as num?)?.toInt() ?? 0,
          exportQuality: ((j['exportQuality'] as num?)?.toInt() ?? 92).clamp(1, 100),
          exportWatermarkText: (j['exportWatermarkText'] as String?) ?? '',
          exportWatermarkOpacity:
              ((j['exportWatermarkOpacity'] as num?)?.toInt() ?? 50).clamp(0, 100),
        );
      }
    } catch (_) {
      // Unreadable / malformed → fall through to the default.
    }
    return AppConfig(catalogDir: defaultCatalogDir);
  }

  void save() {
    final f = _file();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'catalogDir': catalogDir,
      'editSaveMode': editSaveMode,
      'exportFolder': exportFolder,
      'exportMaxDim': exportMaxDim,
      'exportQuality': exportQuality,
      'exportWatermarkText': exportWatermarkText,
      'exportWatermarkOpacity': exportWatermarkOpacity,
    }));
  }

  static File _file() =>
      File('${_configDir()}${Platform.pathSeparator}$_fileName');

  /// Pablo's per-user config dir, resolved without path_provider (mirrors
  /// scheme_store.dart so both stores live side by side).
  static String _configDir() {
    final env = Platform.environment;
    final sep = Platform.pathSeparator;
    final fallback = Directory.systemTemp.path;
    if (Platform.isMacOS) {
      final home = env['HOME'] ?? fallback;
      return '$home${sep}Library${sep}Application Support${sep}Pablo';
    }
    if (Platform.isWindows) {
      final base = env['APPDATA'] ?? env['USERPROFILE'] ?? fallback;
      return '$base${sep}Pablo';
    }
    final base =
        env['XDG_CONFIG_HOME'] ?? '${env['HOME'] ?? fallback}$sep.config';
    return '$base${sep}pablo';
  }
}
