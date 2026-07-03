// Editable caption bar at the bottom of the lightbox, extracted from
// lightbox_view.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/caption_store.dart';
import '../../../theme/tokens.dart';

/// Editable caption bar at the bottom of the lightbox (Picasa "Make a
/// caption!"). Click to type; Enter or click-away saves to the catalog via
/// [CaptionStore]; Esc cancels. Shows a muted "Add a caption…" affordance when
/// the photo has none.
class CaptionBar extends StatefulWidget {
  const CaptionBar({required this.assetId, this.parentFocus, super.key});
  final int assetId;

  /// The lightbox's keyboard-focus node. Reclaimed when an edit ends so the
  /// lightbox's Esc / F / arrow shortcuts work again after captioning.
  final FocusNode? parentFocus;

  @override
  State<CaptionBar> createState() => _CaptionBarState();
}

class _CaptionBarState extends State<CaptionBar> {
  bool _editing = false;
  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ensure the caption is read even when the lightbox is opened directly on a
    // photo that never scrolled through the grid.
    CaptionStore.instance.prioritize([widget.assetId]);
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEdit(String current) {
    _ctl.text = current;
    _ctl.selection = TextSelection(baseOffset: 0, extentOffset: current.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    if (!_editing) return;
    CaptionStore.instance.setCaption(widget.assetId, _ctl.text.trim());
    setState(() => _editing = false);
    widget.parentFocus?.requestFocus();
  }

  void _cancel() {
    setState(() => _editing = false);
    widget.parentFocus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: CaptionStore.instance.captionRevision,
      builder: (context, _, __) {
        final cap = CaptionStore.instance.captionOf(widget.assetId) ?? '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xxl,
            vertical: PabloSpacing.lg,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
            ),
          ),
          alignment: Alignment.center,
          child: _editing ? _field() : _display(cap),
        );
      },
    );
  }

  Widget _field() {
    // Escape cancels the edit. This CallbackShortcuts is nearer the focused
    // TextField than the lightbox's Escape binding, so it wins while editing.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: TextField(
          controller: _ctl,
          focusNode: _focus,
          textAlign: TextAlign.center,
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
          cursorColor: PabloColors.selectionPrimary,
          style: PabloTypography.sans(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.92),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Add a caption…',
            hintStyle: PabloTypography.sans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl,
              vertical: PabloSpacing.base,
            ),
            border: OutlineInputBorder(
              borderRadius: PabloRadius.mdAll,
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _display(String cap) {
    final hasCap = cap.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _beginEdit(cap),
        behavior: HitTestBehavior.opaque,
        child: Text(
          hasCap ? cap : 'Add a caption…',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: PabloTypography.sans(
            fontSize: 13,
            fontWeight: hasCap ? FontWeight.w500 : FontWeight.w400,
            color: Colors.white.withValues(alpha: hasCap ? 0.85 : 0.35),
          ).copyWith(fontStyle: hasCap ? FontStyle.normal : FontStyle.italic),
        ),
      ),
    );
  }
}
