import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../components/pablo_badge.dart';
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
          padding: const EdgeInsets.only(
            left: PabloSpacing.xxxl,
            right: PabloSpacing.xl,
          ),
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: PabloRadius.mdAll,
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
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (lowConf > 0) ...[
                PabloBadge.warning(),
                const SizedBox(width: PabloSpacing.sm),
              ],
              Text(
                '${widget.person.count}',
                style: PabloTypography.mono(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
