// ActivityIndicator — compact running-task pill with progress bar; popover
// listing all tasks when there are 2+.

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';

class ActivityIndicator extends StatefulWidget {
  const ActivityIndicator({required this.tasks, super.key});
  final List<TaskInfo> tasks;

  @override
  State<ActivityIndicator> createState() => _ActivityIndicatorState();
}

class _ActivityIndicatorState extends State<ActivityIndicator> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) return const SizedBox.shrink();
    final primary = widget.tasks.first;

    return MouseRegion(
      cursor: widget.tasks.length > 1
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.tasks.length > 1
            ? () => setState(() => _open = !_open)
            : null,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurface,
            border: Border.all(color: PabloColors.borderSubtle),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      primary.name,
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(
                        fontSize: 10,
                        color: PabloColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: (primary.percent / 100).clamp(0, 1),
                          backgroundColor: PabloColors.borderSubtle,
                          valueColor: const AlwaysStoppedAnimation(
                            PabloColors.accentPrimary,
                          ),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PabloSpacing.base),
              Text(
                '${primary.percent.round()}%',
                style: PabloTypography.mono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: PabloColors.accentPrimary,
                ),
              ),
              if (widget.tasks.length > 1) ...[
                const SizedBox(width: PabloSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PabloSpacing.sm + 1,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: PabloColors.accentPrimary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+${widget.tasks.length - 1}',
                    style: PabloTypography.sans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: PabloColors.textOnAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
