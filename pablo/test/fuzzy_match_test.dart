// fuzzy_match_test.dart — ranking properties of the palette's matcher.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/fuzzy_match.dart';

void main() {
  test('non-subsequence does not match', () {
    expect(fuzzyMatch('xyz', '/photos/beach').isMatch, isFalse);
    expect(fuzzyMatch('bhz', 'beach').isMatch, isFalse); // wrong order
  });

  test('empty query matches everything at score 0', () {
    final r = fuzzyMatch('', '/anything');
    expect(r.isMatch, isTrue);
    expect(r.score, 0);
  });

  test('subsequence matches and records indices', () {
    final r = fuzzyMatch('bch', 'beach');
    expect(r.isMatch, isTrue);
    expect(r.matched, [0, 3, 4]);
  });

  test('word-boundary and consecutive hits outrank scattered ones', () {
    final boundary = fuzzyMatch('vac', '/photos/vacation').score;
    final scattered = fuzzyMatch('vac', '/void/anchor/cellar').score;
    expect(boundary, greaterThan(scattered));
  });

  test('a basename hit beats the same text buried in the parent path', () {
    final ranked = fuzzyRank(
      'trip',
      ['/trip/2021/randomcity', '/photos/summer trip'],
      (s) => s,
    );
    expect(ranked.first, '/photos/summer trip');
  });

  test('fuzzyRank drops non-matches and is stable on ties', () {
    final ranked = fuzzyRank(
      'a',
      ['/x/aa', '/x/ab', '/x/zz'],
      (s) => s,
    );
    expect(ranked, contains('/x/aa'));
    expect(ranked, isNot(contains('/x/zz')));
  });

  test('unicode input does not throw and can match', () {
    final r = fuzzyMatch('éà', '/déjà vu/photo');
    expect(r.isMatch, isTrue);
  });
}
