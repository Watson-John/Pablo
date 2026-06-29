// app_config.dart — the one persisted app-level setting Pablo needs so far:
// where the catalog database lives. Stored as a tiny config.json under the
// platform config dir (same location convention as scheme_store.dart), read
// with dart:io so it adds no package dependency.
//
// Until the user relocates the library, this resolves to the legacy default
// (a folder under the system temp dir), so existing installs are unaffected.

import 'dart:convert';
import 'dart:io';

class AppConfig {
  AppConfig({required this.catalogDir});

  /// Directory holding `catalog.db` (and the thumbnail cache).
  final String catalogDir;

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
        if (dir != null && dir.isNotEmpty) return AppConfig(catalogDir: dir);
      }
    } catch (_) {
      // Unreadable / malformed → fall through to the default.
    }
    return AppConfig(catalogDir: defaultCatalogDir);
  }

  void save() {
    final f = _file();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({'catalogDir': catalogDir}));
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
