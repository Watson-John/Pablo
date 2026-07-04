// Lightbox chrome controls (nav arrows, top-bar buttons, filmstrip edge
// fades), extracted from lightbox_view.dart.

import 'package:flutter/material.dart';

import '../../../components/hover_surface.dart';
import '../../../components/pablo_icon.dart';
import '../../../theme/tokens.dart';

/// Lightbox prev/next arrow — borderless gray glyph that brightens into a dark
/// well on hover (Pablo v4).
class NavArrowButton extends StatelessWidget {
  const NavArrowButton({required this.icon, required this.onTap, super.key});
  final PabloIconName icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverSurface(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: PabloDurations.hover,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? PabloColors.lightboxNavHoverBg : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: PabloIcon(
          icon,
          size: 20,
          color: hovered
              ? PabloColors.lightboxNavHoverIcon
              : PabloColors.lightboxNavIcon,
        ),
      ),
    );
  }
}

/// Lightbox top-bar fullscreen toggle — borderless glyph that brightens into a
/// dark well on hover, mirroring [NavArrowButton].
class FullscreenButton extends StatelessWidget {
  const FullscreenButton({
    required this.fullscreen,
    required this.onTap,
    super.key,
  });
  final bool fullscreen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: fullscreen ? 'Exit Fullscreen (F)' : 'Fullscreen (F)',
      child: HoverSurface(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: PabloDurations.hover,
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                hovered ? PabloColors.lightboxNavHoverBg : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: PabloIcon(
            fullscreen ? PabloIconName.zoomOut : PabloIconName.zoomIn,
            size: 16,
            color: hovered
                ? PabloColors.lightboxNavHoverIcon
                : PabloColors.lightboxNavIcon,
          ),
        ),
      ),
    );
  }
}

/// A generic lightbox top-bar icon button (tooltip + hover well), matching
/// [FullscreenButton]'s styling. Used for the Slideshow launcher.
class TopBarButton extends StatelessWidget {
  const TopBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });
  final PabloIconName icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: HoverSurface(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: PabloDurations.hover,
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                hovered ? PabloColors.lightboxNavHoverBg : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: PabloIcon(
            icon,
            size: 16,
            color: hovered
                ? PabloColors.lightboxNavHoverIcon
                : PabloColors.lightboxNavIcon,
          ),
        ),
      ),
    );
  }
}

/// Horizontal gradient that fades the filmstrip into the lightbox chrome at
/// each edge.
class FilmEdgeFade extends StatelessWidget {
  const FilmEdgeFade({required this.left, super.key});
  final bool left;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            PabloColors.lightboxBackground,
            PabloColors.lightboxBackground.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
