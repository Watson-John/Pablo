// Saved searches persist text + full criteria and round-trip (Stage 9).

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/saved_search_store.dart';

void main() {
  test('save + load round-trips text and every criterion', () {
    final store = SavedSearchStore(InMemorySavedSearchBackend());
    final criteria = AdvSearchCriteria(
      starred: true,
      color: 'red',
      people: {'Alice', 'Bob'},
      peopleMatch: 'and',
      dateMode: 'year',
      year: '2023',
      camera: 'Canon',
      tags: 'beach,family',
    );
    final id = store.save('Red family 2023', text: 'wedding', criteria: criteria);
    expect(id, greaterThan(0));

    final loaded = store.load();
    expect(loaded, hasLength(1));
    final s = loaded.single;
    expect(s.name, 'Red family 2023');
    expect(s.text, 'wedding');
    expect(s.criteria.starred, isTrue);
    expect(s.criteria.color, 'red');
    expect(s.criteria.people, {'Alice', 'Bob'});
    expect(s.criteria.peopleMatch, 'and');
    expect(s.criteria.dateMode, 'year');
    expect(s.criteria.year, '2023');
    expect(s.criteria.camera, 'Canon');
    expect(s.criteria.tags, 'beach,family');
  });

  test('newest first, and delete removes', () {
    final store = SavedSearchStore(InMemorySavedSearchBackend());
    store.save('first', text: 'a');
    final second = store.save('second', text: 'b');
    var all = store.load();
    expect(all.map((s) => s.name), ['second', 'first']);

    store.remove(second);
    all = store.load();
    expect(all.map((s) => s.name), ['first']);
  });

  test('malformed query json degrades to defaults, not a crash', () {
    final backend = InMemorySavedSearchBackend();
    backend.create('broken', 'not json{');
    final store = SavedSearchStore(backend);
    final s = store.load().single;
    expect(s.name, 'broken');
    expect(s.text, '');
    expect(s.criteria.isEmpty, isTrue);
  });
}
