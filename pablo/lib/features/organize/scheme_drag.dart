// scheme_drag.dart — shared visual primitives for the storage-scheme builder:
// the segment chip, the draggable palette chip, and the titled "stage" card
// that keeps the folder-structure and file-name stages visually distinct.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';

/// Wayfinding hue for a token group's chip icon. Azure stays reserved for
/// action/selection, so groups use the earthy section palette.
Color tokenGroupColor(TokenGroup g) {
  switch (g) {
    case TokenGroup.date:
      return PabloColors.sectionTimeline;
    case TokenGroup.camera:
      return PabloColors.sectionPeople;
    case TokenGroup.file:
      return PabloColors.sectionFolders;
    case TokenGroup.counter:
      return PabloColors.highlight;
    case TokenGroup.prompt:
      return PabloColors.aiAccent;
  }
}

/// A single chip representing a token or literal, with an optional remove (×).
class SchemeChip extends StatelessWidget {
  const SchemeChip({
    required this.label,
    this.icon,
    this.color,
    this.muted = false,
    this.onRemove,
    super.key,
  });

  final String label;
  final PabloIconName? icon;
  final Color? color;
  final bool muted;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        icon != null ? PabloSpacing.md : PabloSpacing.base,
        PabloSpacing.sm,
        onRemove != null ? PabloSpacing.sm : PabloSpacing.base,
        PabloSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: muted
            ? PabloColors.backgroundSurfaceAlt
            : PabloColors.backgroundRaised,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            PabloIcon(icon!, size: 13, color: color ?? PabloColors.textMuted),
            const SizedBox(width: PabloSpacing.sm),
          ],
          Text(
            label,
            style: PabloTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: muted ? PabloColors.textMuted : PabloColors.textPrimary,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: PabloSpacing.xs),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(PabloSpacing.xs),
                child: PabloIcon(PabloIconName.close,
                    size: 12, color: PabloColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A palette chip the user drags into a lane. Tokens that need metadata Pablo
/// can't read yet are shown disabled with an explanatory tooltip.
class TokenPaletteChip extends StatelessWidget {
  const TokenPaletteChip({required this.spec, super.key});

  final TokenSpec spec;

  @override
  Widget build(BuildContext context) {
    final chip = SchemeChip(
      label: spec.label,
      icon: spec.icon,
      color: tokenGroupColor(spec.group),
      muted: !spec.isReady,
    );
    if (!spec.isReady) {
      return Tooltip(
        message: 'Coming soon — needs camera metadata Pablo doesn’t read yet',
        child: Opacity(opacity: 0.55, child: chip),
      );
    }
    return Draggable<TokenType>(
      data: spec.type,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: const Offset(-24, -16),
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: PabloShadows.md),
            child: chip,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: chip),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(message: 'e.g. ${spec.example}', child: chip),
      ),
    );
  }
}

/// A titled card wrapping one builder stage. The icon + title + helper line
/// give each stage its own identity so "where it's filed" and "what it's named"
/// never read as one undifferentiated lane.
class SchemeStageCard extends StatelessWidget {
  const SchemeStageCard({
    required this.icon,
    required this.title,
    required this.helper,
    required this.child,
    this.iconColor,
    super.key,
  });

  final PabloIconName icon;
  final String title;
  final String helper;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PabloIcon(icon,
                  size: 16, color: iconColor ?? PabloColors.textSecondary),
              const SizedBox(width: PabloSpacing.base),
              Text(title,
                  style: PabloTypography.serif(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: PabloSpacing.xxxxl),
            child: Text(helper, style: PabloTypography.caption),
          ),
          const SizedBox(height: PabloSpacing.lg),
          child,
        ],
      ),
    );
  }
}
