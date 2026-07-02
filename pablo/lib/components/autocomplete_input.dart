// Inline name input with people autocomplete dropdown. Used by the Unnamed
// Faces page.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class AutocompleteInput extends StatefulWidget {
  const AutocompleteInput({
    required this.controller,
    this.placeholder = 'Type a name…',
    this.suggestions = const [],
    this.onSubmit,
    this.focusNode,
    this.autofocus = false,
    this.bordered = true,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;

  /// Names offered in the dropdown (e.g. existing people). Empty → no dropdown.
  final List<String> suggestions;
  final ValueChanged<String>? onSubmit;

  /// Optional external focus node — lets the host observe focus (e.g. to keep a
  /// hover overlay open while the field is focused). When null, one is owned.
  final FocusNode? focusNode;
  final bool autofocus;

  /// When false, the field draws no border/rounded box of its own — for hosts
  /// (like the Unnamed Faces card) that already supply the surrounding chrome,
  /// so there aren't two nested outlines.
  final bool bordered;

  @override
  State<AutocompleteInput> createState() => _AutocompleteInputState();
}

class _AutocompleteInputState extends State<AutocompleteInput> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  bool get _ownsFocus => widget.focusNode == null;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    widget.controller.addListener(_refreshOverlay);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      _show();
    } else {
      Future.delayed(const Duration(milliseconds: 150), _hide);
    }
  }

  void _refreshOverlay() {
    if (_focus.hasFocus) {
      _overlay?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _hide();
    _focus.removeListener(_onFocusChange);
    widget.controller.removeListener(_refreshOverlay);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  void _show() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: (_) {
      final matches = _matches(widget.controller.text);
      if (matches.isEmpty) return const SizedBox.shrink();
      return Positioned(
        width: (_link.leaderSize?.width ?? 200),
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: Offset(0, (_link.leaderSize?.height ?? 24) + 2),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 140),
              decoration: BoxDecoration(
                color: PabloColors.backgroundSurface,
                border: Border.all(color: PabloColors.borderSubtle),
                borderRadius: PabloRadius.lgAll,
                boxShadow: PabloShadows.lg,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(PabloSpacing.xs),
                children: matches.map((n) {
                  return _MatchItem(
                    label: n,
                    onTap: () {
                      widget.controller.text = n;
                      widget.controller.selection = TextSelection.collapsed(
                        offset: n.length,
                      );
                      widget.onSubmit?.call(n);
                      _hide();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      );
    });
    Overlay.of(context).insert(_overlay!);
  }

  void _hide() {
    _overlay?.remove();
    _overlay = null;
  }

  List<String> _matches(String value) {
    final pool = widget.suggestions;
    if (pool.isEmpty) return const [];
    if (value.trim().isEmpty) return pool.take(5).toList();
    final q = value.toLowerCase();
    return pool.where((n) => n.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Container(
        decoration: widget.bordered
            ? BoxDecoration(
                color: PabloColors.backgroundSurface,
                border: Border.all(color: PabloColors.borderSubtle),
                borderRadius: PabloRadius.mdAll,
              )
            : const BoxDecoration(color: PabloColors.backgroundSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.lg,
          vertical: PabloSpacing.base,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          cursorColor: PabloColors.accentPrimary,
          style: PabloTypography.sans(fontSize: 12),
          onSubmitted: (v) {
            widget.onSubmit?.call(v);
            _hide();
          },
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            hintText: widget.placeholder,
            hintStyle: PabloTypography.sans(
              fontSize: 12,
              color: PabloColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchItem extends StatefulWidget {
  const _MatchItem({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  State<_MatchItem> createState() => _MatchItemState();
}

class _MatchItemState extends State<_MatchItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.lg,
            vertical: PabloSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _hover ? PabloColors.backgroundHover : Colors.transparent,
            borderRadius: PabloRadius.smAll,
          ),
          child: Text(widget.label, style: PabloTypography.sans(fontSize: 12)),
        ),
      ),
    );
  }
}
