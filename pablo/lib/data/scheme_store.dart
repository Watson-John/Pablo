// scheme_store.dart — load/save the user's storage schemes as JSON. Pablo has
// no general settings layer yet, so this is a tiny self-contained store: a
// single schemes.json under the platform config dir, read/written with dart:io
// (no new package dependency). Schemes are small, so the I/O is synchronous.

import 'dart:convert';
import 'dart:io';

import '../features/organize/scheme_presets.dart';
import 'storage_scheme.dart';

class SchemeStoreData {
  SchemeStoreData(this.schemes, this.activeId);
  final List<StorageScheme> schemes;
  String? activeId;
}

class SchemeStore {
  static const _fileName = 'schemes.json';

  /// Load saved schemes. On first run (or any read error) returns the built-in
  /// presets with the first active, and writes them so the file then exists.
  static SchemeStoreData load() {
    try {
      final f = _file();
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final schemes = (j['schemes'] as List<dynamic>)
            .map((e) =>
                StorageScheme.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        if (schemes.isNotEmpty) {
          return SchemeStoreData(schemes, j['active'] as String?);
        }
      }
    } catch (_) {
      // Unreadable / malformed → fall through and re-seed from presets.
    }
    final presets = buildPresetSchemes();
    final seeded = SchemeStoreData(presets, presets.first.id);
    try {
      save(seeded);
    } catch (_) {}
    return seeded;
  }

  static void save(SchemeStoreData data) {
    final f = _file();
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'schemes': data.schemes.map((s) => s.toJson()).toList(),
      if (data.activeId != null) 'active': data.activeId,
    }));
  }

  static File _file() =>
      File('${_configDir()}${Platform.pathSeparator}$_fileName');

  /// Pablo's per-user config dir, resolved without path_provider.
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
