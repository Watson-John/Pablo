// pattern_lane_view.dart — one editable [PatternLane] as a drop target: drag a
// token from the palette to append it, remove a chip with its ×, or type fixed
// text into the inline "text" field. Shared by the folder-structure levels and
// the file-name lane so both behave identically.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import 'scheme_drag.dart';

class PatternLaneView extends StatelessWidget {
  const PatternLaneView({
    required this.lane,
    required this.onChanged,
    this.placeholder = 'Drag tokens here',
    super.key,
  });

  final PatternLane lane;
  final VoidCallback onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TokenType>(
      onAcceptWithDetails: (d) {
        lane.segments.add(TokenSegment(d.data));
        onChanged();
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: PabloDurations.fast,
          constraints: const BoxConstraints(minHeight: 44),
          width: double.infinity,
          padding: const EdgeInsets.all(PabloSpacing.base),
          decoration: BoxDecoration(
            color: hot
                ? PabloColors.accentBackground
                : PabloColors.backgroundSurfaceAlt,
            border: Border.all(
              color: hot ? PabloColors.accentPrimary : PabloColors.borderSubtle,
            ),
            borderRadius: PabloRadius.smAll,
          ),
          child: Wrap(
            spacing: PabloSpacing.sm,
            runSpacing: PabloSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < lane.segments.length; i++)
                _chipFor(lane.segments[i], i),
              if (lane.segments.isEmpty && !hot)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: PabloSpacing.sm, vertical: PabloSpacing.xs),
                  child: Text(placeholder, style: PabloTypography.caption),
                ),
              _LiteralAdd(onAdd: (text) {
                lane.segments.add(LiteralSegment(text));
                onChanged();
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _chipFor(Segment seg, int index) {
    void remove() {
      lane.segments.removeAt(index);
      onChanged();
    }

    if (seg is LiteralSegment) {
      return SchemeChip(label: '“${seg.text}”', onRemove: remove);
    }
    final spec = (seg as TokenSegment).spec;
    return SchemeChip(
      label: spec.label,
      icon: spec.icon,
      color: tokenGroupColor(spec.group),
      onRemove: remove,
    );
  }
}

/// A compact "＋ text" field that appends a literal segment on submit.
class _LiteralAdd extends StatefulWidget {
  const _LiteralAdd({required this.onAdd});
  final ValueChanged<String> onAdd;

  @override
  State<_LiteralAdd> createState() => _LiteralAddState();
}

class _LiteralAddState extends State<_LiteralAdd> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctl.text.trim();
    if (t.isNotEmpty) widget.onAdd(t);
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.sm),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.smAll,
      ),
      child: Row(
        children: [
          const PabloIcon(PabloIconName.plus,
              size: 12, color: PabloColors.textMuted),
          const SizedBox(width: PabloSpacing.xs),
          Expanded(
            child: TextField(
              controller: _ctl,
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) => _submit(),
              style: PabloTypography.sans(fontSize: 12),
              cursorColor: PabloColors.accentPrimary,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'text',
                hintStyle: PabloTypography.sans(
                    fontSize: 12, color: PabloColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
