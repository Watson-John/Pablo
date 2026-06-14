// Shared widgets used across the photo info panel tabs.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';

/// A grouping label inside an inspector tab (e.g. PEOPLE, TAGS) with an
/// optional right-aligned action (a "Manage →" link).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {this.right, super.key});
  final String label;
  final Widget? right;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: PabloSpacing.base),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: PabloTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.05 * 11,
            ),
          ),
          if (right != null) right!,
        ],
      ),
    );
  }
}

/// Icon + uppercase micro-label + value block — the Info-tab property row.
class MetaRow extends StatelessWidget {
  const MetaRow({
    required this.icon,
    required this.label,
    required this.child,
    super.key,
  });
  final PabloIconName icon;
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PabloSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: PabloIcon(icon, size: 16, color: PabloColors.textMuted),
          ),
          const SizedBox(width: PabloSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: PabloTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: PabloColors.textMuted,
                    letterSpacing: 0.05 * 10,
                  ),
                ),
                const SizedBox(height: 2),
                DefaultTextStyle(
                  style: PabloTypography.sans(fontSize: 12.5, height: 1.4),
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Azure clickable text link used for "Manage →" / "Open folder location".
class InspectorLink extends StatelessWidget {
  const InspectorLink(this.label, {required this.onTap, this.fontSize = 11, super.key});
  final String label;
  final VoidCallback onTap;
  final double fontSize;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: PabloTypography.sans(
            fontSize: fontSize,
            color: PabloColors.accentPrimary,
          ),
        ),
      ),
    );
  }
}

