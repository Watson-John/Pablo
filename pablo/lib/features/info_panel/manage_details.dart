// Inspector "Manage details" form — the editable view behind the Info tab's
// Manage-details card (Pablo v4). In-memory only; Save just returns.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_text_field.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';

class ManageDetails extends StatefulWidget {
  const ManageDetails({
    required this.photo,
    required this.onSave,
    required this.onCancel,
    super.key,
  });
  final Photo photo;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  State<ManageDetails> createState() => _ManageDetailsState();
}

class _ManageDetailsState extends State<ManageDetails> {
  late final List<MapEntry<String, TextEditingController>> _fields;

  @override
  void initState() {
    super.initState();
    final e = getPhotoExif(widget.photo.id);
    _fields = [
      MapEntry('File name', TextEditingController(text: widget.photo.label)),
      MapEntry('Camera', TextEditingController(text: e.camera ?? '')),
      MapEntry('Lens', TextEditingController(text: e.lens ?? '')),
      MapEntry('Aperture', TextEditingController(text: e.aperture ?? '')),
      MapEntry('Shutter', TextEditingController(text: e.shutter ?? '')),
      MapEntry('ISO', TextEditingController(text: e.iso != null ? '${e.iso}' : '')),
      MapEntry('Focal length', TextEditingController(text: e.focalLength ?? '')),
      MapEntry('Date', TextEditingController(text: e.dateLabel ?? '')),
      MapEntry('Location', TextEditingController(text: e.location ?? '')),
    ];
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: PabloSpacing.lg),
        for (final f in _fields)
          Padding(
            padding: const EdgeInsets.only(bottom: PabloSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.key.toUpperCase(),
                  style: PabloTypography.sans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: PabloColors.textMuted,
                    letterSpacing: 0.05 * 10,
                  ),
                ),
                const SizedBox(height: PabloSpacing.sm),
                PabloTextField(controller: f.value),
              ],
            ),
          ),
        const SizedBox(height: PabloSpacing.sm),
        Row(
          children: [
            Expanded(
              child: PabloButton(
                label: 'Save Changes',
                variant: PabloButtonVariant.primary,
                onPressed: widget.onSave,
                expand: true,
              ),
            ),
            const SizedBox(width: PabloSpacing.base),
            PabloButton(
              label: 'Cancel',
              variant: PabloButtonVariant.ghost,
              onPressed: widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
}
