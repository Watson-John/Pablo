// Pablo design tokens — Pablo Design System (Pablo DS, v4).
//
// This is the ONLY file in lib/ that may declare raw color / spacing / radius
// literals. Every component must consume tokens from this file. See CLAUDE.md
// for the enforcement rules.
//
// Identity: warm-white, photo-first. Surfaces are quiet near-white neutrals so
// the photos carry the color; a single azure accent (#5283e3, white text on
// top) is reserved for ACTION / SELECTION / ACTIVE state. A teal marks
// on-device AI. Semantic hues (sage / clay / amber) are feedback-only.
// Mixed shape language: rounded cards (Material warmth) + squared toolbars
// (Fluent precision). Shadows are warm espresso-tinted, never neutral gray.
//
// Values mirror the bound Pablo DS token files: tokens/colors.css,
// typography.css, spacing.css, elevation.css, motion.css.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PabloColors {
  PabloColors._();

  // ── Warm-white surfaces ──────────────────────────────────────────────
  static const Color backgroundShell = Color(0xFFF6F4F0); // --surface-canvas / warm-100
  static const Color backgroundSidebar = Color(0xFFF1EEE7); // subtly-tinted chrome
  static const Color backgroundSidebarHover = Color(0x0D211C15); // --surface-hover (5% ink)
  static const Color backgroundSidebarActive = Color(0x17211C15); // --surface-active (9% ink)
  static const Color backgroundSurface = Color(0xFFFBFAF8); // --surface-card / warm-50
  static const Color backgroundSurfaceAlt = Color(0xFFEEECE6); // --surface-sunken / warm-150
  static const Color backgroundRaised = Color(0xFFFFFFFF); // --surface-raised (menus/popovers)
  static const Color backgroundHover = Color(0x0D211C15); // --surface-hover
  static const Color backgroundActive = Color(0x17211C15); // --surface-active
  static const Color backgroundSelected = Color(0xFFDDE9FD); // --surface-selected / azure-100

  // ── Warm-neutral borders ─────────────────────────────────────────────
  static const Color borderSubtle = Color(0xFFE6E3DB); // --border-subtle / warm-200
  static const Color borderStrong = Color(0xFFD6D1C6); // --border-default / warm-300

  // ── Warm-espresso ink ────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF211C15); // --text-strong / warm-900
  static const Color textSecondary = Color(0xFF4D4738); // --text-body / warm-700
  static const Color textMuted = Color(0xFF8A8372); // --text-muted / warm-500
  static const Color textFaint = Color(0xFFB2AB9B); // --text-faint / warm-400 (disabled)
  static const Color textOnAccent = Color(0xFFFFFFFF); // white on azure

  // ── Azure — THE brand & action color (white text reads on azure-600) ──
  static const Color accentPrimary = Color(0xFF5283E3); // azure-600
  static const Color accentHover = Color(0xFF3866CF); // azure-700
  static const Color accentActive = Color(0xFF284C9C); // azure-800
  static const Color accentBackground = Color(0xFFDDE9FD); // azure-100 (soft tint)
  static const Color accentSoft = Color(0xFFC2D6FB); // azure-200

  // ── Selection — also azure in the DS (unified action/selection) ───────
  static const Color selectionPrimary = Color(0xFF5283E3); // azure-600
  static const Color selectionPrimaryHover = Color(0xFF3866CF); // azure-700
  static const Color selectionBackground = Color(0xFFDDE9FD); // azure-100

  // ── Feedback hues (distinct from brand) — sage / clay / amber / teal ──
  static const Color success = Color(0xFF4E8460); // sage-500
  static const Color successBackground = Color(0xFFDCE8DB); // sage-100
  static const Color successText = Color(0xFF335C43); // sage-700
  static const Color successBorder = Color(0xFF8FB591); // sage-300

  static const Color error = Color(0xFFB23A2E); // clay-500
  static const Color errorBackground = Color(0xFFF3DCD4); // clay-100
  static const Color errorText = Color(0xFF7D281F); // clay-700
  static const Color errorBorder = Color(0xFFD99681); // clay-300

  static const Color warning = Color(0xFFD98324); // amber-500
  static const Color warningBackground = Color(0xFFFBE4C4); // amber-100
  static const Color warningText = Color(0xFF98591A); // amber-700
  static const Color warningBorder = Color(0xFFEEB164); // amber-300

  static const Color amber = Color(0xFFD98324); // star / folder leaf (amber-500)

  // Teal — info / on-device AI accent
  static const Color info = Color(0xFF2F7D8A); // teal-500
  static const Color infoBackground = Color(0xFFCFE6E6); // teal-100
  static const Color infoText = Color(0xFF1F555E); // teal-700
  static const Color aiAccent = Color(0xFF2F7D8A); // teal — "on-device AI" spark

  // Plum — highlight / new (distinct from azure & teal)
  static const Color highlight = Color(0xFF7A4EA0); // plum-500
  static const Color highlightBackground = Color(0xFFE7DAF0); // plum-100

  // ── Assign / ignore actions — sage / clay ────────────────────────────
  static const Color assignGreen = Color(0xFF4E8460); // sage-500
  static const Color assignGreenHover = Color(0xFF335C43); // sage-700
  static const Color assignGreenActive = Color(0xFF2A4A37);
  static const Color ignoreRed = Color(0xFFB23A2E); // clay-500
  static const Color ignoreRedHover = Color(0xFF7D281F); // clay-700
  static const Color ignoreRedActive = Color(0xFF5E1E17);

  // ── Dark / lightbox surfaces (near-black espresso field) ──────────────
  static const Color lightboxBackground = Color(0xFF14110C); // warm-950
  static const Color darkSurfaceCanvas = Color(0xFF1C1813); // [data-theme=dark] canvas
  static const Color darkSurfaceCard = Color(0xFF251F18);
  static const Color darkTextStrong = Color(0xFFF6EFE2);
  static const Color darkTextBody = Color(0xFFE0D6C5);

  // ── Sidebar section wayfinding colors ────────────────────────────────
  // Earthy, muted per-section icon colors so the eye navigates quickly. Azure
  // stays reserved for the active/selected state (accentActive overrides these).
  static const Color sectionPeople = Color(0xFFD6492A); // terracotta coral
  static const Color sectionAlbums = Color(0xFF8E3FB8); // plum
  static const Color sectionFolders = Color(0xFFE08600); // amber gold
  static const Color sectionTimeline = Color(0xFF1F9550); // sage green
  static const Color sectionMap = Color(0xFF0A938A); // teal

  // ── Lightbox dark-field controls (gray on the espresso canvas) ────────
  static const Color lightboxNavIcon = Color(0xFF6B6B6B); // idle arrow
  static const Color lightboxNavHoverBg = Color(0xFF1E1E1E); // arrow hover well
  static const Color lightboxNavHoverIcon = Color(0xFFE6E6E6); // arrow hover

  // ── Map ───────────────────────────────────────────────────────────────
  static const Color mapOcean = Color(0xFFC8D8EA);
  static const Color mapOceanLight = Color(0xFFD8E4F0);
  static const Color mapLand = Color(0xFFEEECE6);
  static const Color mapLandBorder = Color(0xFFD6D1C6);
  static const Color mapGridLine = Color(0x2E8CA5C8);
  static const Color mapHeatStroke = Color(0x73945014);
  static const Color mapCenterDot = Color(0xE6FFFFFF);

  // ── macOS-style traffic lights (title bar decoration) ─────────────────
  static const Color titleRed = Color(0xFFFF5F57);
  static const Color titleRedOutline = Color(0xFFE0443E);
  static const Color titleYellow = Color(0xFFFEBC2E);
  static const Color titleYellowOutline = Color(0xFFDEA123);
  static const Color titleGreen = Color(0xFF28C840);
  static const Color titleGreenOutline = Color(0xFF1AAB29);

  // ── Controls bar specific tints ───────────────────────────────────────
  static const Color controlsIconWarm = Color(0xFF6A6353); // warm-600
  static const Color controlsTabBackground = Color(0xFF5283E3); // azure (active segment)
  static const Color controlsTabActiveFg = Color(0xFFFFFFFF);
  static const Color controlsTabDivider = Color(0x33FFFFFF);
  static const Color controlsTabHover = Color(0x14000000);

  // ── Folder / album icon glyph palette (matches DS folder leaf) ────────
  static const Color iconFolderBody = Color(0xFFF0C56D);
  static const Color iconFolderEdge = Color(0xFFD4A843);
  static const Color iconFolderBodyOpen = Color(0xFFEDBE5A);
  static const Color iconFolderEdgeOpen = Color(0xFFC99A30);
  static const Color iconAlbumBody = Color(0xFFA67B5B);
  static const Color iconAlbumSpine = Color(0xFF7D5A3C);
  static const Color iconAlbumLine = Color(0x73FFFFFF);

  // ── Avatar / overlays ─────────────────────────────────────────────────
  static const Color avatarInitial = Color(0xD9FFFFFF);
  static const Color tileGlyph = Color(0x80FFFFFF);
  static const Color tileGlyphFaded = Color(0x66FFFFFF);
  static const Color warningBadgeBorder = Color(0x808F5520);

  /// White with the given alpha (0–1) as a runtime color.
  static Color whiteAlpha(double alpha) =>
      const Color(0xFFFFFFFF).withValues(alpha: alpha);

  /// Espresso ink with the given alpha — for warm scrims / hover washes.
  static Color inkAlpha(double alpha) =>
      const Color(0xFF211C15).withValues(alpha: alpha);
}

