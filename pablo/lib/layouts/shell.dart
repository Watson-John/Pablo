// Window shell — vertical assembly of all top/bottom chrome with a slot for
// the sidebar + body + tray.

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../features/search/advanced_search_modal.dart';
import '../theme/tokens.dart';
import 'menu_bar.dart';
import 'search_header.dart';
import 'status_bar.dart';

class WindowShell extends StatefulWidget {
  const WindowShell({
    required this.body,
    this.statusPhotoCount = 0,
    this.statusSection = '',
    super.key,
  });

  final Widget body;
  final int statusPhotoCount;
  final String statusSection;

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
              StatusBar(
                photoCount: widget.statusPhotoCount,
                sectionTitle: widget.statusSection,
                thumbSize: st.thumbSize,
              ),
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
