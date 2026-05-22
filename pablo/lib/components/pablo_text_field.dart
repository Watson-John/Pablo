// Token-styled text input with optional placeholder, used in search header,
// advanced search modal, and inline name editors.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PabloTextField extends StatefulWidget {
  const PabloTextField({
    required this.controller,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.width,
    this.autoFocus = false,
    this.dense = true,
    this.background = PabloColors.backgroundSurface,
    super.key,
  });

  final TextEditingController controller;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;
  final bool autoFocus;
  final bool dense;
  final Color background;

  @override
  State<PabloTextField> createState() => _PabloTextFieldState();
}

class _PabloTextFieldState extends State<PabloTextField> {
  bool _focused = false;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Container(
        decoration: BoxDecoration(
          color: widget.background,
          border: Border.all(
            color: _focused ? PabloColors.accentPrimary : PabloColors.borderSubtle,
          ),
          borderRadius: PabloRadius.mdAll,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: PabloSpacing.base,
          vertical: widget.dense ? PabloSpacing.sm + 1 : PabloSpacing.base,
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autoFocus,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          cursorColor: PabloColors.accentPrimary,
          style: PabloTypography.sans(fontSize: 12),
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
