// Window shell — vertical assembly of all top/bottom chrome with a slot for
// the sidebar + body + tray.

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../backend/native_backend.dart';
import '../data/saved_search_store.dart';
import '../features/search/advanced_search_modal.dart';
import '../theme/tokens.dart';
import 'menu_bar.dart';
import 'search_header.dart';

class WindowShell extends StatefulWidget {
  const WindowShell({
    required this.body,
    this.statusPhotoCount = 0,
    super.key,
  });

  final Widget body;
  final int statusPhotoCount;

  @override
  State<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends State<WindowShell> {
  bool _advSearchOpen = false;
  SavedSearchStore? _store;
  List<StoredSearch> _saved = const [];

  void _openAdvanced() {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend != null) {
      _store = SavedSearchStore(NativeSavedSearchBackend(backend.engine));
      _saved = _store!.load();
    } else {
      _store = null;
      _saved = const [];
    }
    setState(() => _advSearchOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final runner = st.searchRunner;
    return Container(
      color: PabloColors.backgroundShell,
      child: Stack(
        children: [
          Column(
            children: [
              const PabloMenuBar(),
              SearchHeader(onOpenAdvanced: _openAdvanced),
              Expanded(child: widget.body),
            ],
          ),
          if (_advSearchOpen)
            AdvancedSearchModal(
              photoCount: widget.statusPhotoCount,
              initial: st.advCriteria,
              resultCounter: runner == null
                  ? null
                  : (c) => runner(st.searchText, c).length,
              savedSearches: _saved,
              onSaveSearch: _store == null
                  ? null
                  : (name, c) {
                      _store!.save(name, text: st.searchText, criteria: c);
                      setState(() => _saved = _store!.load());
                    },
              onLoadSaved: (s) {
                st.setSearchText(s.text);
                st.setAdvCriteria(s.criteria);
                st.runSearch();
                setState(() => _advSearchOpen = false);
              },
              onDeleteSaved: _store == null
                  ? null
                  : (s) {
                      _store!.remove(s.id);
                      setState(() => _saved = _store!.load());
                    },
              onClose: () => setState(() => _advSearchOpen = false),
              onApply: (c) {
                st.setAdvCriteria(c);
                st.runSearch();
              },
            ),
        ],
      ),
    );
  }
}
