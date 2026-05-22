// 1-pixel resize handle (vertical or horizontal) with the correct system cursor.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum ResizeDirection { column, row }

class ResizeHandle extends StatelessWidget {
  const ResizeHandle({
    required this.direction,
    required this.onResize,
    super.key,
  });

  final ResizeDirection direction;

  /// Called with the cumulative pixel delta. `done` is true once on the
  /// initial press so the caller can snapshot the starting size.
  final void Function(double delta, bool isStart) onResize;

  @override
  Widget build(BuildContext context) {
    final cursor = direction == ResizeDirection.column
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;
    final isCol = direction == ResizeDirection.column;
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onResize(0, true),
        onPanUpdate: (d) {
          onResize(
            isCol ? d.delta.dx : d.delta.dy,
            false,
          );
        },
        child: Container(
          width: isCol ? 4 : double.infinity,
          height: isCol ? double.infinity : 4,
          alignment: Alignment.center,
          child: Container(
            width: isCol ? 1 : double.infinity,
            height: isCol ? double.infinity : 1,
            color: PabloColors.borderSubtle,
          ),
        ),
      ),
    );
  }
}