/// Spacing scale (4px base grid; balanced density).
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

/// Layout rails & control heights (Pablo DS spacing.css).
class PabloSizing {
  PabloSizing._();
  static const double controlSm = 28;
  static const double controlMd = 36; // default button / input
  static const double controlLg = 44; // min touch target
  static const double railSidebar = 248;
  static const double railInspector = 320;
  static const double toolbarHeight = 52;
}

/// Corner radii — mixed: rounded cards + squared toolbar wells.
class PabloRadius {
  PabloRadius._();
  static const double xs = 3; // squared chrome accents, chips
  static const double sm = 6; // inputs, buttons, toolbar wells
  static const double md = 10; // cards, menus
  static const double lg = 14; // panels, dialogs
  static const double panel = 14;
  static const double xl = 20; // large sheets, hero cards
  static const double pill = 999; // pills, avatars

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius panelAll = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Warm espresso-tinted shadows (rgba(33,28,21,…)), soft & diffuse.
class PabloShadows {
  PabloShadows._();

  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x12211C15), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x14211C15), offset: Offset(0, 1), blurRadius: 3),
    BoxShadow(color: Color(0x0F211C15), offset: Offset(0, 1), blurRadius: 2),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x14211C15), offset: Offset(0, 2), blurRadius: 6),
    BoxShadow(color: Color(0x12211C15), offset: Offset(0, 4), blurRadius: 12),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A211C15), offset: Offset(0, 6), blurRadius: 16),
    BoxShadow(color: Color(0x1A211C15), offset: Offset(0, 12), blurRadius: 32),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x24211C15), offset: Offset(0, 12), blurRadius: 28),
    BoxShadow(color: Color(0x29211C15), offset: Offset(0, 24), blurRadius: 64),
  ];

  // Sidebar drop shadow (2px right)
  static const List<BoxShadow> sidebar = [
    BoxShadow(color: Color(0x12211C15), offset: Offset(2, 0), blurRadius: 10),
  ];

  // Inverted (under tray)
  static const List<BoxShadow> trayTop = [
    BoxShadow(color: Color(0x0F211C15), offset: Offset(0, -2), blurRadius: 10),
  ];

  // Search header
  static const List<BoxShadow> searchHeader = [
    BoxShadow(color: Color(0x0F211C15), offset: Offset(0, 1), blurRadius: 5),
  ];

  // Controls bar (above tray)
  static const List<BoxShadow> controlsBar = [
    BoxShadow(color: Color(0x0D211C15), offset: Offset(0, -1), blurRadius: 5),
  ];

  // Floating button on controls bar
  static const List<BoxShadow> floatingButton = [
    BoxShadow(color: Color(0x1F211C15), offset: Offset(0, 1), blurRadius: 4),
  ];

  // Sticky/pinned section header drop shadow
  static const List<BoxShadow> stickyHighlight = [
    BoxShadow(color: Color(0x1B211C15), offset: Offset(0, 1), blurRadius: 3),
  ];

  // Info / inspector panel (left edge)
  static const List<BoxShadow> infoPanel = [
    BoxShadow(color: Color(0x12211C15), offset: Offset(-2, 0), blurRadius: 10),
  ];

  /// Inset shadow for sunken wells (search field, slider track, thumb track).
  static const BoxShadow inset = BoxShadow(
    color: Color(0x14211C15),
    offset: Offset(0, 1),
    blurRadius: 2,
    spreadRadius: -1,
  );
}

