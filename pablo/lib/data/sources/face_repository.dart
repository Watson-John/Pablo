// face_repository.dart — the People UI's data source.
//
// A thin seam between the existing People widgets (people_scroll_view,
// unnamed_faces_page, info_panel/people_tab) and the native face pipeline.
// Two implementations:
//   * [MockFaceRepository] — the offline repo: returns empty lists (the mock
//     library was removed), so People renders empty when no native backend is
//     mounted, until the live pipeline scans.
//   * [NativeFaceRepository] — maps photo_core's read-back rows (FacePerson /
//     FaceRow) onto the UI models and forwards confirm/reject/scan/name to the
//     engine.
//
// Widgets read `repo.people()` / `repo.unnamedFaces()` (via PeopleScope).
// [createFaceRepository] picks the implementation by what's wired.

import 'dart:async';

import 'package:photo_native/photo_native.dart';

import '../../utils/hue.dart';
import '../models.dart';

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

  /// A person's confirmed faces (highest quality first). Empty in mock mode.
  List<FaceRow> confirmedFacesForPerson(int personId);

  /// Display name for a person id, or null if not found / unnamed.
  String? personName(int personId);

  /// Confirm a face into a cluster/person. Returns a request id (0 in mock).
  int approve({required int clusterId, required int faceId});

  /// Reject a face's suggested membership. Returns a request id (0 in mock).
  int reject({required int clusterId, required int faceId});

  /// Schedule a face scan for a catalog asset (the native side resolves the
  /// path via the asset id). Returns a request id.
  int scan({required int assetId});

  /// Re-cluster all unconfirmed faces (full recompute). Returns a request id
  /// (0 in mock).
  int rebuildClusters();

  /// Name (or rename) a person. Returns a photo_status_t (0 == OK).
  int namePerson(int personId, String name);

  /// Promote an unconfirmed cluster into a named person (confirm-all, merging
  /// into an existing person of the same name). Returns a request id (0 in mock).
  int nameCluster(int clusterId, String name);

  /// Hide (ignore) or restore a detected face. photo_status_t (0 == OK).
  int setFaceIgnored(int faceId, bool ignored);

  /// Add a user-drawn face rectangle (source-image pixels) to an asset.
  /// Returns the new face id, or 0 on failure.
  int addManualFace(int assetId,
      {required double x,
      required double y,
      required double w,
      required double h});

  /// Assign a face to a named person (create/merge), confirming it. photo_status_t.
  int assignFace(int faceId, String name);

  /// Delete a face row (undo a manual rectangle). photo_status_t.
  int removeFace(int faceId);

  /// Write the asset's named face regions to an XMP sidecar. OPT-IN write-back.
  /// Returns the sidecar path, or null (no named faces / unsupported / error).
  String? writeFaceXmp(int assetId);

  /// Fires when the clustering changes (scan completed / approve / reject /
  /// rebuild), so the UI can re-query. Never fires in mock mode.
  Stream<void> get changes;

  /// True when backed by the live native pipeline.
  bool get isLive;
}

/// Picks the live repository when an engine is available, else the mockup.
FaceRepository createFaceRepository(
    {Engine? engine, Stream<PhotoEvent>? events}) {
  if (engine == null) return const MockFaceRepository();
  return NativeFaceRepository(engine, events);
}

// ---------------------------------------------------------------------------
// Offline — used when no native backend is mounted. With the mock library
// stripped there is no face data, so People is simply empty until the live
// pipeline scans the imported photos.
// ---------------------------------------------------------------------------

class MockFaceRepository implements FaceRepository {
  const MockFaceRepository();

  @override
  bool get isLive => false;

  @override
  List<Person> people() => const [];

  @override
  List<UnnamedFace> unnamedFaces() => const [];

  @override
  List<FaceRow> facesInCluster(int clusterId) => const [];

  @override
  List<FaceRow> suggestions(int personId) => const [];

  @override
  List<FaceRow> facesForAsset(int assetId) => const [];

  @override
  List<FaceRow> confirmedFacesForPerson(int personId) => const [];

  @override
  String? personName(int personId) => null;

  @override
  int approve({required int clusterId, required int faceId}) => 0;

  @override
  int reject({required int clusterId, required int faceId}) => 0;

  @override
  int scan({required int assetId}) => 0;

  @override
  int rebuildClusters() => 0;

  @override
  int namePerson(int personId, String name) => 0;

  @override
  int nameCluster(int clusterId, String name) => 0;

  @override
  int setFaceIgnored(int faceId, bool ignored) => 0;

  @override
  int addManualFace(int assetId,
          {required double x,
          required double y,
          required double w,
          required double h}) =>
      0;

  @override
  int assignFace(int faceId, String name) => 0;

  @override
  int removeFace(int faceId) => 0;

  @override
  String? writeFaceXmp(int assetId) => null;

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
            hue: hueForId(p.personId),
            confirmed: p.confirmed,
          ),
      ];

  @override
  List<UnnamedFace> unnamedFaces() => [
        for (final c in _engine.listClusters())
          UnnamedFace(
            id: 'nc${c.clusterId}',
            hue: hueForId(c.clusterId),
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
  List<FaceRow> confirmedFacesForPerson(int personId) {
    for (final p in _engine.listPeople()) {
      if (p.personId == personId) {
        return _engine
            .listClusterFaces(p.clusterId)
            .where((f) => f.confirmed)
            .toList();
      }
    }
    return const [];
  }

  @override
  String? personName(int personId) {
    for (final p in _engine.listPeople()) {
      if (p.personId == personId) return p.name.isEmpty ? null : p.name;
    }
    return null;
  }

  @override
  int approve({required int clusterId, required int faceId}) =>
      _engine.approveFace(clusterId: clusterId, embeddingId: faceId);

  @override
  int reject({required int clusterId, required int faceId}) =>
      _engine.rejectFace(clusterId: clusterId, embeddingId: faceId);

  @override
  int scan({required int assetId}) => _engine.scanFaces(assetId: assetId);

  @override
  int rebuildClusters() => _engine.rebuildClusters();

  @override
  int namePerson(int personId, String name) =>
      _engine.namePerson(personId, name);

  @override
  int nameCluster(int clusterId, String name) =>
      _engine.nameCluster(clusterId, name);

  @override
  int setFaceIgnored(int faceId, bool ignored) {
    final rc = _engine.setFaceIgnored(faceId, ignored);
    if (rc == 0) _changes.add(null);
    return rc;
  }

  @override
  int addManualFace(int assetId,
      {required double x,
      required double y,
      required double w,
      required double h}) {
    final id = _engine.addManualFace(assetId, x: x, y: y, w: w, h: h);
    if (id != 0) _changes.add(null);
    return id;
  }

  @override
  int assignFace(int faceId, String name) {
    final rc = _engine.assignFace(faceId, name);
    if (rc == 0) _changes.add(null);
    return rc;
  }

  @override
  int removeFace(int faceId) {
    final rc = _engine.removeFace(faceId);
    if (rc == 0) _changes.add(null);
    return rc;
  }

  @override
  String? writeFaceXmp(int assetId) => _engine.writeFaceXmp(assetId);

  @override
  Stream<void> get changes => _changes.stream;

  void dispose() {
    _sub?.cancel();
    _changes.close();
  }
}
