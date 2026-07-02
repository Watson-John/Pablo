// Pablo icon set — Material Symbols Rounded (Pablo DS).
//
// Each [PabloIconName] maps to a Material Symbols Rounded glyph (bundled subset
// variable font, see pubspec `fonts:`). Icons render through the real icon font
// with the variable `FILL` and `wght` axes, exactly like the design's
// `ICON_SYMBOLS` map (filled glyphs for active/selected states). `currentColor`
// is honored via the inherited DefaultTextStyle, same as before.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum PabloIconName {
  library,
  people,
  albums,
  search,
  importIcon,
  trash,
  folder,
  folderOpen,
  chevDown,
  chevRight,
  arrowLeft,
  arrowRight,
  filter,
  sort,
  grid,
  masonry,
  list,
  panelRight,
  star,
  starFill,
  sun,
  sparkle,
  droplet,
  save,
  saveFill,
  copy,
  dockToRight,
  info,
  infoFill,
  tag,
  tagFill,
  person,
  personFill,
  close,
  plus,
  more,
  moreHorizontal,
  camera,
  cameraFill,
  map,
  calendar,
  exportIcon,
  move,
  rotateLeft,
  rotateRight,
  clock,
  settings,
  play,
  playFill,
  pause,
  check,
  lock,
  unlock,
  straighten,
  flipHorizontal,
  flipVertical,
  heal,
  redEye,
  crop,
  minus,
  zoomIn,
  zoomOut,
}

/// Material Symbols Rounded codepoint + default FILL for each icon. Filled
/// glyphs (folder, *Fill names) default to FILL 1; everything else FILL 0.
/// Mirrors `ICON_SYMBOLS` in pablo4-foundation.jsx.
class _Glyph {
  const _Glyph(this.code, [this.filled = false]);
  final int code;
  final bool filled;
}

