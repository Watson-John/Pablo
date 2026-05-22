import 'package:flutter/material.dart';

import '../../components/pablo_badge.dart';
import '../../theme/tokens.dart';

class UnnamedFacesRow extends StatefulWidget {
  const UnnamedFacesRow({
    required this.count,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final int count;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<UnnamedFacesRow> createState() => _UnnamedFacesRowState();
}

class _UnnamedFacesRowState extends State<UnnamedFacesRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? PabloColors.selectionBackground
        : _hover
            ? PabloColors.backgroundSidebarHover
            : Colors.transparent;
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
              SizedBox(
                width: 14 + 3 * 11.0,
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Positioned(
                        left: i * 11.0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                HSLColor.fromAHSL(
                                  1,
                                  [15, 200, 340, 30][i].toDouble(),
                                  0.36,
                                  0.72,
                                ).toColor(),
                                HSLColor.fromAHSL(
                                  1,
                                  ([15, 200, 340, 30][i] + 15).toDouble(),
                                  0.42,
                                  0.56,
                                ).toColor(),
                              ],
                            ),
                            border: Border.all(
                              color: PabloColors.backgroundSidebar,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  'Unnamed Faces',
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              PabloBadge.count('${widget.count}'),
            ],
          ),
        ),
      ),
    );
  }
}
