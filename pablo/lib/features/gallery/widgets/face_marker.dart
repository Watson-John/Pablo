// Hover-to-name face box drawn over the lightbox image, extracted from
// lightbox_view.dart.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../../components/hover_surface.dart';
import '../../../theme/tokens.dart';
import '../../people/face_naming.dart';
import '../../people/people_scope.dart';

/// One face box on the lightbox image: a faint always-on outline (so faces are
/// discoverable), brightening on hover and revealing the name / "Name…" bar.
class FaceMarker extends StatelessWidget {
  const FaceMarker({required this.face, super.key});
  final FaceRow face;

  @override
  Widget build(BuildContext context) {
    final pc = PeopleScope.read(context);
    return HoverSurface(
      cursor: MouseCursor.defer,
      builder: (context, hovered) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: hovered
                      ? PabloColors.selectionPrimary
                      : Colors.white.withValues(alpha: 0.4),
                  width: 2,
                ),
                borderRadius: PabloRadius.smAll,
              ),
            ),
          ),
          // The naming field (rounded, matching the Unnamed Faces cards) sits at
          // the box's bottom edge — inside the hover region so it isn't
          // dismissed before it can be clicked. Shown on hover; persists while
          // focused (so the suggestion dropdown is usable).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FaceNameOverlay(
              face: face,
              controller: pc,
              hovered: hovered,
            ),
          ),
        ],
      ),
    );
  }
}
