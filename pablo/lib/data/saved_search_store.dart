// saved_search_store.dart — persistent saved searches (Stage 9).
//
// Saved searches live in the native catalog's `saved_search` table (durable,
// survives restarts). This store serializes the full query — free text +
// [AdvSearchCriteria] (which includes the colour/person/starred/date filters) —
// to JSON and back. The backend is an interface so the store is unit-testable
// with an in-memory fake; the app wires [NativeSavedSearchBackend] over the
// native Engine.

import 'dart:convert';

import 'package:photo_native/photo_native.dart' show Engine;

import '../app/app_state.dart';

/// A saved search as the UI consumes it.
class StoredSearch {
  const StoredSearch({
    required this.id,
    required this.name,
    required this.text,
    required this.criteria,
  });

  final int id;
  final String name;
  final String text;
  final AdvSearchCriteria criteria;
}

/// One raw row as the backend returns it.
class RawSavedSearch {
  const RawSavedSearch(this.id, this.name, this.queryJson);
  final int id;
  final String name;
  final String queryJson;
}

/// Storage backend for saved searches. The native implementation persists to
/// the catalog; tests use an in-memory fake.
abstract class SavedSearchBackend {
  int create(String name, String queryJson);
  void delete(int id);
  List<RawSavedSearch> list(); // newest first
}

/// Backend backed by the native catalog (`photo_saved_search_*`).
class NativeSavedSearchBackend implements SavedSearchBackend {
  NativeSavedSearchBackend(this._engine);
  final Engine _engine;

  @override
  int create(String name, String queryJson) =>
      _engine.createSavedSearch(name, queryJson);

  @override
  void delete(int id) => _engine.deleteSavedSearch(id);

  @override
  List<RawSavedSearch> list() => [
        for (final s in _engine.listSavedSearches())
          RawSavedSearch(s.id, s.name, s.queryJson),
      ];
}

/// In-memory backend for tests (mirrors the native newest-first ordering).
class InMemorySavedSearchBackend implements SavedSearchBackend {
  final _rows = <RawSavedSearch>[];
  int _next = 1;

  @override
  int create(String name, String queryJson) {
    final id = _next++;
    _rows.insert(0, RawSavedSearch(id, name, queryJson)); // newest first
    return id;
  }

  @override
  void delete(int id) => _rows.removeWhere((r) => r.id == id);

  @override
  List<RawSavedSearch> list() => List.unmodifiable(_rows);
}

class SavedSearchStore {
  SavedSearchStore(this._backend);
  final SavedSearchBackend _backend;

  /// Persist a saved search and return its id.
  int save(String name, {String text = '', AdvSearchCriteria? criteria}) {
    final query = jsonEncode({
      'text': text,
      'criteria': (criteria ?? AdvSearchCriteria()).toJson(),
    });
    return _backend.create(name, query);
  }

  void remove(int id) => _backend.delete(id);

  /// Load all saved searches, decoding each query back into text + criteria.
  List<StoredSearch> load() =>
      [for (final r in _backend.list()) _decode(r)];

  StoredSearch _decode(RawSavedSearch r) {
    Map<String, dynamic> j;
    try {
      final parsed = jsonDecode(r.queryJson);
      j = parsed is Map<String, dynamic> ? parsed : const {};
    } catch (_) {
      j = const {};
    }
    final rawCriteria = j['criteria'];
    final criteria = rawCriteria is Map
        ? AdvSearchCriteria.fromJson(rawCriteria.cast<String, dynamic>())
        : AdvSearchCriteria();
    return StoredSearch(
      id: r.id,
      name: r.name,
      text: (j['text'] as String?) ?? '',
      criteria: criteria,
    );
  }
}
