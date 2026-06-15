// PeopleController — the seam between the People UI and the face pipeline.
//
// A thin reactive wrapper over [FaceRepository]. It owns the repo, re-emits
// the repo's `changes` stream as ChangeNotifier notifications (so the People
// views re-query when clustering updates), and adds the helpers the widgets
// need: native-id parsing, a quality→confidence tier, a person→cluster lookup,
// and an assetId→path registry the ingestion run populates so [FaceThumb] can
// resolve pixels for a face row.
//
// Mock vs. live: in mock mode the repo returns the kPeople / kUnnamedFaces
// rows and `changes` never fires, so widgets keep their existing local-state
// behavior untouched. In live mode the repo is the source of truth and every
// `changes` event triggers a re-query — no local verdict state needed.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart';

import '../../data/models.dart';
import '../../data/sources/face_repository.dart';
import '../../utils/image_dims.dart';

/// Legacy mockup figure for the sidebar Unnamed Faces count — kept so the
/// default (mock) app is pixel-identical to before the integration.
const int kMockUnnamedCount = 247;

/// Quality cutoff separating high- vs low-confidence suggestions. The only
/// tunable knob on the UI side; affects the "N new" badge, not correctness.
const double kQualityHighCutoff = 0.6;

/// Confidence tier derived from a face's [FaceRow.quality].
enum FaceTier { high, low }

class PeopleController extends ChangeNotifier {
  PeopleController(this._repo, {Engine? engine}) : _engine = engine {
    _sub = _repo.changes.listen((_) => notifyListeners());
  }

  final FaceRepository _repo;

  /// Live engine, used only for the few raw queries the repo doesn't expose
  /// (mapping a person to its representative cluster). Null in mock mode.
  final Engine? _engine;

  StreamSubscription<void>? _sub;

  /// assetId → file path, populated by the ingestion run (see [FaceIngestion])
  /// so [FaceThumb] can request a thumbnail for a [FaceRow]'s asset.
  final Map<int, String> _assetPaths = {};

  /// assetId → source image dimensions. Face boxes are in source pixels
  /// ([FaceRow.boxX] etc.), so FaceThumb needs these to normalize the crop.
  final Map<int, ImageDims> _assetDims = {};

  bool get isLive => _repo.isLive;

  // ── People / clusters ────────────────────────────────────────────────────

  List<Person> people() => _repo.people();

  List<UnnamedFace> unnamedFaces() => _repo.unnamedFaces();

  /// Sidebar Unnamed Faces count. Live: sum of cluster sizes; mock: the legacy
  /// mockup figure.
  int unnamedFaceCount() => isLive
      ? unnamedFaces().fold<int>(0, (s, u) => s + u.count)
      : kMockUnnamedCount;

  /// Total shown on the collapsed People section header.
  int peopleTotal() =>
      people().fold<int>(0, (s, p) => s + p.count) + unnamedFaceCount();

  // ── Faces (live) ──────────────────────────────────────────────────────────

  List<FaceRow> suggestionsForPerson(int personId) =>
      _repo.suggestions(personId);

  int lowConfidenceCount(int personId) =>
      suggestionsForPerson(personId).where((f) => tierOf(f) == FaceTier.low).length;

  List<FaceRow> facesInCluster(int clusterId) => _repo.facesInCluster(clusterId);

  /// Highest-quality face of a cluster (drives the cluster card cover crop).
  FaceRow? coverFace(int clusterId) {
    final faces = facesInCluster(clusterId);
    return faces.isEmpty ? null : faces.first;
  }

  List<FaceRow> facesForAsset(int assetId) => _repo.facesForAsset(assetId);

  /// Display name for a confirmed person id, or null if not found/unnamed.
  String? personNameFor(int personId) {
    for (final p in people()) {
      if (nativePersonId(p.id) == personId) {
        return p.name == 'Unnamed' ? null : p.name;
      }
    }
    return null;
  }

  /// A person's confirmed faces, via the engine's person→cluster mapping.
  /// Empty in mock mode (no engine).
  List<FaceRow> confirmedFacesForPerson(int personId) {
    final engine = _engine;
    if (engine == null) return const [];
    int clusterId = -1;
    for (final fp in engine.listPeople()) {
      if (fp.personId == personId) {
        clusterId = fp.clusterId;
        break;
      }
    }
    if (clusterId < 0) return const [];
    return facesInCluster(clusterId).where((f) => f.confirmed).toList();
  }

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

  int scan({required int assetId, required String path}) {
    registerAsset(assetId, path);
    return _repo.scan(assetId: assetId, path: path);
  }

  /// Re-cluster all unconfirmed faces (full recompute on the idle lane).
  /// No-op without a live engine.
  int rebuildClusters() => _engine?.rebuildClusters() ?? 0;

  // ── Asset registry (populated by ingestion) ────────────────────────────────

  /// Records the path and (header-parsed) source dimensions for an asset so
  /// FaceThumb can resolve pixels and normalize source-pixel face boxes.
  void registerAsset(int assetId, String path) {
    _assetPaths[assetId] = path;
    final dims = readImageDimensions(path);
    if (dims != null) _assetDims[assetId] = dims;
  }

  String? assetPath(int assetId) => _assetPaths[assetId];

  ImageDims? assetDims(int assetId) => _assetDims[assetId];

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
