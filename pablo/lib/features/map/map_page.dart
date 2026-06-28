// MapPage — heat-map view of photo locations + location-photo grid below.
// Pablo v4: the map auto-collapses (fades + slides away) once the photo grid
// scrolls past a small threshold, and re-reveals near the top / on a new pick.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show GeoPoint;

import '../../backend/native_backend.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import 'location_photo_grid.dart';
import 'map_data.dart';
import 'usa_heat_map.dart';

const double _kMapHeight = 300;

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  String? _selectedId;
  bool _showMap = true;
  bool _mapCollapsed = false;
  final ScrollController _scrollCtl = ScrollController();

  // Markers + per-marker asset ids, built from the catalog's geotagged assets.
  MapData _data = MapData.empty;

  @override
  void initState() {
    super.initState();
    _scrollCtl.addListener(_onScroll);
    // Rebuild when the library (and its catalog metadata) becomes ready.
    libraryRevision.addListener(_reload);
  }

  @override
  void dispose() {
    libraryRevision.removeListener(_reload);
    _scrollCtl.removeListener(_onScroll);
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() {
    final backend = NativeBackendScope.maybeOf(context);
    final pts = backend?.engine.listGeotagged() ?? const <GeoPoint>[];
    final data = buildMapData(pts);
    if (mounted) setState(() => _data = data);
  }

  // Binary collapse with a hysteresis band so the transition fires once, not
  // every frame.
  void _onScroll() {
    if (!_scrollCtl.hasClients) return;
    final y = _scrollCtl.offset;
    if (y > 56 && !_mapCollapsed) {
      setState(() => _mapCollapsed = true);
    } else if (y < 16 && _mapCollapsed) {
      setState(() => _mapCollapsed = false);
    }
  }

  void _select(String id) {
    setState(() {
      _selectedId = _selectedId == id ? null : id;
      _mapCollapsed = false;
    });
    // Jump the (rebuilt) grid back to the top after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtl.hasClients) _scrollCtl.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locations = _data.locations;
    MapLocation? selected;
    if (_selectedId != null) {
      for (final l in locations) {
        if (l.id == _selectedId) {
          selected = l;
          break;
        }
      }
    }
    // Resolve the selected marker's catalog asset ids back to library photos.
    final photos = <Photo>[];
    if (selected != null) {
      for (final assetId in _data.assetIdsByLocation[selected.id] ?? const []) {
        final path = pathForAssetId(assetId);
        final photo = path == null ? null : Library.instance.byId[path];
        if (photo != null) photos.add(photo);
      }
    }
    final totalPhotos = locations.fold<int>(0, (a, b) => a + b.count);

    return Container(
      color: PabloColors.backgroundSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Page header
          Container(
            height: 42,
            padding:
                const EdgeInsets.symmetric(horizontal: PabloSpacing.xl + 2),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
            ),
            child: Row(
              children: [
                const PabloIcon(
                  PabloIconName.map,
                  size: 15,
                  color: PabloColors.textMuted,
                ),
                const SizedBox(width: PabloSpacing.base),
                Text(
                  'Photo Map',
                  style: PabloTypography.serif(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: PabloSpacing.base),
                Text(
                  '$totalPhotos photos · ${locations.length} locations',
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
          // Collapsible map — binary open/hidden; fades + slides away on scroll.
          if (_showMap)
            AnimatedContainer(
              duration: PabloDurations.slow,
              curve: PabloEasing.standard,
              height: _mapCollapsed ? 0 : _kMapHeight,
              transform:
                  Matrix4.translationValues(0, _mapCollapsed ? -12 : 0, 0),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: PabloColors.mapOcean,
                border: Border(
                  bottom: BorderSide(
                    color: _mapCollapsed
                        ? Colors.transparent
                        : PabloColors.borderSubtle,
                  ),
                ),
              ),
              child: AnimatedOpacity(
                duration: PabloDurations.base,
                opacity: _mapCollapsed ? 0 : 1,
                child: IgnorePointer(
                  ignoring: _mapCollapsed,
                  child: USAHeatMap(
                    locations: locations,
                    selectedId: _selectedId,
                    onSelect: _select,
                  ),
                ),
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
                              size: 15,
                              color: PabloColors.accentPrimary,
                            ),
                            const SizedBox(width: PabloSpacing.base),
                            Text(
                              selected.name,
                              style: PabloTypography.serif(
                                fontSize: 15,
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
                          controller: _scrollCtl,
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
                          'No geotagged photos in this library.\nThe Flickr30k set carries no GPS metadata.',
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
