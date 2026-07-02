// DialogOptionTile — a bordered, selectable option card for settings-style
// dialogs: radio dot + bold label + secondary detail text. Extracted from the
// edit-save mode picker so every dialog that offers mutually-exclusive modes
// renders options the same way (the save-mode picker grows a third tile in the
// overwrite-with-backup work; export/print dialogs are future call sites).

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'hover_surface.dart';

class DialogOptionTile extends StatelessWidget {
  const DialogOptionTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.width = 360,
    super.key,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: width,
        padding: const EdgeInsets.all(PabloSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? PabloColors.accentBackground
              : hovered
                  ? PabloColors.backgroundHover
                  : PabloColors.backgroundSurfaceAlt,
          border: Border.all(
            color:
                selected ? PabloColors.accentPrimary : PabloColors.borderStrong,
          ),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PabloRadioDot(selected: selected),
            const SizedBox(width: PabloSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: PabloTypography.sans(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(detail,
                      style: PabloTypography.sans(
                          fontSize: 11, color: PabloColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple radio dot (avoids pulling in Material Radio's group plumbing).
class PabloRadioDot extends StatelessWidget {
  const PabloRadioDot({required this.selected, super.key});
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.only(top: PabloSpacing.xs),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? PabloColors.accentPrimary : PabloColors.borderStrong,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: PabloColors.accentPrimary),
            )
          : null,
    );
  }
}
