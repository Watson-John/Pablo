// Shared widgets used across the photo info panel tabs.

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class InfoSectionHeader extends StatelessWidget {
  const InfoSectionHeader(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: PabloSpacing.base),
      padding: const EdgeInsets.only(bottom: PabloSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Text(
        label.toUpperCase(),
        style: PabloTypography.sans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: PabloColors.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: PabloTypography.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: PabloTypography.mono(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
