// MapPage — heat-map view of photo locations + location-photo grid below.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';
import 'location_photo_grid.dart';
import 'usa_heat_map.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  String? _selectedId;
  bool _showMap = true;

  Map<String, List<Photo>> get _photosByLocation => {
        for (var i = 0; i < kMapLocations.length; i++)
          kMapLocations[i].id: makePhotos(
              'map-${kMapLocations[i].id}',
              kMapLocations[i].count < 40 ? kMapLocations[i].count : 40,
              i * 11 + 4),
      };

  @override
  Widget build(BuildContext context) {
    final selected =
        _selectedId != null
            ? kMapLocations.firstWhere(
                (l) => l.id == _selectedId,
                orElse: () => kMapLocations.first,
              )
            : null;
    final photos = _selectedId != null
        ? _photosByLocation[_selectedId]!
        : <Photo>[];
    final totalPhotos = kMapLocations.fold<int>(0, (a, b) => a + b.count);

    return Container(
      color: PabloColors.backgroundSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl + 2),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const PabloIcon(
                  PabloIconName.map,
                  size: 15,
                  color: PabloColors.textMuted,
                ),
                const SizedBox(width: PabloSpacing.lg),
                Text(
                  'Photo Map',
                  style: PabloTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: PabloSpacing.lg),
                Text(
                  '$totalPhotos photos · ${kMapLocations.length} locations',
                  style: PabloTypography.caption,
                ),
                const Spacer(),
                PabloButton(
                  label: _showMap ? 'Hide Map' : 'Show Map',
                  variant: PabloButtonVariant.ghost,
                  icon: _showMap ? PabloIconName.panelRight : PabloIconName.map,
                  onPressed: () => setState(() => _showMap = !_showMap),
                ),
              ],
            ),
          ),
          // Map
          if (_showMap)
            Container(
              height: 300,
              decoration: const BoxDecoration(
                color: PabloColors.mapOcean,
                border: Border(
                  bottom: BorderSide(color: PabloColors.borderSubtle),
                ),
              ),
              child: USAHeatMap(
                selectedId: _selectedId,
                onSelect: (id) {
                  setState(() {
                    _selectedId = _selectedId == id ? null : id;
                  });
                },
              ),
            ),
          // Photos
          Expanded(
            child: selected != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PabloSpacing.xl + 2,
                          vertical: PabloSpacing.base,
                        ),
                        decoration: const BoxDecoration(
                          color: PabloColors.backgroundSurfaceAlt,
                          border: Border(
                            bottom: BorderSide(color: PabloColors.borderSubtle),
                          ),
                        ),
                        child: Row(
                          children: [
                            const PabloIcon(
                              PabloIconName.map,
                              size: 13,
                              color: PabloColors.accentPrimary,
                            ),
                            const SizedBox(width: PabloSpacing.base),
                            Text(
                              selected.name,
                              style: PabloTypography.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: PabloSpacing.lg),
                            Text(
                              '${selected.count} photos',
                              style: PabloTypography.caption,
                            ),
                            const Spacer(),
                            if (!_showMap)
                              PabloButton(
                                label: 'Show Map',
                                variant: PabloButtonVariant.ghost,
                                size: PabloButtonSize.xs,
                                icon: PabloIconName.map,
                                onPressed: () =>
                                    setState(() => _showMap = true),
                              ),
                            const SizedBox(width: PabloSpacing.sm),
                            PabloButton(
                              label: 'Clear',
                              variant: PabloButtonVariant.ghost,
                              size: PabloButtonSize.xs,
                              onPressed: () =>
                                  setState(() => _selectedId = null),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: LocationPhotoGrid(photos: photos),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: 0.35,
                          child: const PabloIcon(
                            PabloIconName.map,
                            size: 38,
                            color: PabloColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: PabloSpacing.xl),
                        Text(
                          _showMap
                              ? 'Click a location on the map\nto view photos from that area'
                              : 'Show the map and click a location\nto view photos',
                          textAlign: TextAlign.center,
                          style: PabloTypography.sans(
                            fontSize: 13,
                            color: PabloColors.textMuted,
                            height: 1.7,
                          ),
                        ),
                        if (!_showMap) ...[
                          const SizedBox(height: PabloSpacing.xl),
                          PabloButton(
                            label: 'Show Map',
                            icon: PabloIconName.map,
                            onPressed: () => setState(() => _showMap = true),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
