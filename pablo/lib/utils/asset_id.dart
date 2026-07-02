// asset_id.dart — the single source of truth for deriving a native asset id
// from a photo's stable identity.
//
// The face pipeline links faces to photos by asset id, and the thumbnail
// pipeline requests pixels by asset id. Those must agree, so the gallery
// (PhotoThumb), the ingestion scan (FaceIngestion), and the info-panel People
// tab all route through this one helper instead of hashing inline. In dataset
// mode a photo's id == its file path, so hashing either is equivalent.
//
// Once the catalog is imported, [hydrateCatalogIds] installs the stable,
// engine-assigned asset id for each path; [assetIdFor] then returns that id so
// face data and the thumbnail cache stay valid across restarts. Before
// hydration (or for a path not in the catalog) it falls back to a hash of the
// path — usable within a single run but not stable across runs.
//
// Clears the top bit (rather than `.abs()`) so the fallback is always a
// non-negative int — Dart's hashCode can be negative, and `.abs()` of the most
// negative value stays negative.

Map<String, int> _catalogIds = const {};
Map<int, String> _catalogPaths = const {};

/// Install the catalog's stable path → asset_id mapping (called once after the
/// native import completes). Replaces any prior mapping; also builds the
/// inverse (asset_id → path) used to resolve a catalog asset back to a photo.
/// Copies into growable maps so [remapCatalogPath] can update them in place.
void hydrateCatalogIds(Map<String, int> idByPath) {
  _catalogIds = Map.of(idByPath);
  _catalogPaths = {for (final e in idByPath.entries) e.value: e.key};
}

int assetIdFor(String key) =>
    _catalogIds[key] ?? (key.hashCode & 0x7FFFFFFFFFFFFFFF);

/// Path for a stable catalog asset_id, or null if unknown (e.g. pre-hydration).
String? pathForAssetId(int assetId) => _catalogPaths[assetId];

/// The hydrated catalog id for [path], or null when the path is unknown or
/// hydration hasn't happened yet. Unlike [assetIdFor] this never falls back to
/// the per-run path hash — use it wherever the id crosses the FFI as a real
/// catalog id (e.g. Engine.relocateAssets), where a hash would corrupt rows.
int? catalogIdForPath(String path) => _catalogIds[path];

/// Point an asset's in-memory mapping at its new path after a file move (the
/// catalog row was already relocated natively). No-op when [oldPath] was never
/// hydrated.
void remapCatalogPath(String oldPath, String newPath) {
  final id = _catalogIds[oldPath];
  if (id == null) return;
  _catalogIds.remove(oldPath);
  _catalogIds[newPath] = id;
  _catalogPaths[id] = newPath;
}
