// SaveSearchDialog — a small themed dialog to name a saved search, extracted
// from advanced_search_modal.dart.

import 'package:flutter/material.dart';

import '../../../components/pablo_button.dart';
import '../../../components/pablo_text_field.dart';
import '../../../theme/tokens.dart';

/// A small themed dialog to name a saved search.
class SaveSearchDialog extends StatelessWidget {
  const SaveSearchDialog({required this.controller, super.key});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    void submit() => Navigator.of(context).pop(controller.text);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(PabloSpacing.xxxl),
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurface,
            borderRadius: PabloRadius.panelAll,
            boxShadow: PabloShadows.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save Search',
                style: PabloTypography.serif(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: PabloSpacing.lg),
              PabloTextField(
                controller: controller,
                placeholder: 'Name this search…',
                autoFocus: true,
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: PabloSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PabloButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: PabloSpacing.lg),
                  PabloButton(
                    label: 'Save',
                    variant: PabloButtonVariant.primary,
                    onPressed: submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
