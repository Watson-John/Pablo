import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../data/models.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';

class PersonRow extends StatefulWidget {
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
  State<PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends State<PersonRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final lowConf = suggestionsFor(widget.person.id)
        .where((s) => s.confidence == SuggestionConfidence.low)
        .length;
    final bg = widget.selected
        ? PabloColors.selectionBackground
        : _hover
            ? PabloColors.backgroundSidebarHover
            : Colors.transparent;
    final label = widget.narrow ? widget.person.name.split(' ').first : widget.person.name;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelect,
        child: AnimatedContainer(
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
                      name: widget.person.name,
                      hue: widget.person.hue,
                      size: 20,
                    ),
                    const SizedBox(width: PabloSpacing.base),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: PabloTypography.sans(
                          fontSize: 12.5,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.person.count}',
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
        ),
      ),
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
