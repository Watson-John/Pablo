// folder_prefs.dart — persisted folder pins + recent move destinations, in a
// dedicated folder_prefs.json beside config.json.
//
// DELIBERATELY separate from AppConfig: library_location.dart writes a fresh
// `AppConfig(catalogDir: …).save()` on relocate, which rewrites config.json
// from scratch — any field added there would be wiped. A standalone file has
// zero coupling to that path.
//
// A ChangeNotifier so the sidebar's pinned strip repaints when pins change.
// dart:io + dart:convert only (no package dependency), mirroring AppConfig's
// config-dir resolution.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class FolderPrefs extends ChangeNotifier {
  FolderPrefs._();
  static final FolderPrefs instance = FolderPrefs._();

  static const int _recentsCap = 8;
  static const _fileName = 'folder_prefs.json';

  final List<String> _pins = [];
  final List<String> _recents = [];
  bool _loaded = false;

  List<String> get pins => List.unmodifiable(_pins);
  List<String> get recents => List.unmodifiable(_recents);
  bool isPinned(String path) => _pins.contains(path);

  /// Load once from disk, pruning any folder that no longer exists. Safe to
  /// call repeatedly; only the first call touches the filesystem.
  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _file();
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        _pins
          ..clear()
          ..addAll(_stringList(j['pins']).where(_exists));
        _recents
          ..clear()
          ..addAll(_stringList(j['recents']).where(_exists).take(_recentsCap));
      }
    } catch (_) {
      // Malformed / unreadable → start empty (matches AppConfig.load).
    }
  }

  void togglePin(String path) {
    ensureLoaded();
    if (!_pins.remove(path)) _pins.add(path);
    _save();
    notifyListeners();
  }

  /// Record [path] as the newest move destination (deduped, capped, MRU).
  void noteRecent(String path) {
    ensureLoaded();
    _recents
      ..remove(path)
      ..insert(0, path);
    if (_recents.length > _recentsCap) _recents.removeRange(_recentsCap, _recents.length);
    _save();
    notifyListeners();
  }

  void _save() {
    try {
      final f = _file();
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert({'pins': _pins, 'recents': _recents}));
    } catch (_) {
      // Best-effort; a failed write just means prefs don't persist this run.
    }
  }

  static List<String> _stringList(Object? v) =>
      v is List ? [for (final e in v) if (e is String) e] : const [];

  static bool _exists(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Test seam: when set, prefs read/write here instead of the user config dir.
  @visibleForTesting
  static String? configDirOverride;

  static File _file() =>
      File('${_configDir()}${Platform.pathSeparator}$_fileName');

  // Mirrors AppConfig._configDir so both stores live side by side.
  static String _configDir() {
    if (configDirOverride != null) return configDirOverride!;
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

  /// Test seam: reset in-memory state (does not touch disk).
  @visibleForTesting
  void resetForTest() {
    _pins.clear();
    _recents.clear();
    _loaded = false;
  }
}
