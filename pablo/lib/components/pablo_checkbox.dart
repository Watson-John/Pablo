// Token-styled checkbox row used in the Advanced Search modal.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PabloCheckbox extends StatelessWidget {
  const PabloCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.only(bottom: PabloSpacing.sm + 1),
          child: Row(
            children: [
              AnimatedContainer(
                duration: PabloDurations.hover,
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value
                      ? PabloColors.accentPrimary
                      : PabloColors.backgroundSurface,
                  borderRadius: PabloRadius.smAll,
                  border: Border.all(
                    color: value
                        ? PabloColors.accentPrimary
                        : PabloColors.borderSubtle,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Text(
                        '✓',
                        style: TextStyle(
                          color: PabloColors.textOnAccent,
                          fontSize: 11,
                          height: 1,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: PabloSpacing.base),
              // Flexible so a long label wraps instead of overflowing the
              // fixed-width criteria column.
              Flexible(
                child: Text(label, style: PabloTypography.sans(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