const Map<PabloIconName, _Glyph> _symbols = {
  PabloIconName.library: _Glyph(0xe413), // photo_library
  PabloIconName.people: _Glyph(0xea21), // group
  PabloIconName.albums: _Glyph(0xe411), // photo_album
  PabloIconName.search: _Glyph(0xef7a), // search
  PabloIconName.importIcon: _Glyph(0xf090), // file_download
  PabloIconName.trash: _Glyph(0xe92e), // delete
  PabloIconName.folder: _Glyph(0xe2c7, true), // folder (filled)
  PabloIconName.folderOpen: _Glyph(0xe2c8, true), // folder_open (filled)
  PabloIconName.chevDown: _Glyph(0xe5cf), // expand_more
  PabloIconName.chevRight: _Glyph(0xe5cc), // chevron_right
  PabloIconName.arrowLeft: _Glyph(0xe5c4), // arrow_back
  PabloIconName.arrowRight: _Glyph(0xe5c8), // arrow_forward
  PabloIconName.filter: _Glyph(0xe152), // filter_list
  PabloIconName.sort: _Glyph(0xe164), // sort
  PabloIconName.grid: _Glyph(0xe9b0), // grid_view
  PabloIconName.masonry: _Glyph(0xe871), // dashboard
  PabloIconName.list: _Glyph(0xe8ef), // view_list
  PabloIconName.panelRight: _Glyph(0xf704), // right_panel_open
  PabloIconName.star: _Glyph(0xf09a), // star
  PabloIconName.starFill: _Glyph(0xf09a, true), // star (filled)
  PabloIconName.sun: _Glyph(0xe518), // light_mode
  PabloIconName.sparkle: _Glyph(0xe65f), // auto_awesome
  PabloIconName.droplet: _Glyph(0xe798), // water_drop
  PabloIconName.save: _Glyph(0xe161), // save
  PabloIconName.saveFill: _Glyph(0xe161, true), // save (filled)
  PabloIconName.copy: _Glyph(0xe14d), // content_copy
  PabloIconName.dockToRight: _Glyph(0xf7e4, true), // dock_to_right (filled)
  PabloIconName.info: _Glyph(0xe88e), // info
  PabloIconName.infoFill: _Glyph(0xe88e, true), // info (filled)
  PabloIconName.tag: _Glyph(0xf05b), // sell
  PabloIconName.tagFill: _Glyph(0xf05b, true), // sell (filled)
  PabloIconName.person: _Glyph(0xf0d3), // person
  PabloIconName.personFill: _Glyph(0xf0d3, true), // person (filled)
  PabloIconName.close: _Glyph(0xe5cd), // close
  PabloIconName.plus: _Glyph(0xe145), // add
  PabloIconName.more: _Glyph(0xe5d4), // more_vert
  PabloIconName.moreHorizontal: _Glyph(0xe5d3), // more_horiz
  PabloIconName.camera: _Glyph(0xe412), // photo_camera
  PabloIconName.cameraFill: _Glyph(0xe412, true), // photo_camera (filled)
  PabloIconName.map: _Glyph(0xf1db), // location_on
  PabloIconName.calendar: _Glyph(0xebcc), // calendar_month
  PabloIconName.exportIcon: _Glyph(0xe6b8), // ios_share
  PabloIconName.move: _Glyph(0xf1df), // east
  PabloIconName.rotateLeft: _Glyph(0xe419), // rotate_left
  PabloIconName.rotateRight: _Glyph(0xe41a), // rotate_right
  PabloIconName.clock: _Glyph(0xefd6), // schedule
  PabloIconName.settings: _Glyph(0xe8b8), // settings
  PabloIconName.play: _Glyph(0xe037), // play_arrow
  PabloIconName.playFill: _Glyph(0xe037, true), // play_arrow (filled)
  PabloIconName.pause: _Glyph(0xe034), // pause
  PabloIconName.check: _Glyph(0xe668), // check
  PabloIconName.lock: _Glyph(0xe899), // lock
  PabloIconName.unlock: _Glyph(0xe898), // lock_open
  PabloIconName.straighten: _Glyph(0xe41c), // straighten
  PabloIconName.flipHorizontal: _Glyph(0xe3e8), // flip
  PabloIconName.flipVertical: _Glyph(0xe3e8), // flip
  PabloIconName.heal: _Glyph(0xe3f3), // healing
  PabloIconName.redEye: _Glyph(0xe8f4), // visibility
  PabloIconName.crop: _Glyph(0xe3be), // crop
  PabloIconName.minus: _Glyph(0xe15b), // remove
  PabloIconName.zoomIn: _Glyph(0xe8ff), // zoom_in
  PabloIconName.zoomOut: _Glyph(0xe900), // zoom_out
};

const String _kFontFamily = 'MaterialSymbolsRounded';

class PabloIcon extends StatelessWidget {
  const PabloIcon(
    this.name, {
    this.size = 16,
    this.color,
    this.strokeWidth,
    this.filled,
    this.shadows,
    super.key,
  });

  final PabloIconName name;
  final double size;
  final Color? color;

  /// Optional drop shadow(s) painted behind the glyph (e.g. the star badge rim).
  final List<Shadow>? shadows;

  /// Maps to the Material Symbols `wght` axis (× 150, clamped 100–700), mirroring
  /// the design's `iconStroke` → weight mapping. Null = default weight (300).
  final double? strokeWidth;

  /// Overrides the glyph's default FILL. Null = use the icon's natural fill
  /// (e.g. [PabloIconName.starFill]/[PabloIconName.folder] are filled).
  final bool? filled;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        DefaultTextStyle.of(context).style.color ??
        PabloColors.textPrimary;
    final g = _symbols[name] ?? const _Glyph(0xe5cd); // fallback: close
    final isFilled = filled ?? g.filled;
    // Design uses iconStroke 2.0 → wght 300; a passed strokeWidth scales it.
    final weight = ((strokeWidth ?? 2.0) * 150).clamp(100.0, 700.0).toDouble();
    return Icon(
      IconData(g.code, fontFamily: _kFontFamily),
      size: size,
      color: c,
      fill: isFilled ? 1.0 : 0.0,
      weight: weight,
      grade: 0,
      opticalSize: 24,
      shadows: shadows,
    );
  }
}
