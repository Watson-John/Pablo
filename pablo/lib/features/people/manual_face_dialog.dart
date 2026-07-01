// manual_face_dialog.dart — draw a face rectangle by hand on a photo, then name
// it (Picasa parity §7 "Manual face rectangle add / adjust"). The user drags a
// box over the contained image; on save the box is converted to source-image
// pixels and stored via [PeopleController.addManualFace], then (optionally)
// assigned to a named person.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_text_field.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../gallery/photo_surface.dart';
import 'people_controller.dart';

/// Opens the dialog. Returns true if a face was added.
Future<bool> showManualFaceDialog(
  BuildContext context, {
  required Photo photo,
  required int assetId,
  required int imgW,
  required int imgH,
  required PeopleController controller,
}) async {
  final added = await showDialog<bool>(
    context: context,
    builder: (_) => _ManualFaceDialog(
      photo: photo,
      assetId: assetId,
      imgW: imgW,
      imgH: imgH,
      controller: controller,
    ),
  );
  return added ?? false;
}

class _ManualFaceDialog extends StatefulWidget {
  const _ManualFaceDialog({
    required this.photo,
    required this.assetId,
    required this.imgW,
    required this.imgH,
    required this.controller,
  });

  final Photo photo;
  final int assetId;
  final int imgW;
  final int imgH;
  final PeopleController controller;

  @override
  State<_ManualFaceDialog> createState() => _ManualFaceDialogState();
}

class _ManualFaceDialogState extends State<_ManualFaceDialog> {
  // Rubber-band rect in NORMALIZED image coordinates (0..1), so conversion to
  // source pixels never depends on the display size.
  Rect? _rect;
  Offset? _start;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.imgW > 0 && widget.imgH > 0;
    final aspect = known ? widget.imgW / widget.imgH : 4 / 3;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add a face',
                  style: PabloTypography.sans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Drag a box over a face, then name them.',
                  style: PabloTypography.sans(
                      fontSize: 12, color: PabloColors.textMuted)),
              const SizedBox(height: PabloSpacing.lg),
              Flexible(
                child: LayoutBuilder(builder: (context, c) {
                  var dW = c.maxWidth;
                  var dH = dW / aspect;
                  final maxH = c.maxHeight.isFinite ? c.maxHeight : 400.0;
                  if (dH > maxH) {
                    dH = maxH;
                    dW = dH * aspect;
                  }
                  Offset norm(Offset p) => Offset(
                        (p.dx / dW).clamp(0.0, 1.0),
                        (p.dy / dH).clamp(0.0, 1.0),
                      );
                  final dispRect = _rect == null
                      ? null
                      : Rect.fromLTWH(_rect!.left * dW, _rect!.top * dH,
                          _rect!.width * dW, _rect!.height * dH);
                  return Center(
                    child: SizedBox(
                      width: dW,
                      height: dH,
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          _start = norm(d.localPosition);
                          _rect = null;
                        }),
                        onPanUpdate: (d) => setState(() {
                          _rect = Rect.fromPoints(_start!, norm(d.localPosition));
                        }),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: PabloRadius.smAll,
                              child: PhotoSurface(
                                photo: widget.photo,
                                targetW: 1024,
                                targetH: 1024,
                              ),
                            ),
                            if (dispRect != null)
                              Positioned.fromRect(
                                rect: dispRect,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: PabloColors.selectionPrimary,
                                        width: 2),
                                    color: PabloColors.selectionPrimary
                                        .withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: PabloSpacing.lg),
              PabloTextField(
                controller: _name,
                placeholder: 'Name (optional)',
              ),
              const SizedBox(height: PabloSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PabloButton(
                    label: 'Cancel',
                    variant: PabloButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  PabloButton(
                    label: 'Add face',
                    onPressed: _canSave ? _save : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave =>
      _rect != null && _rect!.width > 0.02 && _rect!.height > 0.02;

  void _save() {
    // _rect is normalized (0..1); scale straight to source-image pixels.
    final r = _rect!;
    final sx = r.left * widget.imgW;
    final sy = r.top * widget.imgH;
    final sw = r.width * widget.imgW;
    final sh = r.height * widget.imgH;

    final faceId = widget.controller
        .addManualFace(widget.assetId, x: sx, y: sy, w: sw, h: sh);
    if (faceId != 0) {
      final name = _name.text.trim();
      if (name.isNotEmpty) widget.controller.assignFace(faceId, name);
    }
    if (mounted) Navigator.of(context).pop(faceId != 0);
  }
}
