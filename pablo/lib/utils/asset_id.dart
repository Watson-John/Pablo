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

/// Install the catalog's stable path → asset_id mapping (called once after the
/// native import completes). Replaces any prior mapping.
void hydrateCatalogIds(Map<String, int> idByPath) {
  _catalogIds = idByPath;
}

int assetIdFor(String key) =>
    _catalogIds[key] ?? (key.hashCode & 0x7FFFFFFFFFFFFFFF);
