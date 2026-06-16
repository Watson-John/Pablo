import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../theme/tokens.dart';

class EditorTool {
  const EditorTool({required this.id, required this.label, required this.icon});
  final String id;
  final String label;
  final PabloIconName icon;
}

const List<EditorTool> kEditorTools = [
  EditorTool(id: 'crop', label: 'Crop', icon: PabloIconName.crop),
  EditorTool(
      id: 'straighten', label: 'Straighten', icon: PabloIconName.straighten),
  EditorTool(id: 'rotateL', label: 'Rotate L', icon: PabloIconName.rotateLeft),
  EditorTool(id: 'rotateR', label: 'Rotate R', icon: PabloIconName.rotateRight),
  EditorTool(id: 'flipH', label: 'Flip H', icon: PabloIconName.flipHorizontal),
  EditorTool(id: 'flipV', label: 'Flip V', icon: PabloIconName.flipVertical),
  EditorTool(id: 'heal', label: 'Heal', icon: PabloIconName.heal),
  EditorTool(id: 'redeye', label: 'Red Eye', icon: PabloIconName.redEye),
];

class ToolsGrid extends StatelessWidget {
  const ToolsGrid(
      {required this.activeTool, required this.onChange, super.key});
  final String? activeTool;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: PabloSpacing.md,
      mainAxisSpacing: PabloSpacing.md,
      childAspectRatio: 1.0,
      children: kEditorTools.map((t) {
        final sel = activeTool == t.id;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChange(sel ? null : t.id),
            child: AnimatedContainer(
              duration: PabloDurations.control,
              decoration: BoxDecoration(
                color: sel
                    ? PabloColors.accentBackground
                    : PabloColors.backgroundSurfaceAlt,
                border: Border.all(
                  color: sel
                      ? PabloColors.accentPrimary
                      : PabloColors.borderStrong,
                ),
                borderRadius: PabloRadius.mdAll,
                boxShadow: sel ? null : PabloShadows.sm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PabloIcon(
                    t.icon,
                    size: 18,
                    color: sel
                        ? PabloColors.accentPrimary
                        : PabloColors.textSecondary,
                  ),
                  const SizedBox(height: PabloSpacing.sm + 1),
                  Text(
                    t.label,
                    style: PabloTypography.sans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      color: sel
                          ? PabloColors.accentPrimary
                          : PabloColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
