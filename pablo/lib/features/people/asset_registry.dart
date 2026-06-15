// AssetRegistry — maps a native assetId to its file path + (header-parsed)
// source dimensions.
//
// Populated by the ingestion run (one register() per scanned file) and read by
// FaceThumb to (a) resolve the asset's pixels for a thumbnail request and
// (b) normalize source-pixel face boxes against the real image size. Kept out
// of PeopleController so the controller stays a pure reactive face-data facade
// (no file I/O, no render-side caches).

import '../../utils/image_dims.dart';

class AssetRegistry {
  final Map<int, String> _paths = {};
  final Map<int, ImageDims> _dims = {};

  /// Record an asset's path and parse its dimensions from the file header.
  void register(int assetId, String path) {
    _paths[assetId] = path;
    final dims = readImageDimensions(path);
    if (dims != null) _dims[assetId] = dims;
  }

  String? path(int assetId) => _paths[assetId];

  ImageDims? dims(int assetId) => _dims[assetId];
}
