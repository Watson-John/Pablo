// Pablo design tokens.
//
// This is the ONLY file in lib/ that may declare raw color / spacing / radius
// literals. Every component must consume tokens from this file. See CLAUDE.md
// for the enforcement rules.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PabloColors {
  PabloColors._();

  // Warm surfaces
  static const Color backgroundShell = Color(0xFFF3EDE6);
  static const Color backgroundSidebar = Color(0xFFEAE4DB);
  static const Color backgroundSidebarHover = Color(0xFFE0D9CE);
  static const Color backgroundSidebarActive = Color(0xFFD8D0C3);
  static const Color backgroundSurface = Color(0xFFFDFAF6);
  static const Color backgroundSurfaceAlt = Color(0xFFF7F2EC);
  static const Color backgroundHover = Color(0xFFF0EBE3);
  static const Color backgroundActive = Color(0xFFE6DFD5);
  static const Color backgroundSelected = Color(0xFFFBF0E0);

  // Borders
  static const Color borderSubtle = Color(0xFFDDD6CA);
  static const Color borderStrong = Color(0xFFC8C0B2);

  // Text
  static const Color textPrimary = Color(0xFF2D2820);
  static const Color textSecondary = Color(0xFF5C554A);
  static const Color textMuted = Color(0xFF9A9286);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Copper accent (actions, sliders, copper-tinted UI)
  static const Color accentPrimary = Color(0xFFC17A3A);
  static const Color accentHover = Color(0xFFA8682F);
  static const Color accentActive = Color(0xFF8F5725);
  static const Color accentBackground = Color(0xFFFBF0E0);
  static const Color accentSoft = Color(0xFFF5E3CC);

  // Blue selection (sidebar active, photo selection ring)
  static const Color selectionPrimary = Color(0xFF2563EB);
  static const Color selectionPrimaryHover = Color(0xFF1D4ED8);
  static const Color selectionBackground = Color(0xFFDBEAFE);

  // Status colors
  static const Color success = Color(0xFF5E8E52);
  static const Color successBackground = Color(0xFFEEF5EC);
  static const Color successText = Color(0xFF3D6433);
  static const Color successBorder = Color(0xFFBBF7D0);

  static const Color error = Color(0xFFC06058);
  static const Color errorBackground = Color(0xFFFDF0EE);
  static const Color errorText = Color(0xFF8B3E38);

  static const Color warning = Color(0xFFE8762A);
  static const Color warningBackground = Color(0xFFFFF3E8);
  static const Color warningText = Color(0xFFB05518);
  static const Color warningBorder = Color(0xFFFCD34D);

  static const Color amber = Color(0xFFD4952E);

  // Assign / ignore actions
  static const Color assignGreen = Color(0xFF5E9E58);
  static const Color assignGreenHover = Color(0xFF4E8A49);
  static const Color assignGreenActive = Color(0xFF347259);
  static const Color ignoreRed = Color(0xFFC47068);
  static const Color ignoreRedHover = Color(0xFFAD5E57);
  static const Color ignoreRedActive = Color(0xFF944E4A);

  // Editor / dark surfaces (lightbox)
  static const Color lightboxBackground = Color(0xFF1A1410);

  // Map ocean
  static const Color mapOcean = Color(0xFFC8D8EA);
  static const Color mapOceanLight = Color(0xFFD8E4F0);
  static const Color mapLand = Color(0xFFEDE8DF);
  static const Color mapLandBorder = Color(0xFFC0B8A8);
  static const Color mapGridLine = Color(0x2E8CA5C8);
  static const Color mapHeatStroke = Color(0x73945014);
  static const Color mapCenterDot = Color(0xE6FFFFFF);

  // macOS-style traffic lights (title bar decoration)
  static const Color titleRed = Color(0xFFFF5F57);
  static const Color titleRedOutline = Color(0xFFE0443E);
  static const Color titleYellow = Color(0xFFFEBC2E);
  static const Color titleYellowOutline = Color(0xFFDEA123);
  static const Color titleGreen = Color(0xFF28C840);
  static const Color titleGreenOutline = Color(0xFF1AAB29);

  // Controls bar specific tints
  static const Color controlsIconWarm = Color(0xFF7B6B4E);
  static const Color controlsTabBackground = Color(0xFF7088B8);
  static const Color controlsTabActiveFg = Color(0xFF111318);
  static const Color controlsTabDivider = Color(0x33FFFFFF);
  static const Color controlsTabHover = Color(0x14000000);

  // Folder / album icon glyph palette
  static const Color iconFolderBody = Color(0xFFF0C56D);
  static const Color iconFolderEdge = Color(0xFFD4A843);
  static const Color iconFolderBodyOpen = Color(0xFFEDBE5A);
  static const Color iconFolderEdgeOpen = Color(0xFFC99A30);
  static const Color iconAlbumBody = Color(0xFFA67B5B);
  static const Color iconAlbumSpine = Color(0xFF7D5A3C);
  static const Color iconAlbumLine = Color(0x73FFFFFF);

  // Avatar / overlays
  static const Color avatarInitial = Color(0xD9FFFFFF);
  static const Color tileGlyph = Color(0x80FFFFFF);
  static const Color tileGlyphFaded = Color(0x66FFFFFF);
  static const Color warningBadgeBorder = Color(0x808F5520);

  /// White with the given alpha (0–1) as a runtime color.
  static Color whiteAlpha(double alpha) =>
      const Color(0xFFFFFFFF).withValues(alpha: alpha);
}

