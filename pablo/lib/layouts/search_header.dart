// Search header: activity indicator (sidebar-aligned) + search input + adv
// search settings cog + Import Photos button.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../backend/native_backend.dart';
import '../components/pablo_button.dart';
import '../components/pablo_icon.dart';
import '../components/pablo_icon_button.dart';
import '../data/boot.dart';
import '../data/library_import.dart';
import '../features/search/activity_indicator.dart';
import '../theme/tokens.dart';

class SearchHeader extends StatefulWidget {
  const SearchHeader({this.onOpenAdvanced, super.key});
  final VoidCallback? onOpenAdvanced;

  @override
  State<SearchHeader> createState() => _SearchHeaderState();
}

class _SearchHeaderState extends State<SearchHeader> {
  late final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _focused = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Store the query immediately (so the field + badge update) but debounce the
  // actual retrieval — embedding the query + ranking runs after a short pause,
  // not on every keystroke.
  void _onQueryChanged(BuildContext context, String q) {
    AppScope.of(context).setSearchText(q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) AppScope.read(context).runSearch();
    });
  }

  // Re-import + re-scan the configured library, refreshing the catalog (stable
  // ids), the gallery, and the face auto-scan. No-op without a native backend
  // or a configured library root. A folder-picker import is a follow-up.
  void _import(BuildContext context) {
    final backend = NativeBackendScope.maybeOf(context);
    final root = BootConfig.instance.libraryRoot;
    if (backend == null || root.isEmpty) return;
    unawaited(LibraryImport.refresh(
      backend: backend,
      root: root,
      appState: AppScope.of(context),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final criteriaCount =
        (st.advCriteria?.activeCount ?? 0) + (st.searchText.isNotEmpty ? 1 : 0);
    if (_ctl.text != st.searchText) {
      _ctl
        ..text = st.searchText
        ..selection = TextSelection.collapsed(offset: _ctl.text.length);
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border:
            const Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
        boxShadow: PabloShadows.searchHeader,
      ),
      child: Row(
        children: [
          SizedBox(
            width: st.sidebarWidth - PabloSpacing.xl,
            child: ActivityIndicator(tasks: st.tasks),
          ),
          const SizedBox(width: PabloSpacing.md),
          Expanded(
            child: AnimatedContainer(
              duration: PabloDurations.base,
              curve: PabloEasing.standard,
              height: 30,
              padding:
                  const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
              decoration: BoxDecoration(
                color: PabloColors.backgroundSurfaceAlt,
                border: Border.all(
                  color: _focused
                      ? PabloColors.accentPrimary
                      : PabloColors.borderSubtle,
                ),
                borderRadius: PabloRadius.pillAll,
                // Azure focus halo (design: 0 0 0 2px accentBg).
                boxShadow: _focused
                    ? const [
                        BoxShadow(
                          color: PabloColors.accentBackground,
                          spreadRadius: 2,
                          blurRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  const PabloIcon(PabloIconName.search, size: 14),
                  const SizedBox(width: PabloSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      focusNode: _focus,
                      onChanged: (q) => _onQueryChanged(context, q),
                      onSubmitted: (_) => st.runSearch(),
                      cursorColor: PabloColors.accentPrimary,
                      style: PabloTypography.sans(fontSize: 12.5),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search photos, people, places, albums…',
                        hintStyle: PabloTypography.sans(
                          fontSize: 12.5,
                          color: PabloColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  if (st.searchText.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _debounce?.cancel();
                        _ctl.clear();
                        st.clearSearch();
                      },
                      child: Text(
                        '✕',
                        style: PabloTypography.sans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: PabloColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: PabloSpacing.md),
          Stack(
            clipBehavior: Clip.none,
            children: [
              PabloIconButton(
                icon: PabloIconName.filter,
                tooltip: 'Advanced Search',
                active: criteriaCount > 0,
                onPressed: widget.onOpenAdvanced,
              ),
              if (criteriaCount > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: PabloColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$criteriaCount',
                      style: PabloTypography.sans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: PabloColors.textOnAccent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: PabloSpacing.md),
          PabloButton(
            label: 'Import Photos',
            variant: PabloButtonVariant.success,
            size: PabloButtonSize.md,
            icon: PabloIconName.cameraFill,
            iconSize: 15,
            onPressed: () => _import(context),
          ),
        ],
      ),
    );
  }
}
