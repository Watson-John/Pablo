// Catalog-backed search: metadata/star/colour/person/combined filters + text
// semantic ranking (Stage 9). Runs over hand-built SearchDocs (the app builds
// these from the real catalog + embedding index; here we control them).

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/models.dart';
import 'package:pablo/features/search/search_service.dart';

Photo _photo(String id) => Photo(id: id, label: id, filePath: id);

SearchDoc _doc(
  String id, {
  int assetId = 0,
  bool starred = false,
  DateTime? date,
  String? camera,
  int? iso,
  Set<String>? people,
  List<String>? tags,
  int? rgb,
  bool inAlbum = false,
  bool hasLocation = false,
  String fileType = 'JPEG',
}) =>
    SearchDoc(
      photo: _photo(id),
      assetId: assetId == 0 ? id.hashCode & 0x7fffffff : assetId,
      starred: starred,
      date: date,
      camera: camera,
      iso: iso,
      people: people,
      tags: tags,
      dominantRgb: rgb,
      inAlbum: inAlbum,
      hasLocation: hasLocation,
      fileType: fileType,
    );

const _red = 0xD01818;
const _blue = 0x1830D0;
const _green = 0x18B030;

void main() {
  final svc = SearchService();

  test('empty criteria returns every doc (catalog-backed, not heuristic)', () {
    final docs = [_doc('a'), _doc('b'), _doc('c')];
    final r = svc.search(docs, criteria: AdvSearchCriteria());
    expect(r.length, 3);
  });

  test('starred filter keeps only starred docs', () {
    final docs = [
      _doc('a', starred: true),
      _doc('b'),
      _doc('c', starred: true),
    ];
    final r = svc.search(docs, criteria: AdvSearchCriteria(starred: true));
    expect(r.map((p) => p.id).toSet(), {'a', 'c'});
  });

  test('colour filter matches by hue and ranks by proximity', () {
    final docs = [
      _doc('red', rgb: _red),
      _doc('blue', rgb: _blue),
      _doc('green', rgb: _green),
    ];
    final r = svc.search(docs, criteria: AdvSearchCriteria(color: 'red'));
    expect(r.map((p) => p.id), ['red']); // only red matches
  });

  test('person filter honours OR vs AND', () {
    final docs = [
      _doc('ab', people: {'Alice', 'Bob'}),
      _doc('a', people: {'Alice'}),
      _doc('c', people: {'Carol'}),
    ];
    final orR = svc.search(docs,
        criteria: AdvSearchCriteria(people: {'Alice'}, peopleMatch: 'or'));
    expect(orR.map((p) => p.id).toSet(), {'ab', 'a'});

    final andR = svc.search(docs,
        criteria:
            AdvSearchCriteria(people: {'Alice', 'Bob'}, peopleMatch: 'and'));
    expect(andR.map((p) => p.id).toSet(), {'ab'});
  });

  test('combined filters: starred + colour', () {
    final docs = [
      _doc('red_star', starred: true, rgb: _red),
      _doc('red_plain', rgb: _red),
      _doc('blue_star', starred: true, rgb: _blue),
    ];
    final r = svc.search(docs,
        criteria: AdvSearchCriteria(starred: true, color: 'red'));
    expect(r.map((p) => p.id), ['red_star']);
  });

  test('year and tag filters', () {
    final docs = [
      _doc('y23', date: DateTime(2023, 5, 1), tags: ['beach']),
      _doc('y24', date: DateTime(2024, 5, 1), tags: ['beach', 'family']),
      _doc('y23b', date: DateTime(2023, 8, 1), tags: ['city']),
    ];
    expect(
      svc.search(docs, criteria: AdvSearchCriteria(dateMode: 'year', year: '2023'))
          .map((p) => p.id)
          .toSet(),
      {'y23', 'y23b'},
    );
    expect(
      svc.search(docs, criteria: AdvSearchCriteria(tags: 'beach'))
          .map((p) => p.id)
          .toSet(),
      {'y23', 'y24'},
    );
  });

  test('text query is ranked by the injected semantic ranker', () {
    // Ranker that prefers docs whose id contains the query word.
    final ranker = SearchService(ranker: (text, ids) {
      final scored = [...ids]..sort((x, y) {
          // higher assetId = "more relevant" in this fake ordering
          return y.compareTo(x);
        });
      return scored;
    });
    final docs = [
      _doc('tree1', assetId: 10),
      _doc('tree2', assetId: 30),
      _doc('car', assetId: 20),
    ];
    final r = ranker.search(docs, text: 'tree');
    // assetId desc → 30, 20, 10
    expect(r.map((p) => p.id), ['tree2', 'car', 'tree1']);
  });

  test('text query still applies metadata filters before ranking', () {
    final ranker = SearchService(ranker: (text, ids) => ids); // identity
    final docs = [
      _doc('star', assetId: 1, starred: true),
      _doc('plain', assetId: 2),
    ];
    final r = ranker.search(docs,
        text: 'wedding', criteria: AdvSearchCriteria(starred: true));
    expect(r.map((p) => p.id), ['star']);
  });

  test('isActive reflects text or non-empty criteria', () {
    expect(SearchService.isActive('', AdvSearchCriteria()), isFalse);
    expect(SearchService.isActive('tree', null), isTrue);
    expect(
        SearchService.isActive('', AdvSearchCriteria(starred: true)), isTrue);
  });
}
