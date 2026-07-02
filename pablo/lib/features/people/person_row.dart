import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../components/hover_surface.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'people_controller.dart';
import 'people_scope.dart';

class PersonRow extends StatelessWidget {
  const PersonRow({
    required this.person,
    required this.selected,
    required this.onSelect,
    this.narrow = false,
    super.key,
  });

  final Person person;
  final bool selected;
  final VoidCallback onSelect;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final pc = PeopleScope.of(context);
    final lowConf = pc.isLive
        ? pc.lowConfidenceCount(
            PeopleController.nativePersonId(person.id) ?? -1)
        : 0;
    final label = narrow ? person.name.split(' ').first : person.name;
    return HoverSurface(
      onTap: onSelect,
      builder: (context, hovered) {
        final bg = selected
            ? PabloColors.selectionBackground
            : hovered
                ? PabloColors.backgroundSidebarHover
                : Colors.transparent;
        return AnimatedContainer(
          duration: PabloDurations.hover,
          margin: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: PabloSpacing.xxxl,
                  right: PabloSpacing.xl,
                ),
                child: Row(
                  children: [
                    PabloAvatar(
                      name: person.name,
                      hue: person.hue,
                      size: 20,
                    ),
                    const SizedBox(width: PabloSpacing.base),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: PabloTypography.sans(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${person.count}',
                      style: PabloTypography.mono(fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Low-confidence "?" badge in the left gutter — sits beside the
              // avatar without shifting it (matches v4).
              if (lowConf > 0)
                const Positioned(
                  left: 3,
                  top: 0,
                  bottom: 0,
                  child: Center(child: _LowConfBadge()),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 14px amber circle with a white "?" — marks a person with low-confidence
/// suggestions awaiting review.
class _LowConfBadge extends StatelessWidget {
  const _LowConfBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PabloColors.warning,
        shape: BoxShape.circle,
        border: Border.all(color: PabloColors.warningBadgeBorder, width: 1.5),
      ),
      child: const Text(
        '?',
        style: TextStyle(
          color: PabloColors.textOnAccent,
          fontWeight: FontWeight.w700,
          fontSize: 8.5,
          height: 1,
        ),
      ),
    );
  }
}
