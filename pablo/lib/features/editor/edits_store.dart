// EditsStore — a tiny in-memory index of which assets have a saved edit and at
// what content_rev. Two jobs:
//   * drive the gallery "edited" badge (PhotoThumb), and
//   * force already-displayed tiles to repaint after a save — PhotoSurface
//     threads revOf(assetId) into the texture's content-rev, and the texture
//     rebinds + re-requests when it changes (the freshly-requested frame is the
//     edited one, since the native render applies the saved edit).
//
// Edited PIXELS render correctly without this store (the native engine applies
// edits during decode regardless); the store only handles the badge + the
// in-session refresh of tiles that are already on screen holding an old frame.

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

class EditsStore extends ChangeNotifier {
  EditsStore._();
  static final EditsStore instance = EditsStore._();

  final Map<int, int> _revs = {}; // assetId -> content_rev (edited assets only)

  bool isEdited(int assetId) => _revs.containsKey(assetId);
  int revOf(int assetId) => _revs[assetId] ?? 0;

  /// Hydrate from the engine at boot so the badge is correct on restart.
  void hydrate(Engine engine) {
    _revs.clear();
    for (final id in engine.editedAssetIds()) {
      _revs[id] = engine.assetContentRev(id);
    }
    notifyListeners();
  }

  /// Record a save (or, when [edited] is false, a clear-to-identity).
  void setRev(int assetId, int rev, {required bool edited}) {
    if (edited) {
      _revs[assetId] = rev;
    } else {
      _revs.remove(assetId);
    }
    notifyListeners();
  }

  /// Remove an asset's edit marker (revert).
  void clear(int assetId) {
    if (_revs.remove(assetId) != null) notifyListeners();
  }
}
