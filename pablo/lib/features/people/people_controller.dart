// PeopleController — the seam between the People UI and the face pipeline.
//
// A thin reactive wrapper over [FaceRepository]. It owns the repo, re-emits
// the repo's `changes` stream as ChangeNotifier notifications (so the People
// views re-query when clustering updates), and adds the small view-side helpers
// the widgets need: native-id parsing and a quality→confidence tier. All face
// data and mutations go through the repo (the single seam); the ingestion-fed
// asset path/dims cache lives in a separate [AssetRegistry].
//
// Offline vs. live: in offline mode the repo returns empty lists and `changes`
// never fires, so People renders empty. In live mode the repo is the source of
// truth and every `changes` event triggers a re-query — no local verdict state.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../../data/models.dart';
import '../../data/sources/face_repository.dart';
import '../../utils/image_dims.dart';
import 'asset_registry.dart';

/// Quality cutoff separating high- vs low-confidence suggestions. The only
/// tunable knob on the UI side; affects the "N new" badge, not correctness.
const double kQualityHighCutoff = 0.6;

/// Confidence tier derived from a face's [FaceRow.quality].
enum FaceTier { high, low }

class PeopleController extends ChangeNotifier {
  PeopleController(this._repo) {
    _sub = _repo.changes.listen((_) => notifyListeners());
  }

  final FaceRepository _repo;
  StreamSubscription<void>? _sub;

  /// assetId → path/dims, populated by the ingestion run (see [FaceIngestion])
  /// and read by [FaceThumb]. Kept separate so the controller stays a pure
  /// reactive facade over face data.
  final AssetRegistry _assets = AssetRegistry();

  bool get isLive => _repo.isLive;

  // ── People / clusters ────────────────────────────────────────────────────

  List<Person> people() => _repo.people();

  List<UnnamedFace> unnamedFaces() => _repo.unnamedFaces();

  /// Sidebar Unnamed Faces count — the sum of unconfirmed cluster sizes (0
  /// until the live pipeline has scanned).
  int unnamedFaceCount() => unnamedFaces().fold<int>(0, (s, u) => s + u.count);

  /// Total shown on the collapsed People section header.
  int peopleTotal() =>
      people().fold<int>(0, (s, p) => s + p.count) + unnamedFaceCount();

  // ── Faces (live) ──────────────────────────────────────────────────────────

  List<FaceRow> suggestionsForPerson(int personId) =>
      _repo.suggestions(personId);

  int lowConfidenceCount(int personId) => suggestionsForPerson(personId)
      .where((f) => tierOf(f) == FaceTier.low)
      .length;

  List<FaceRow> facesInCluster(int clusterId) =>
      _repo.facesInCluster(clusterId);

  /// Highest-quality face of a cluster (drives the cluster card cover crop).
  FaceRow? coverFace(int clusterId) {
    final faces = facesInCluster(clusterId);
    return faces.isEmpty ? null : faces.first;
  }

  List<FaceRow> facesForAsset(int assetId) => _repo.facesForAsset(assetId);

  /// Display name for a confirmed person id, or null if not found/unnamed.
  String? personNameFor(int personId) => _repo.personName(personId);

  /// A person's confirmed faces. Empty in mock mode.
  List<FaceRow> confirmedFacesForPerson(int personId) =>
      _repo.confirmedFacesForPerson(personId);

  // ── Mutations (live; no-ops in mock since the repo returns 0) ──────────────

  void approve({required int clusterId, required int faceId}) =>
      _repo.approve(clusterId: clusterId, faceId: faceId);

  void reject({required int clusterId, required int faceId}) =>
      _repo.reject(clusterId: clusterId, faceId: faceId);

  /// Name (or rename) a person. Synchronous in the C-ABI and emits no event,
  /// so we notify immediately to refresh the People list.
  void namePerson(int personId, String name) {
    _repo.namePerson(personId, name);
    notifyListeners();
  }

  /// Promote an unconfirmed cluster into a named person (confirm-all + merge by
  /// name). Async in the engine; the resulting clusterUpdated event re-queries.
  void assignCluster(int clusterId, String name) =>
      _repo.nameCluster(clusterId, name);

  int scan({required int assetId, required String path}) {
    registerAsset(assetId, path);
    return _repo.scan(assetId: assetId, path: path);
  }

  /// Re-cluster all unconfirmed faces (full recompute on the idle lane).
  /// No-op (0) in mock mode.
  int rebuildClusters() => _repo.rebuildClusters();

  // ── Asset registry (populated by ingestion, read by FaceThumb) ─────────────

  void registerAsset(int assetId, String path) =>
      _assets.register(assetId, path);

  String? assetPath(int assetId) => _assets.path(assetId);

  ImageDims? assetDims(int assetId) => _assets.dims(assetId);

  // ── Helpers ────────────────────────────────────────────────────────────────

  FaceTier tierOf(FaceRow f) =>
      f.quality >= kQualityHighCutoff ? FaceTier.high : FaceTier.low;

  /// Native person id encoded in a live [Person.id] (`np<id>`); null for mock
  /// rows (e.g. 'p1').
  static int? nativePersonId(String uiId) =>
      uiId.startsWith('np') ? int.tryParse(uiId.substring(2)) : null;

  /// Native cluster id encoded in a live [UnnamedFace.id] (`nc<id>`).
  static int? nativeClusterId(String uiId) =>
      uiId.startsWith('nc') ? int.tryParse(uiId.substring(2)) : null;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
