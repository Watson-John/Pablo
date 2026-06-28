// storage_scheme_modal_name.dart — the scheme's name input, split out to keep
// the modal file small.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class SchemeNameField extends StatefulWidget {
  const SchemeNameField({
    required this.name,
    required this.onChanged,
    super.key,
  });

  final String name;
  final ValueChanged<String> onChanged;

  @override
  State<SchemeNameField> createState() => _SchemeNameFieldState();
}

class _SchemeNameFieldState extends State<SchemeNameField> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(covariant SchemeNameField old) {
    super.didUpdateWidget(old);
    // Sync when the scheme is swapped out (e.g. a preset is loaded), but not on
    // ordinary keystrokes (the text already matches).
    if (widget.name != _ctl.text) _ctl.text = widget.name;
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Scheme name', style: PabloTypography.label),
        const SizedBox(width: PabloSpacing.xl),
        SizedBox(
          width: 280,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: PabloSpacing.base, vertical: PabloSpacing.sm + 1),
            decoration: BoxDecoration(
              color: PabloColors.backgroundSurface,
              border: Border.all(color: PabloColors.borderSubtle),
              borderRadius: PabloRadius.smAll,
            ),
            child: TextField(
              controller: _ctl,
              onChanged: widget.onChanged,
              style: PabloTypography.sans(fontSize: 13),
              cursorColor: PabloColors.accentPrimary,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'My scheme',
                hintStyle: PabloTypography.sans(
                    fontSize: 13, color: PabloColors.textMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
