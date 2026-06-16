// Decorative title bar matching the design's macOS-style traffic lights.
// On Windows the real chrome lives above this; here we render the same strip
// for visual parity with the mockup.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSidebar,
        border: Border(
          bottom: BorderSide(color: PabloColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          _trafficLight(PabloColors.titleRed, PabloColors.titleRedOutline),
          const SizedBox(width: PabloSpacing.md + 1),
          _trafficLight(
              PabloColors.titleYellow, PabloColors.titleYellowOutline),
          const SizedBox(width: PabloSpacing.md + 1),
          _trafficLight(PabloColors.titleGreen, PabloColors.titleGreenOutline),
          Expanded(
            child: Center(
              child: Text(
                'Pablo',
                style: PabloTypography.serif(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PabloColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 60),
        ],
      ),
    );
  }

  Widget _trafficLight(Color body, Color outline) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: body,
          shape: BoxShape.circle,
          border: Border.all(color: outline, width: 0.5),
        ),
      );
}
