// Window shell — vertical assembly of all top/bottom chrome with a slot for
// the sidebar + body + tray.

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
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

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Container(
      color: PabloColors.backgroundShell,
      child: Stack(
        children: [
          Column(
            children: [
              const PabloMenuBar(),
              SearchHeader(
                onOpenAdvanced: () => setState(() => _advSearchOpen = true),
              ),
              Expanded(child: widget.body),
            ],
          ),
          if (_advSearchOpen)
            AdvancedSearchModal(
              photoCount: widget.statusPhotoCount,
              onClose: () => setState(() => _advSearchOpen = false),
              onApply: st.setAdvCriteria,
            ),
        ],
      ),
    );
  }
}