/// Motion durations (Pablo DS motion.css — calm & quick).
class PabloDurations {
  PabloDurations._();
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration slower = Duration(milliseconds: 480);

  // Back-compat semantic aliases used across features.
  static const Duration hover = fast; // 140ms
  static const Duration expand = base; // 220ms
  static const Duration page = base; // 220ms
}

/// Motion easing curves (Pablo DS).
class PabloEasing {
  PabloEasing._();
  static const Cubic standard = Cubic(0.2, 0, 0, 1); // enter/exit default
  static const Cubic out = Cubic(0.16, 1, 0.3, 1); // decelerate
  static const Cubic inn = Cubic(0.4, 0, 1, 1); // accelerate
  static const Cubic spring = Cubic(0.34, 1.4, 0.64, 1); // slight overshoot — toggles
}

class PabloIcons {
  PabloIcons._();
  static const double strokeLight = 1.5;
  static const double stroke = 2.0;
}

/// Centralized typography — Pablo DS families via google_fonts (resolved at
/// runtime, no bundled .ttf):
///   • Bricolage Grotesque (display / headings / wordmark) -> [serif]
///   • Hanken Grotesk (UI & body, ss01 on)                 -> [sans]
///   • JetBrains Mono (EXIF, counts, paths, dimensions)    -> [mono]
class PabloTypography {
  PabloTypography._();

