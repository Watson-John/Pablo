// set_location_dialog.dart — manually geotag one or more photos (Picasa parity
// §8 "manual geotag / drag onto map"). Shows the world map in "placing" mode:
// click to drop a pin, or type coordinates directly. Saving writes the override
// via [Engine.setGeo]; Clear removes it (falling back to EXIF GPS).

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Engine;

import '../../components/pablo_button.dart';
import '../../components/pablo_text_field.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'reverse_geocode.dart';
import 'world_map.dart';

/// Opens the dialog for [assetIds]. Returns true if the location changed.
Future<bool> showSetLocationDialog(
  BuildContext context, {
  required Engine engine,
  required List<int> assetIds,
  double? initialLat,
  double? initialLon,
}) async {
  if (assetIds.isEmpty) return false;
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _SetLocationDialog(
      engine: engine,
      assetIds: assetIds,
      initialLat: initialLat,
      initialLon: initialLon,
    ),
  );
  if (changed == true) libraryRevision.value++;
  return changed ?? false;
}

class _SetLocationDialog extends StatefulWidget {
  const _SetLocationDialog({
    required this.engine,
    required this.assetIds,
    this.initialLat,
    this.initialLon,
  });

  final Engine engine;
  final List<int> assetIds;
  final double? initialLat;
  final double? initialLon;

  @override
  State<_SetLocationDialog> createState() => _SetLocationDialogState();
}

class _SetLocationDialogState extends State<_SetLocationDialog> {
  double? _lat;
  double? _lon;
  final _latCtl = TextEditingController();
  final _lonCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lon = widget.initialLon;
    if (_lat != null) _latCtl.text = _lat!.toStringAsFixed(5);
    if (_lon != null) _lonCtl.text = _lon!.toStringAsFixed(5);
  }

  @override
  void dispose() {
    _latCtl.dispose();
    _lonCtl.dispose();
    super.dispose();
  }

  void _place(double lat, double lon) {
    setState(() {
      _lat = lat;
      _lon = lon;
      _latCtl.text = lat.toStringAsFixed(5);
      _lonCtl.text = lon.toStringAsFixed(5);
    });
  }

  void _onFieldEdited() {
    final la = double.tryParse(_latCtl.text.trim());
    final lo = double.tryParse(_lonCtl.text.trim());
    setState(() {
      _lat = (la != null && la >= -90 && la <= 90) ? la : null;
      _lon = (lo != null && lo >= -180 && lo <= 180) ? lo : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final has = _lat != null && _lon != null;
    final place = has ? reverseGeocode(_lat!, _lon!) : null;
    final marker = has
        ? [
            MapLocation(
              id: 'pin',
              name: 'Pin',
              cx: 0,
              cy: 0,
              count: 1,
              lat: _lat!,
              lon: _lon!,
            )
          ]
        : <MapLocation>[];
    final n = widget.assetIds.length;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(PabloSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(n == 1 ? 'Set location' : 'Set location · $n photos',
                  style: PabloTypography.sans(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('Click the map to drop a pin, or type coordinates.',
                  style: PabloTypography.sans(
                      fontSize: 12, color: PabloColors.textMuted)),
              const SizedBox(height: PabloSpacing.lg),
              SizedBox(
                height: 300,
                child: ClipRRect(
                  borderRadius: PabloRadius.mdAll,
                  child: WorldHeatMap(
                    locations: marker,
                    selectedId: has ? 'pin' : null,
                    onSelect: (_) {},
                    placing: true,
                    onPlace: _place,
                  ),
                ),
              ),
              const SizedBox(height: PabloSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: PabloTextField(
                      controller: _latCtl,
                      placeholder: 'Latitude',
                      onChanged: (_) => _onFieldEdited(),
                    ),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  Expanded(
                    child: PabloTextField(
                      controller: _lonCtl,
                      placeholder: 'Longitude',
                      onChanged: (_) => _onFieldEdited(),
                    ),
                  ),
                ],
              ),
              if (place != null) ...[
                const SizedBox(height: PabloSpacing.base),
                Text(
                  place.label,
                  style: PabloTypography.sans(
                      fontSize: 12, color: PabloColors.textSecondary),
                ),
              ],
              const SizedBox(height: PabloSpacing.lg),
              Row(
                children: [
                  PabloButton(
                    label: 'Clear',
                    variant: PabloButtonVariant.ghost,
                    onPressed: _clear,
                  ),
                  const Spacer(),
                  PabloButton(
                    label: 'Cancel',
                    variant: PabloButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: PabloSpacing.base),
                  PabloButton(
                    label: 'Save',
                    onPressed: has ? _save : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    for (final id in widget.assetIds) {
      widget.engine.setGeo(id, _lat!, _lon!);
    }
    Navigator.of(context).pop(true);
  }

  void _clear() {
    for (final id in widget.assetIds) {
      widget.engine.clearGeo(id);
    }
    Navigator.of(context).pop(true);
  }
}
