// Token-styled radio row used in the Advanced Search modal.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PabloRadio<T> extends StatelessWidget {
  const PabloRadio({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
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
                  color: PabloColors.backgroundSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? PabloColors.accentPrimary
                        : PabloColors.borderSubtle,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: PabloColors.accentPrimary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: PabloSpacing.base),
              Text(label, style: PabloTypography.sans(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
