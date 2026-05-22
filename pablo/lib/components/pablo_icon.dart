// Pablo icon set — ports the 24×24 SVG paths from pablo3-foundation.jsx
// `Icon({ name })`. Rendered via CustomPainter so stroke weight is controlled
// by `PabloIcons.stroke` rather than baked in.

import 'dart:math' as math;

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

class PabloIcon extends StatelessWidget {
  const PabloIcon(
    this.name, {
    this.size = 16,
    this.color,
    this.strokeWidth,
    super.key,
  });

  final PabloIconName name;
  final double size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? PabloColors.textPrimary;
    final stroke = strokeWidth ??
        (_emphasized.contains(name) ? PabloIcons.stroke : PabloIcons.strokeLight);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PabloIconPainter(name: name, color: c, strokeWidth: stroke),
      ),
    );
  }

  static const _emphasized = <PabloIconName>{
    PabloIconName.rotateLeft,
    PabloIconName.rotateRight,
    PabloIconName.star,
    PabloIconName.plus,
    PabloIconName.clock,
  };
}

class _PabloIconPainter extends CustomPainter {
  _PabloIconPainter({
    required this.name,
    required this.color,
    required this.strokeWidth,
  });

  final PabloIconName name;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // All paths are designed on a 24-unit viewBox. Scale.
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (name) {
      case PabloIconName.library:
        _rrect(canvas, stroke, 3, 3, 18, 18, 2);
        canvas.drawCircle(const Offset(8.5, 8.5), 1.5, stroke);
        canvas.drawPath(
          _path([
            const Offset(21, 15),
            const Offset(16, 10),
            const Offset(5, 21),
          ]),
          stroke,
        );
      case PabloIconName.people:
        canvas.drawPath(
          _open([
            const Offset(16, 21),
            const Offset(16, 19),
          ])
            ..arcToPoint(const Offset(12, 15), radius: const Radius.circular(4))
            ..lineTo(6, 15)
            ..arcToPoint(const Offset(2, 19), radius: const Radius.circular(4))
            ..lineTo(2, 21),
          stroke,
        );
        canvas.drawCircle(const Offset(9, 7), 4, stroke);
        // Second figure
        canvas.drawPath(
          _open([const Offset(22, 21), const Offset(22, 19)])
            ..arcToPoint(const Offset(19, 15.13),
                radius: const Radius.circular(4)),
          stroke,
        );
        canvas.drawPath(
          Path()..moveTo(16, 3.13)..arcToPoint(const Offset(16, 10.88),
              radius: const Radius.circular(4)),
          stroke,
        );
      case PabloIconName.albums:
        // book-with-spine style album icon
        final body = Paint()
          ..color = PabloColors.iconAlbumBody
          ..style = PaintingStyle.fill;
        final spine = Paint()
          ..color = PabloColors.iconAlbumSpine
          ..style = PaintingStyle.fill;
        final bodyStroke = Paint()
          ..color = PabloColors.iconAlbumSpine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7;
        final rect = RRect.fromLTRBR(2.5, 1, 14.5, 17, const Radius.circular(1.5));
        canvas.drawRRect(rect, body);
        canvas.drawRRect(rect, bodyStroke);
        canvas.drawRRect(
          RRect.fromLTRBR(2, 1, 5.5, 17, const Radius.circular(1)),
          spine,
        );
        final lineP = Paint()
          ..color = PabloColors.iconAlbumLine
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        canvas.drawLine(const Offset(7.5, 5), const Offset(13, 5), lineP);
        canvas.drawLine(const Offset(7.5, 8), const Offset(13, 8), lineP);
        canvas.drawLine(const Offset(7.5, 11), const Offset(13, 11), lineP);
      case PabloIconName.search:
        canvas.drawCircle(const Offset(11, 11), 7, stroke);
        canvas.drawLine(const Offset(16.5, 16.5), const Offset(21, 21), stroke);
      case PabloIconName.importIcon:
        canvas.drawPath(
          Path()
            ..moveTo(21, 15)
            ..lineTo(21, 19)
            ..arcToPoint(const Offset(19, 21), radius: const Radius.circular(2))
            ..lineTo(5, 21)
            ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
            ..lineTo(3, 15),
          stroke,
        );
        canvas.drawPath(_open([
          const Offset(7, 10),
          const Offset(12, 15),
          const Offset(17, 10),
        ]), stroke);
        canvas.drawLine(const Offset(12, 15), const Offset(12, 3), stroke);
      case PabloIconName.trash:
        canvas.drawPath(_open([
          const Offset(3, 6),
          const Offset(5, 6),
          const Offset(21, 6),
        ]), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(19, 6)
            ..lineTo(18, 20)
            ..arcToPoint(const Offset(16, 22), radius: const Radius.circular(2))
            ..lineTo(8, 22)
            ..arcToPoint(const Offset(6, 20), radius: const Radius.circular(2))
            ..lineTo(5, 6),
          stroke,
        );
        canvas.drawLine(const Offset(10, 11), const Offset(10, 17), stroke);
        canvas.drawLine(const Offset(14, 11), const Offset(14, 17), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9, 6)
            ..lineTo(9, 4)
            ..arcToPoint(const Offset(10, 3), radius: const Radius.circular(1))
            ..lineTo(14, 3)
            ..arcToPoint(const Offset(15, 4), radius: const Radius.circular(1))
            ..lineTo(15, 6),
          stroke,
        );
      case PabloIconName.folder:
      case PabloIconName.folderOpen:
        final bool open = name == PabloIconName.folderOpen;
        // 20×17 viewBox compressed into 24 scale by drawing scaled
        canvas.save();
        canvas.translate(2, 4);
        canvas.scale(20 / 24);
        final folderBody = Paint()
          ..color = open ? PabloColors.iconFolderBodyOpen : PabloColors.iconFolderBody
          ..style = PaintingStyle.fill;
        final folderEdge = Paint()
          ..color = open ? PabloColors.iconFolderEdgeOpen : PabloColors.iconFolderEdge
          ..style = PaintingStyle.fill;
        final folderStroke = Paint()
          ..color = open ? PabloColors.iconFolderEdgeOpen : PabloColors.iconFolderEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeJoin = StrokeJoin.round;
        final p = Path()
          ..moveTo(1, 5.5)
          ..arcToPoint(const Offset(2.4, 4), radius: const Radius.circular(1.4))
          ..lineTo(8, 4)
          ..lineTo(10, 6)
          ..lineTo(18.6, 6)
          ..arcToPoint(const Offset(20, 7.4), radius: const Radius.circular(1.4))
          ..lineTo(20, 15)
          ..arcToPoint(const Offset(18.6, 16.4), radius: const Radius.circular(1.4))
          ..lineTo(2.4, 16.4)
          ..arcToPoint(const Offset(1, 15), radius: const Radius.circular(1.4))
          ..close();
        canvas.drawPath(p, folderBody);
        canvas.drawPath(p, folderStroke);
        canvas.drawPath(
          Path()
            ..moveTo(1, 7.5)
            ..lineTo(19, 7.5)
            ..lineTo(19, 6.9)
            ..arcToPoint(const Offset(17.6, 5.4), radius: const Radius.circular(1.4), clockwise: false)
            ..lineTo(10, 5.4)
            ..lineTo(8, 4)
            ..lineTo(2.4, 4)
            ..arcToPoint(const Offset(1, 5.4), radius: const Radius.circular(1.4), clockwise: false)
            ..close(),
          folderEdge,
        );
        canvas.restore();
      case PabloIconName.chevDown:
        canvas.drawPath(_open([
          const Offset(6, 9),
          const Offset(12, 15),
          const Offset(18, 9),
        ]), stroke);
      case PabloIconName.chevRight:
        canvas.drawPath(_open([
          const Offset(9, 6),
          const Offset(15, 12),
          const Offset(9, 18),
        ]), stroke);
      case PabloIconName.arrowLeft:
        canvas.drawLine(const Offset(19, 12), const Offset(5, 12), stroke);
        canvas.drawPath(_open([
          const Offset(12, 19),
          const Offset(5, 12),
          const Offset(12, 5),
        ]), stroke);
      case PabloIconName.arrowRight:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
        canvas.drawPath(_open([
          const Offset(12, 5),
          const Offset(19, 12),
          const Offset(12, 19),
        ]), stroke);
      case PabloIconName.filter:
        canvas.drawLine(const Offset(4, 6), const Offset(20, 6), stroke);
        canvas.drawLine(const Offset(7, 12), const Offset(17, 12), stroke);
        canvas.drawLine(const Offset(10, 18), const Offset(14, 18), stroke);
      case PabloIconName.sort:
        canvas.drawLine(const Offset(4, 6), const Offset(13, 6), stroke);
        canvas.drawLine(const Offset(4, 12), const Offset(10, 12), stroke);
        canvas.drawLine(const Offset(4, 18), const Offset(7, 18), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(18, 4)
            ..lineTo(18, 20)
            ..moveTo(18, 20)
            ..lineTo(21, 17)
            ..moveTo(18, 20)
            ..lineTo(15, 17),
          stroke,
        );
      case PabloIconName.grid:
        _rrect(canvas, stroke, 3, 3, 7, 7, 1);
        _rrect(canvas, stroke, 14, 3, 7, 7, 1);
        _rrect(canvas, stroke, 3, 14, 7, 7, 1);
        _rrect(canvas, stroke, 14, 14, 7, 7, 1);
      case PabloIconName.masonry:
        _rrect(canvas, stroke, 3, 3, 7, 9, 1);
        _rrect(canvas, stroke, 14, 3, 7, 5, 1);
        _rrect(canvas, stroke, 3, 15, 7, 6, 1);
        _rrect(canvas, stroke, 14, 11, 7, 10, 1);
      case PabloIconName.list:
        canvas.drawLine(const Offset(9, 6), const Offset(21, 6), stroke);
        canvas.drawLine(const Offset(9, 12), const Offset(21, 12), stroke);
        canvas.drawLine(const Offset(9, 18), const Offset(21, 18), stroke);
        canvas.drawCircle(const Offset(5, 6), 1, fill);
        canvas.drawCircle(const Offset(5, 12), 1, fill);
        canvas.drawCircle(const Offset(5, 18), 1, fill);
      case PabloIconName.panelRight:
        _rrect(canvas, stroke, 3, 3, 18, 18, 2);
        canvas.drawLine(const Offset(15, 3), const Offset(15, 21), stroke);
      case PabloIconName.star:
        canvas.drawPath(_star(), stroke);
      case PabloIconName.starFill:
        canvas.drawPath(_star(), fill);
      case PabloIconName.info:
        canvas.drawCircle(const Offset(12, 12), 10, stroke);
        canvas.drawLine(const Offset(12, 16), const Offset(12, 12), stroke);
        canvas.drawCircle(const Offset(12, 8), 0.7, fill);
      case PabloIconName.infoFill:
        canvas.drawCircle(const Offset(12, 12), 10, fill);
        final cut = Paint()
          ..color = PabloColors.backgroundSurface
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(12, 7), 1.3, cut);
        canvas.drawRRect(
          RRect.fromLTRBR(10.5, 10.5, 13.5, 17, const Radius.circular(1.5)),
          cut,
        );
      case PabloIconName.tag:
        canvas.drawPath(_tagPath(), stroke);
        canvas.drawCircle(const Offset(7, 7), 1, fill);
      case PabloIconName.tagFill:
        canvas.drawPath(_tagPath(), fill);
        final cut = Paint()
          ..color = PabloColors.backgroundSurface
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(7, 7), 1.2, cut);
      case PabloIconName.person:
        canvas.drawPath(
          Path()
            ..moveTo(20, 21)
            ..lineTo(20, 19)
            ..arcToPoint(const Offset(16, 15), radius: const Radius.circular(4))
            ..lineTo(8, 15)
            ..arcToPoint(const Offset(4, 19), radius: const Radius.circular(4))
            ..lineTo(4, 21),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 7), 4, stroke);
      case PabloIconName.personFill:
        canvas.drawCircle(const Offset(12, 7), 4, fill);
        canvas.drawPath(
          Path()
            ..moveTo(20, 21)
            ..lineTo(20, 19)
            ..arcToPoint(const Offset(16, 15), radius: const Radius.circular(4))
            ..lineTo(8, 15)
            ..arcToPoint(const Offset(4, 19), radius: const Radius.circular(4))
            ..lineTo(4, 21)
            ..close(),
          fill,
        );
      case PabloIconName.close:
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), stroke);
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), stroke);
      case PabloIconName.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), stroke);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
      case PabloIconName.minus:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
      case PabloIconName.more:
        canvas.drawCircle(const Offset(12, 5), 1, fill);
        canvas.drawCircle(const Offset(12, 12), 1, fill);
        canvas.drawCircle(const Offset(12, 19), 1, fill);
      case PabloIconName.moreHorizontal:
        canvas.drawCircle(const Offset(5, 12), 1.5, fill);
        canvas.drawCircle(const Offset(12, 12), 1.5, fill);
        canvas.drawCircle(const Offset(19, 12), 1.5, fill);
      case PabloIconName.camera:
        canvas.drawPath(
          Path()
            ..moveTo(23, 19)
            ..arcToPoint(const Offset(21, 21), radius: const Radius.circular(2))
            ..lineTo(3, 21)
            ..arcToPoint(const Offset(1, 19), radius: const Radius.circular(2))
            ..lineTo(1, 8)
            ..arcToPoint(const Offset(3, 6), radius: const Radius.circular(2))
            ..lineTo(7, 6)
            ..lineTo(9, 3)
            ..lineTo(15, 3)
            ..lineTo(17, 6)
            ..lineTo(21, 6)
            ..arcToPoint(const Offset(23, 8), radius: const Radius.circular(2))
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 13), 4, stroke);
      case PabloIconName.cameraFill:
        canvas.drawPath(
          Path()
            ..moveTo(21, 6)
            ..lineTo(17, 6)
            ..lineTo(15, 3)
            ..lineTo(9, 3)
            ..lineTo(7, 6)
            ..lineTo(3, 6)
            ..arcToPoint(const Offset(1, 8), radius: const Radius.circular(2))
            ..lineTo(1, 19)
            ..arcToPoint(const Offset(3, 21), radius: const Radius.circular(2))
            ..lineTo(21, 21)
            ..arcToPoint(const Offset(23, 19), radius: const Radius.circular(2))
            ..lineTo(23, 8)
            ..arcToPoint(const Offset(21, 6), radius: const Radius.circular(2))
            ..close(),
          fill,
        );
        // Cut-out lens
        final cut = Paint()
          ..color = PabloColors.assignGreen
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(12, 13), 4, cut);
      case PabloIconName.map:
        canvas.drawPath(
          Path()
            ..moveTo(21, 10)
            ..cubicTo(21, 17, 12, 23, 12, 23)
            ..cubicTo(12, 23, 3, 17, 3, 10)
            ..arcToPoint(const Offset(21, 10),
                radius: const Radius.circular(9)),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 10), 3, stroke);
      case PabloIconName.calendar:
        _rrect(canvas, stroke, 3, 4, 18, 18, 2);
        canvas.drawLine(const Offset(16, 2), const Offset(16, 6), stroke);
        canvas.drawLine(const Offset(8, 2), const Offset(8, 6), stroke);
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), stroke);
      case PabloIconName.exportIcon:
        canvas.drawPath(
          Path()
            ..moveTo(21, 15)
            ..lineTo(21, 19)
            ..arcToPoint(const Offset(19, 21), radius: const Radius.circular(2))
            ..lineTo(5, 21)
            ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
            ..lineTo(3, 15),
          stroke,
        );
        canvas.drawPath(_open([
          const Offset(17, 8),
          const Offset(12, 3),
          const Offset(7, 8),
        ]), stroke);
        canvas.drawLine(const Offset(12, 3), const Offset(12, 15), stroke);
      case PabloIconName.move:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(12, 5)
            ..lineTo(19, 12)
            ..lineTo(12, 19),
          stroke,
        );
      case PabloIconName.rotateLeft:
        canvas.drawPath(_open([
          const Offset(1, 4),
          const Offset(1, 10),
          const Offset(7, 10),
        ]), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(3.51, 15)
            ..arcToPoint(const Offset(5.64, 5.64),
                radius: const Radius.circular(9),
                largeArc: true,
                clockwise: false)
            ..lineTo(1, 10),
          stroke,
        );
      case PabloIconName.rotateRight:
        canvas.drawPath(_open([
          const Offset(23, 4),
          const Offset(23, 10),
          const Offset(17, 10),
        ]), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(20.49, 15)
            ..arcToPoint(const Offset(18.37, 5.64),
                radius: const Radius.circular(9),
                largeArc: true)
            ..lineTo(23, 10),
          stroke,
        );
      case PabloIconName.clock:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        canvas.drawPath(_open([
          const Offset(12, 7),
          const Offset(12, 12),
          const Offset(15, 15),
        ]), stroke);
      case PabloIconName.settings:
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
        // simplified gear ring
        for (int i = 0; i < 8; i++) {
          final a = i * 0.7854; // 45 deg increments
          final dx = 12 + 9 * (i.isEven ? 1 : 0.9) * cos(a);
          final dy = 12 + 9 * (i.isEven ? 1 : 0.9) * sin(a);
          canvas.drawLine(
            Offset(12 + 5 * cos(a), 12 + 5 * sin(a)),
            Offset(dx, dy),
            stroke,
          );
        }
      case PabloIconName.play:
        canvas.drawPath(
          Path()
            ..moveTo(5, 3)
            ..lineTo(19, 12)
            ..lineTo(5, 21)
            ..close(),
          stroke,
        );
      case PabloIconName.playFill:
        canvas.drawPath(
          Path()
            ..moveTo(5, 3)
            ..lineTo(19, 12)
            ..lineTo(5, 21)
            ..close(),
          fill,
        );
      case PabloIconName.check:
        canvas.drawPath(_open([
          const Offset(5, 12),
          const Offset(10, 17),
          const Offset(19, 7),
        ]), stroke);
      case PabloIconName.lock:
        canvas.drawRRect(
          RRect.fromLTRBR(4, 11, 20, 22, const Radius.circular(2.5)),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8, 11)
            ..lineTo(8, 7)
            ..arcToPoint(const Offset(16, 7), radius: const Radius.circular(4))
            ..lineTo(16, 11),
          stroke,
        );
        final inner = Paint()
          ..color = PabloColors.backgroundSurface
          ..style = PaintingStyle.fill;
        canvas.drawCircle(const Offset(12, 16), 1.5, inner);
      case PabloIconName.unlock:
        canvas.drawRRect(
          RRect.fromLTRBR(4, 11, 20, 22, const Radius.circular(2.5)),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16, 11)
            ..lineTo(16, 7)
            ..arcToPoint(const Offset(8, 7),
                radius: const Radius.circular(4), clockwise: false),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 16), 1.5, fill);
      case PabloIconName.straighten:
        canvas.drawLine(const Offset(3, 12), const Offset(21, 12), stroke);
        canvas.drawPath(_open([
          const Offset(16, 8),
          const Offset(20, 12),
          const Offset(16, 16),
        ]), stroke);
        canvas.drawPath(_open([
          const Offset(8, 8),
          const Offset(4, 12),
          const Offset(8, 16),
        ]), stroke);
      case PabloIconName.flipHorizontal:
        canvas.drawLine(const Offset(12, 3), const Offset(12, 21), stroke);
        canvas.drawPath(_open([
          const Offset(5, 8),
          const Offset(2, 12),
          const Offset(5, 16),
        ]), stroke);
        canvas.drawPath(_open([
          const Offset(19, 8),
          const Offset(22, 12),
          const Offset(19, 16),
        ]), stroke);
      case PabloIconName.flipVertical:
        canvas.drawLine(const Offset(3, 12), const Offset(21, 12), stroke);
        canvas.drawPath(_open([
          const Offset(8, 5),
          const Offset(12, 2),
          const Offset(16, 5),
        ]), stroke);
        canvas.drawPath(_open([
          const Offset(8, 19),
          const Offset(12, 22),
          const Offset(16, 19),
        ]), stroke);
      case PabloIconName.heal:
        canvas.drawCircle(const Offset(12, 12), 8, stroke);
        canvas.drawLine(const Offset(12, 8), const Offset(12, 16), stroke);
        canvas.drawLine(const Offset(8, 12), const Offset(16, 12), stroke);
      case PabloIconName.redEye:
        canvas.drawPath(
          Path()
            ..moveTo(1, 12)
            ..cubicTo(1, 12, 5, 5, 12, 5)
            ..cubicTo(19, 5, 23, 12, 23, 12)
            ..cubicTo(23, 12, 19, 19, 12, 19)
            ..cubicTo(5, 19, 1, 12, 1, 12)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 12), 2.5, stroke);
        canvas.drawLine(const Offset(3.5, 3.5), const Offset(20.5, 20.5), stroke);
      case PabloIconName.crop:
        canvas.drawPath(
          Path()
            ..moveTo(6, 2)
            ..lineTo(6, 16)
            ..arcToPoint(const Offset(8, 18), radius: const Radius.circular(2))
            ..lineTo(22, 18),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(18, 22)
            ..lineTo(18, 8)
            ..arcToPoint(const Offset(16, 6), radius: const Radius.circular(2))
            ..lineTo(2, 6),
          stroke,
        );
      case PabloIconName.zoomIn:
        canvas.drawCircle(const Offset(11, 11), 7, stroke);
        canvas.drawLine(const Offset(16.5, 16.5), const Offset(21, 21), stroke);
        canvas.drawLine(const Offset(8, 11), const Offset(14, 11), stroke);
        canvas.drawLine(const Offset(11, 8), const Offset(11, 14), stroke);
      case PabloIconName.zoomOut:
        canvas.drawCircle(const Offset(11, 11), 7, stroke);
        canvas.drawLine(const Offset(16.5, 16.5), const Offset(21, 21), stroke);
        canvas.drawLine(const Offset(8, 11), const Offset(14, 11), stroke);
    }

    canvas.restore();
  }

  // Helpers
  Path _open(List<Offset> pts) {
    final p = Path();
    if (pts.isEmpty) return p;
    p.moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    return p;
  }

  Path _path(List<Offset> pts) {
    final p = _open(pts);
    return p;
  }

  void _rrect(
    Canvas canvas,
    Paint paint,
    double x,
    double y,
    double w,
    double h,
    double r,
  ) {
    canvas.drawRRect(
      RRect.fromLTRBR(x, y, x + w, y + h, Radius.circular(r)),
      paint,
    );
  }

  Path _star() => Path()
    ..moveTo(12, 2)
    ..lineTo(15.09, 8.26)
    ..lineTo(22, 9.27)
    ..lineTo(17, 14.14)
    ..lineTo(18.18, 21.02)
    ..lineTo(12, 17.77)
    ..lineTo(5.82, 21.02)
    ..lineTo(7, 14.14)
    ..lineTo(2, 9.27)
    ..lineTo(8.91, 8.26)
    ..close();

  Path _tagPath() => Path()
    ..moveTo(20.59, 13.41)
    ..lineTo(13.42, 20.58)
    ..arcToPoint(const Offset(10.59, 20.58), radius: const Radius.circular(2))
    ..lineTo(2, 12)
    ..lineTo(2, 2)
    ..lineTo(12, 2)
    ..lineTo(20.59, 10.59)
    ..arcToPoint(const Offset(20.59, 13.41), radius: const Radius.circular(2))
    ..close();

  @override
  bool shouldRepaint(covariant _PabloIconPainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

double cos(double a) => math.cos(a);
double sin(double a) => math.sin(a);
