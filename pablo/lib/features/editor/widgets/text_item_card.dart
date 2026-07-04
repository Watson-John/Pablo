// Per-text-overlay editor card for the edit panel's Text section — extracted
// from photo_edit_panel.dart.

import 'package:flutter/material.dart';

import '../../../components/pablo_icon.dart';
import '../../../components/pablo_slider.dart';
import '../edit_spec.dart';
import '../../../theme/tokens.dart';

/// Per-text-overlay editor: content + size + colour + position + delete.
class TextItemCard extends StatefulWidget {
  const TextItemCard({
    required this.item,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final TextOverlay item;
  final void Function(void Function(TextOverlay)) onChanged;
  final VoidCallback onDelete;

  @override
  State<TextItemCard> createState() => _TextItemCardState();
}

class _TextItemCardState extends State<TextItemCard> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.item.text);

  static const List<int> _swatches = [
    0xFFFFFF, 0x000000, 0xC0392B, 0xF1C40F, 0x2563EB, 0x27AE60,
  ];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item;
    return Container(
      margin: const EdgeInsets.only(bottom: PabloSpacing.base),
      padding: const EdgeInsets.all(PabloSpacing.lg),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderStrong),
        borderRadius: PabloRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctl,
                  onChanged: (v) => widget.onChanged((x) => x.text = v),
                  style: PabloTypography.sans(fontSize: 12.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Text…',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: PabloSpacing.base,
                        vertical: PabloSpacing.sm),
                    border: OutlineInputBorder(borderRadius: PabloRadius.smAll),
                  ),
                ),
              ),
              const SizedBox(width: PabloSpacing.sm),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: const PabloIcon(PabloIconName.trash,
                      size: 15, color: PabloColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: PabloSpacing.sm),
          Row(
            children: [
              for (final c in _swatches)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => widget.onChanged((x) => x.color = c),
                    child: Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.only(right: PabloSpacing.sm),
                      decoration: BoxDecoration(
                        color: Color.fromARGB(
                            255, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: t.color == c
                              ? PabloColors.accentPrimary
                              : PabloColors.borderStrong,
                          width: t.color == c ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          EditSlider(
            label: 'Size',
            value: t.size * 100,
            min: 2,
            max: 40,
            onChanged: (v) => widget.onChanged((x) => x.size = v / 100),
          ),
          EditSlider(
            label: 'X',
            value: t.x * 100,
            min: 0,
            max: 100,
            onChanged: (v) => widget.onChanged((x) => x.x = v / 100),
          ),
          EditSlider(
            label: 'Y',
            value: t.y * 100,
            min: 0,
            max: 100,
            onChanged: (v) => widget.onChanged((x) => x.y = v / 100),
          ),
        ],
      ),
    );
  }
}
