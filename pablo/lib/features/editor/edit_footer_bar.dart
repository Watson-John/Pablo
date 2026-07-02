// Sticky footer for the photo editor (Pablo v4): an "Unsaved changes" hint,
// a split green Save button (Save Edits / Save as Copy), and a Reset button.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';

class EditFooterBar extends StatelessWidget {
  const EditFooterBar({
    required this.isDefault,
    required this.isDirty,
    required this.hasSavedEdits,
    required this.saveLabel,
    required this.onSave,
    required this.onSaveCopy,
    required this.onReset,
    required this.onRevert,
    super.key,
  });

  /// The working spec is neutral (nothing to reset) — drives the Reset button.
  final bool isDefault;

  /// The working spec differs from what's saved — drives the "Unsaved changes"
  /// hint (distinct from [isDefault]: a saved non-neutral edit is NOT dirty).
  final bool isDirty;

  /// True when a persisted edit exists on disk → show "Revert to Original".
  final bool hasSavedEdits;
  final String saveLabel;
  final VoidCallback onSave;
  final VoidCallback onSaveCopy;
  final VoidCallback onReset;

  /// Discard the saved edit and restore the untouched original.
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(top: BorderSide(color: PabloColors.borderStrong)),
      ),
      padding: const EdgeInsets.fromLTRB(
          PabloSpacing.xl, PabloSpacing.lg, PabloSpacing.xl, PabloSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDirty)
            Padding(
              padding: const EdgeInsets.only(bottom: PabloSpacing.base),
              child: Text(
                'Unsaved changes',
                textAlign: TextAlign.center,
                style: PabloTypography.sans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: PabloColors.warning,
                ),
              ),
            ),
          SizedBox(
            height: 26,
            child: Row(
              children: [
                Expanded(
                  child: _SaveSplit(
                    label: saveLabel,
                    onSave: onSave,
                    onSaveCopy: onSaveCopy,
                  ),
                ),
                const SizedBox(width: PabloSpacing.base),
                _ResetButton(enabled: !isDefault, onTap: onReset),
              ],
            ),
          ),
          // Reversibility signal: edits never touch the original. When a saved
          // edit exists, the hint becomes a tappable "Revert to Original".
          Padding(
            padding: const EdgeInsets.only(top: PabloSpacing.base),
            child: hasSavedEdits
                ? _RevertLink(onTap: onRevert)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const PabloIcon(PabloIconName.rotateLeft,
                          size: 11, color: PabloColors.textMuted),
                      const SizedBox(width: 5),
                      Text(
                        'Non-destructive — revert anytime',
                        style: PabloTypography.sans(
                          fontSize: 10.5,
                          color: PabloColors.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tappable "Revert to Original" affordance shown when the photo has a saved
/// edit — the explicit, file-safe undo.
class _RevertLink extends StatefulWidget {
  const _RevertLink({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_RevertLink> createState() => _RevertLinkState();
}

class _RevertLinkState extends State<_RevertLink> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PabloIcon(PabloIconName.rotateLeft,
                size: 11,
                color: _hover ? PabloColors.accentHover : PabloColors.accentPrimary),
            const SizedBox(width: 5),
            Text(
              'Revert to Original',
              style: PabloTypography.sans(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _hover
                    ? PabloColors.accentHover
                    : PabloColors.accentPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveSplit extends StatelessWidget {
  const _SaveSplit({
    required this.label,
    required this.onSave,
    required this.onSaveCopy,
  });
  final String label;
  final VoidCallback onSave;
  final VoidCallback onSaveCopy;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: PabloRadius.pillAll,
      child: Row(
        children: [
          Expanded(
            child: _GreenHalf(
              onTap: onSave,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const PabloIcon(PabloIconName.saveFill,
                      size: 13, color: PabloColors.textOnAccent),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: PabloColors.textOnAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, color: PabloColors.whiteAlpha(0.3)),
          PopupMenuButton<String>(
            tooltip: 'Save options',
            position: PopupMenuPosition.under,
            padding: EdgeInsets.zero,
            color: PabloColors.backgroundSurface,
            onSelected: (v) => v == 'copy' ? onSaveCopy() : onSave(),
            itemBuilder: (_) => [
              _menuItem('save', PabloIconName.saveFill, 'Save Edits'),
              _menuItem('copy', PabloIconName.copy, 'Save as Copy'),
            ],
            child: Container(
              width: 26,
              color: PabloColors.assignGreen,
              alignment: Alignment.center,
              child: const PabloIcon(PabloIconName.chevDown,
                  size: 12, color: PabloColors.textOnAccent),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String v, PabloIconName icon, String label) {
    return PopupMenuItem<String>(
      value: v,
      height: 36,
      child: Row(
        children: [
          PabloIcon(icon, size: 14, color: PabloColors.textSecondary),
          const SizedBox(width: 7),
          Text(label, style: PabloTypography.sans(fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _GreenHalf extends StatefulWidget {
  const _GreenHalf({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;
  @override
  State<_GreenHalf> createState() => _GreenHalfState();
}

class _GreenHalfState extends State<_GreenHalf> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.control,
          height: 26,
          color:
              _hover ? PabloColors.assignGreenHover : PabloColors.assignGreen,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ResetButton extends StatefulWidget {
  const _ResetButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;
  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final fg =
        widget.enabled ? PabloColors.textSecondary : PabloColors.textMuted;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.control,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.enabled && _hover
                ? PabloColors.backgroundHover
                : PabloColors.backgroundSurface,
            border: Border.all(color: PabloColors.borderStrong),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.5,
            child: Text(
              'Reset',
              style: PabloTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
