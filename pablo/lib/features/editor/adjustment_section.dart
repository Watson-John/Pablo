import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';

class AdjustmentSection extends StatelessWidget {
  const AdjustmentSection({
    required this.label,
    required this.open,
    required this.onToggle,
    required this.children,
    super.key,
  });

  final String label;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              margin: const EdgeInsets.only(bottom: PabloSpacing.lg),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: PabloColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label.toUpperCase(),
                      style: PabloTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: PabloDurations.expand,
                    child: const PabloIcon(
                      PabloIconName.chevRight,
                      size: 10,
                      color: PabloColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) ...children,
      ],
    );
  }
}
