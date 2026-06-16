// Shared face-naming overlay, used by both the thumbnail FaceThumb and the
// lightbox face boxes so they look and behave like the Unnamed Faces cards:
//
//   * Named face   → a rounded read-only name pill.
//   * Unnamed face → the same rounded AutocompleteInput field the cards use,
//                    with existing people as suggestions.
//
// Assigning an EXISTING person is immediate (no dialog); typing a brand-new
// name asks to confirm before creating the person. The overlay stays open while
// the field is focused — even after the pointer leaves — so the suggestion
// dropdown is usable.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../components/autocomplete_input.dart';
import '../../theme/tokens.dart';
import 'people_controller.dart';

class FaceNameOverlay extends StatefulWidget {
  const FaceNameOverlay({
    required this.face,
    required this.controller,
    required this.hovered,
    super.key,
  });

  final FaceRow face;
  final PeopleController controller;

  /// Whether the host face tile is currently hovered. The overlay also shows
  /// itself whenever its field has focus, regardless of this.
  final bool hovered;

  @override
  State<FaceNameOverlay> createState() => _FaceNameOverlayState();
}

class _FaceNameOverlayState extends State<FaceNameOverlay> {
  final FocusNode _focus = FocusNode();
  final TextEditingController _ctl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.personNameFor(widget.face.personId);
    final named = name != null && name.isNotEmpty;
    // Named pills are hover-only; the editable field also persists while focused
    // (so moving the pointer to the suggestion dropdown doesn't dismiss it).
    final visible = widget.hovered || (!named && _focus.hasFocus);
    if (!visible) return const SizedBox.shrink();

    if (named) {
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.base, vertical: PabloSpacing.sm),
        decoration: BoxDecoration(
          color: PabloColors.backgroundSurface.withValues(alpha: 0.96),
          border: Border.all(color: PabloColors.borderSubtle),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: PabloTypography.sans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: PabloColors.textPrimary,
          ),
        ),
      );
    }

    return AutocompleteInput(
      controller: _ctl,
      focusNode: _focus,
      placeholder: 'Name…',
      suggestions: [for (final p in widget.controller.people()) p.name],
      onSubmit: _submit,
    );
  }

  Future<void> _submit(String value) async {
    final name = value.trim();
    if (name.isEmpty) return;
    final pc = widget.controller;
    // Existing person → assign straight away. New person → confirm first.
    if (!isExistingPerson(pc, name) && !await confirmNewPerson(context, name)) {
      return;
    }
    pc.assignCluster(widget.face.clusterId, name);
    _ctl.clear();
    _focus.unfocus();
  }
}

/// Whether [name] (case-insensitive) is already a named person in the library.
bool isExistingPerson(PeopleController pc, String name) =>
    pc.people().any((p) => p.name.toLowerCase() == name.toLowerCase());

/// Confirm creating a brand-new person. Returns true if the user accepts. Used
/// so naming only prompts when adding someone new (existing people assign
/// immediately).
Future<bool> confirmNewPerson(BuildContext context, String name) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PabloColors.backgroundSurface,
      title: Text('Add new person?',
          style:
              PabloTypography.sans(fontSize: 15, fontWeight: FontWeight.w600)),
      content: Text(
        '“$name” isn’t in your library yet. Create them as a new person?',
        style: PabloTypography.sans(
            fontSize: 13, color: PabloColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel',
              style: PabloTypography.sans(color: PabloColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('Add',
              style: PabloTypography.sans(
                  color: PabloColors.accentPrimary,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
