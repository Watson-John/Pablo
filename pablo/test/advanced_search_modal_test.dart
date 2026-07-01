// Advanced Search UI: real match count (no heuristic), colour criterion, and
// save/load saved searches (Stage 9).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/saved_search_store.dart';
import 'package:pablo/features/search/advanced_search_modal.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the real match count from the injected counter', (t) async {
    await t.pumpWidget(_host(AdvancedSearchModal(
      photoCount: 999,
      onClose: () {},
      onApply: (_) {},
      resultCounter: (c) => 7, // real count, not a heuristic of photoCount
    )));
    await t.pump();
    expect(find.textContaining('7'), findsWidgets);
    expect(find.textContaining('photos match'), findsOneWidget);
  });

  testWidgets('exposes the colour criterion section', (t) async {
    await t.pumpWidget(_host(AdvancedSearchModal(
      photoCount: 10,
      onClose: () {},
      onApply: (_) {},
      resultCounter: (_) => 10,
    )));
    await t.pump();
    expect(find.text('COLOUR'), findsOneWidget);
  });

  testWidgets('offers Save Search when a save callback is wired', (t) async {
    String? savedName;
    await t.pumpWidget(_host(AdvancedSearchModal(
      photoCount: 10,
      onClose: () {},
      onApply: (_) {},
      resultCounter: (_) => 5,
      onSaveSearch: (name, _) => savedName = name,
    )));
    await t.pump();
    expect(find.text('Save Search'), findsOneWidget);
    expect(savedName, isNull); // not saved until used
  });

  testWidgets('renders saved-search chips that load criteria', (t) async {
    StoredSearch? loaded;
    final saved = [
      StoredSearch(
        id: 1,
        name: 'Red starred',
        text: '',
        criteria: AdvSearchCriteria(color: 'Red', starred: true),
      ),
    ];
    await t.pumpWidget(_host(AdvancedSearchModal(
      photoCount: 10,
      onClose: () {},
      onApply: (_) {},
      resultCounter: (_) => 3,
      savedSearches: saved,
      onLoadSaved: (s) => loaded = s,
    )));
    await t.pump();
    expect(find.text('Red starred'), findsOneWidget);
    await t.tap(find.text('Red starred'));
    await t.pump();
    expect(loaded?.name, 'Red starred');
  });
}