  static const List<FontFeature> _ss01 = [FontFeature.enable('ss01')];

  static TextStyle sans({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color color = PabloColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.hankenGrotesk(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      ).copyWith(fontFeatures: _ss01);

  static TextStyle serif({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w600,
    Color color = PabloColors.textPrimary,
    double? height,
    double? letterSpacing = -0.01 * 15, // DS display tracking ≈ -0.01em
  }) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle mono({
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w400,
    Color color = PabloColors.textMuted,
    double? letterSpacing,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // Common pre-baked styles
  static TextStyle get bodySm => sans(fontSize: 12);
  static TextStyle get bodyMd => sans(fontSize: 13);
  static TextStyle get bodyLg => sans(fontSize: 15); // DS base body
  static TextStyle get label => sans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: PabloColors.textSecondary,
      );
  static TextStyle get menuItem =>
      sans(fontSize: 12.5, fontWeight: FontWeight.w500);
  static TextStyle get sectionTitle =>
      serif(fontSize: 17, fontWeight: FontWeight.w600);
  static TextStyle get viewTitle =>
      serif(fontSize: 21, fontWeight: FontWeight.w600);

  /// ALL-CAPS micro label / section eyebrow (e.g. PEOPLE, ALBUMS).
  static TextStyle get sectionLabelUpper => sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: PabloColors.textMuted,
        letterSpacing: 0.04 * 11, // DS tracking-wide 0.04em
      );
  static TextStyle get count => mono(fontSize: 11);
  static TextStyle get caption =>
      sans(fontSize: 11.5, color: PabloColors.textMuted);
  static TextStyle get button =>
      sans(fontSize: 12, fontWeight: FontWeight.w500);
}
