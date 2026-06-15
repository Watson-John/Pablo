// face_repository.dart — the People UI's data source.
//
// A thin seam between the existing People widgets (people_scroll_view,
// unnamed_faces_page, info_panel/people_tab) and the native face pipeline.
// Two implementations:
//   * [MockFaceRepository] — returns the M0 mockup rows (kPeople / kUnnamedFaces)
//     so the UI looks identical when the native backend is off.
//   * [NativeFaceRepository] — maps photo_core's read-back rows (FacePerson /
//     FaceRow) onto the UI models and forwards confirm/reject/scan/name to the
//     engine.
//
// Widgets stay unchanged: swap `kPeople` for `repo.people()` and
// `kUnnamedFaces` for `repo.unnamedFaces()` where the repo is read from
// AppScope. [createFaceRepository] picks the implementation by what's wired.

import 'dart:async';

import 'package:photo_native/photo_native.dart';

import 'mock_data.dart';
import 'models.dart';

abstract interface class FaceRepository {
  /// Confirmed/named people, as UI [Person] rows.
  List<Person> people();

  /// Unconfirmed cluster buckets, as UI [UnnamedFace] rows.
  List<UnnamedFace> unnamedFaces();

  /// Native face rows in a cluster (highest quality first). Empty in mock mode.
  List<FaceRow> facesInCluster(int clusterId);

  /// Suggested (unconfirmed) faces for a person — the confirm queue.
  List<FaceRow> suggestions(int personId);

  /// Faces detected in one asset (info-panel People tab).
  List<FaceRow> facesForAsset(int assetId);

  /// Confirm a face into a cluster/person. Returns a request id (0 in mock).
  int approve({required int clusterId, required int faceId});

  /// Reject a face's suggested membership. Returns a request id (0 in mock).
  int reject({required int clusterId, required int faceId});

  /// Schedule a face scan for an asset by path. Returns a request id.
  int scan({required int assetId, required String path});

  /// Name (or rename) a person. Returns a photo_status_t (0 == OK).
  int namePerson(int personId, String name);

  /// Fires when the clustering changes (scan completed / approve / reject /
  /// rebuild), so the UI can re-query. Never fires in mock mode.
  Stream<void> get changes;

  /// True when backed by the live native pipeline.
  bool get isLive;
}

/// Picks the live repository when an engine is available, else the mockup.
FaceRepository createFaceRepository({Engine? engine, Stream<PhotoEvent>? events}) {
  if (engine == null) return const MockFaceRepository();
  return NativeFaceRepository(engine, events);
}

// ---------------------------------------------------------------------------
// Mock — preserves the M0 look when the native backend is off.
// ---------------------------------------------------------------------------

class MockFaceRepository implements FaceRepository {
  const MockFaceRepository();

  @override
  bool get isLive => false;

  @override
  List<Person> people() => kPeople;

  @override
  List<UnnamedFace> unnamedFaces() => kUnnamedFaces;

  @override
  List<FaceRow> facesInCluster(int clusterId) => const [];

  @override
  List<FaceRow> suggestions(int personId) => const [];

  @override
  List<FaceRow> facesForAsset(int assetId) => const [];

  @override
  int approve({required int clusterId, required int faceId}) => 0;

  @override
  int reject({required int clusterId, required int faceId}) => 0;

  @override
  int scan({required int assetId, required String path}) => 0;

  @override
  int namePerson(int personId, String name) => 0;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

// ---------------------------------------------------------------------------
// Native — maps photo_core read-back rows onto the UI models.
// ---------------------------------------------------------------------------

class NativeFaceRepository implements FaceRepository {
  NativeFaceRepository(this._engine, Stream<PhotoEvent>? events) {
    if (events != null) {
      _sub = events
          .where((e) =>
              e.kind == PhotoEventKind.clusterUpdated ||
              e.kind == PhotoEventKind.scanProgress)
          .listen((_) => _changes.add(null));
    }
  }

  final Engine _engine;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<PhotoEvent>? _sub;

  @override
  bool get isLive => true;

  @override
  List<Person> people() => [
        for (final p in _engine.listPeople())
          Person(
            id: 'np${p.personId}',
            name: p.name.isEmpty ? 'Unnamed' : p.name,
            count: p.confirmedCount > 0 ? p.confirmedCount : p.faceCount,
            lastDate: '',
            hue: _hue(p.personId),
            confirmed: p.confirmed,
          ),
      ];

  @override
  List<UnnamedFace> unnamedFaces() => [
        for (final c in _engine.listClusters())
          UnnamedFace(
            id: 'nc${c.clusterId}',
            hue: _hue(c.clusterId),
            count: c.faceCount,
          ),
      ];

  @override
  List<FaceRow> facesInCluster(int clusterId) =>
      _engine.listClusterFaces(clusterId);

  @override
  List<FaceRow> suggestions(int personId) => _engine.listSuggestions(personId);

  @override
  List<FaceRow> facesForAsset(int assetId) =>
      _engine.listFacesForAsset(assetId);

  @override
  int approve({required int clusterId, required int faceId}) =>
      _engine.approveFace(clusterId: clusterId, embeddingId: faceId);

  @override
  int reject({required int clusterId, required int faceId}) =>
      _engine.rejectFace(clusterId: clusterId, embeddingId: faceId);

  @override
  int scan({required int assetId, required String path}) =>
      _engine.scanFacePath(assetId: assetId, path: path);

  @override
  int namePerson(int personId, String name) =>
      _engine.namePerson(personId, name);

  @override
  Stream<void> get changes => _changes.stream;

  void dispose() {
    _sub?.cancel();
    _changes.close();
  }

  // Stable hue from an id so avatars get a consistent color without a stored
  // palette (the mock rows carry an explicit hue; native rows derive one).
  static int _hue(int id) => (id * 47) % 360;
}
