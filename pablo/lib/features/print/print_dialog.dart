// print_dialog.dart — pick a print layout before opening the OS print dialog.
// Small themed chooser following set_location_dialog.dart's shape; returns the
// chosen PrintLayout or null on cancel.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../theme/tokens.dart';
import 'print_layouts.dart';

/// Show the layout picker for [count] photos. Returns the chosen layout or null.
Future<PrintLayout?> showPrintDialog(
  BuildContext context, {
  required int count,
}) {
  return showDialog<PrintLayout>(
    context: context,
    builder: (_) => _PrintDialog(count: count),
  );
}

class _PrintDialog extends StatefulWidget {
  const _PrintDialog({required this.count});
  final int count;

  @override
  State<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends State<_PrintDialog> {
  PrintLayout _layout = PrintLayout.full;

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                n == 1 ? 'Print photo' : 'Print $n photos',
                style: PabloTypography.sans(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Choose a layout, then the system print dialog opens.',
                style: PabloTypography.sans(
                    fontSize: 12, color: PabloColors.textMuted),
              ),
              const SizedBox(height: PabloSpacing.lg),
              for (final l in PrintLayout.values) _option(l),
              const SizedBox(height: PabloSpacing.xl),
              Row(
                children: [
                  const Spacer(),
                  PabloButton(
                    label: 'Cancel',
                    variant: PabloButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  PabloButton(
                    label: 'Print…',
                    onPressed: () => Navigator.of(context).pop(_layout),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(PrintLayout l) {
    final selected = _layout == l;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _layout = l),
        child: Container(
          margin: const EdgeInsets.only(bottom: PabloSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.lg,
            vertical: PabloSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? PabloColors.selectionBackground
                : PabloColors.backgroundSurface,
            border: Border.all(
              color: selected
                  ? PabloColors.selectionPrimary
                  : PabloColors.borderSubtle,
            ),
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              Text('○ ', style: PabloTypography.sans(fontSize: 12)),
              Expanded(
                child: Text(l.label,
                    style: PabloTypography.sans(fontSize: 12.5)),
              ),
              if (selected)
                const Text('✓',
                    style: TextStyle(
                        color: PabloColors.selectionPrimary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