class PabloSpacing {
  PabloSpacing._();
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 6;
  static const double base = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double xxl = 16;
  static const double xxxl = 20;
  static const double xxxxl = 24;
  static const double xxxxxl = 32;
}

class PabloRadius {
  PabloRadius._();
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double panel = 12;
  static const double pill = 20;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius panelAll =
      BorderRadius.all(Radius.circular(panel));
  static const BorderRadius pillAll =
      BorderRadius.all(Radius.circular(pill));
}

class PabloShadows {
  PabloShadows._();

  static const List<BoxShadow> sm = [
    BoxShadow(
      color: Color(0x0F3C2814), // rgba(60,40,20,0.06)
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: Color(0x173C2814), // rgba(60,40,20,0.09)
      offset: Offset(0, 2),
      blurRadius: 10,
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: Color(0x243C2814), // rgba(60,40,20,0.14)
      offset: Offset(0, 8),
      blurRadius: 28,
    ),
    BoxShadow(
      color: Color(0x143C2814), // rgba(60,40,20,0.08)
      offset: Offset(0, 0),
      blurRadius: 1,
    ),
  ];

  // Sidebar drop shadow (2px right)
  static const List<BoxShadow> sidebar = [
    BoxShadow(
      color: Color(0x123C2814),
      offset: Offset(2, 0),
      blurRadius: 10,
    ),
  ];

  // Inverted (under tray)
  static const List<BoxShadow> trayTop = [
    BoxShadow(
      color: Color(0x0F3C2814),
      offset: Offset(0, -2),
      blurRadius: 10,
    ),
  ];

  // Search header
  static const List<BoxShadow> searchHeader = [
    BoxShadow(
      color: Color(0x0F3C2814),
      offset: Offset(0, 1),
      blurRadius: 5,
    ),
  ];

  // Controls bar (above tray)
  static const List<BoxShadow> controlsBar = [
    BoxShadow(
      color: Color(0x0D3C2814),
      offset: Offset(0, -1),
      blurRadius: 5,
    ),
  ];

  // Floating button on controls bar
  static const List<BoxShadow> floatingButton = [
    BoxShadow(
      color: Color(0x1F3C2814),
      offset: Offset(0, 1),
      blurRadius: 4,
    ),
  ];

  // Sticky section header drop shadow (when the section is highlighted)
  static const List<BoxShadow> stickyHighlight = [
    BoxShadow(
      color: Color(0x1B3C2814),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  // Info panel (right side)
  static const List<BoxShadow> infoPanel = [
    BoxShadow(
      color: Color(0x123C2814),
      offset: Offset(-2, 0),
      blurRadius: 10,
    ),
  ];
}

class PabloDurations {
  PabloDurations._();
  static const Duration hover = Duration(milliseconds: 120);
  static const Duration expand = Duration(milliseconds: 150);
  static const Duration page = Duration(milliseconds: 180);
}

class PabloIcons {
  PabloIcons._();
  static const double strokeLight = 1.5;
  static const double stroke = 2.0;
}

/// Centralized typography. Uses google_fonts so the three families resolve
/// without bundled .ttf files; on first run they download once.
class PabloTypography {
  PabloTypography._();

  static TextStyle sans({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color color = PabloColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle serif({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w600,
    Color color = PabloColors.textPrimary,
    double? height,
  }) =>
      GoogleFonts.lora(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );

  static TextStyle mono({
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w400,
    Color color = PabloColors.textMuted,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      );

  // Common pre-baked styles
  static TextStyle get bodySm => sans(fontSize: 12);
  static TextStyle get bodyMd => sans(fontSize: 13);
  static TextStyle get label =>
      sans(fontSize: 12, fontWeight: FontWeight.w500, color: PabloColors.textSecondary);
  static TextStyle get menuItem => sans(fontSize: 12.5, fontWeight: FontWeight.w500);
  static TextStyle get sectionTitle => serif(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle get sectionLabelUpper => sans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: PabloColors.textPrimary,
        letterSpacing: 0.4,
      );
  static TextStyle get count => mono(fontSize: 11);
  static TextStyle get caption =>
      sans(fontSize: 11.5, color: PabloColors.textMuted);
  static TextStyle get button =>
      sans(fontSize: 12, fontWeight: FontWeight.w500);
}
