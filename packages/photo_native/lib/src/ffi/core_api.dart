// core_api.dart — typed Dart facade over the photo_core C ABI.
//
// During M1 this file hand-writes the FFI bindings for the engine/slot/event
// subset so the Dart side works end-to-end without the ffigen step. In M2,
// when ffigen runs and `bindings_generated.dart` becomes real, this file is
// refactored to delegate to PhotoBindings and only keep the typed wrappers.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'load_library.dart';
import 'request_arena.dart';

// ---------------------------------------------------------------------------
// Enum mirrors (must stay in sync with photo_core.h)
// ---------------------------------------------------------------------------

abstract final class LogLevel {
  static const int trace = 0;
  static const int debug = 1;
  static const int info = 2;
  static const int warn = 3;
  static const int error = 4;
}

abstract final class Stage {
  static const int placeholder32 = 1;
  static const int thumb256 = 2;
  static const int full = 3;

  static const int maskPlaceholder32 = 1 << 0;
  static const int maskThumb256 = 1 << 1;
  static const int maskFull = 1 << 2;
  static const int maskDefault = maskPlaceholder32 | maskThumb256;
}

abstract final class Priority {
  static const int interactive = 0;
  static const int viewport = 1;
  static const int idle = 2;
}

/// photo_provider_t mirror (for [Engine.probeProvider]).
abstract final class Provider {
  static const int cpu = 0;
  static const int coreml = 1;
  static const int directml = 2;
  static const int winml = 3;
  static const int cuda = 4;
}

// ---------------------------------------------------------------------------
// photo_config_t mirror — kept POD-compatible with the C struct
// ---------------------------------------------------------------------------

final class _NativeConfig extends Struct {
  external Pointer<Utf8> catalog_path_utf8;
  external Pointer<Utf8> cache_path_utf8;
  external Pointer<Utf8> models_path_utf8;
  @Uint64()
  external int memory_budget_bytes;
  @Uint64()
  external int disk_budget_bytes;
  @Uint32()
  external int decode_threads;
  @Uint32()
  external int io_threads;
  @Uint32()
  external int ml_threads;
  @Uint32()
  external int log_level;
  @Uint32()
  external int flags;
}

final class _NativeFrameView extends Struct {
  external Pointer<Uint8> bgra;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int stride;
  external Pointer<Void> release_ctx;
}

final class NativeEvent extends Struct {
  @Uint32()
  external int kind;
  @Uint32()
  external int stage;
  @Int32()
  external int status;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint64()
  external int request_id;
  @Uint64()
  external int asset_id;
  @Uint64()
  external int slot_id;
  @Uint64()
  external int generation;
  @Uint64()
  external int aux64;
  @Uint64()
  external int aux64_b;
  @Array(2)
  external Array<Uint32> reserved;
}

/// photo_person_t mirror (face read-back).
final class _NativePerson extends Struct {
  @Uint64()
  external int person_id;
  @Int64()
  external int cluster_id;
  @Uint64()
  external int cover_face_id;
  @Int32()
  external int face_count;
  @Int32()
  external int confirmed_count;
  @Int32()
  external int confirmed;
  @Int32()
  external int pad;
  @Array(128)
  external Array<Uint8> name;
}

/// photo_face_t mirror (face read-back).
final class _NativeFace extends Struct {
  @Uint64()
  external int face_id;
  @Uint64()
  external int asset_id;
  @Int64()
  external int cluster_id;
  @Int64()
  external int person_id;
  @Float()
  external double box_x;
  @Float()
  external double box_y;
  @Float()
  external double box_w;
  @Float()
  external double box_h;
  @Float()
  external double det_score;
  @Float()
  external double quality;
  @Int32()
  external int confirmed;
  @Int32()
  external int pad;
}

/// photo_asset_t mirror (catalog hydration). Field order + sizes must match
/// the C struct exactly.
final class _NativeAsset extends Struct {
  @Uint64()
  external int asset_id;
  @Uint64()
  external int size;
  @Uint64()
  external int mtime_ns;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int orientation;
  @Int32()
  external int starred;
  @Int32()
  external int rating;
  @Uint32()
  external int flags;
  @Array(3)
  external Array<Uint32> reserved;
  @Array(4096)
  external Array<Uint8> path;
}

/// PHOTO_ASSET_FLAG_HIDDEN.
const int _kAssetFlagHidden = 1 << 0;

/// photo_geopoint_t mirror.
final class _NativeGeoPoint extends Struct {
  @Uint64()
  external int asset_id;
  @Double()
  external double lat;
  @Double()
  external double lon;
}

// ---------------------------------------------------------------------------
// FFI function typedefs
// ---------------------------------------------------------------------------

typedef _AbiVersionC = Uint32 Function();
typedef _AbiVersionDart = int Function();

typedef _EngineVersionC = Pointer<Utf8> Function();
typedef _EngineVersionDart = Pointer<Utf8> Function();

typedef _EngineCreateC = Pointer<Void> Function(Pointer<_NativeConfig>);
typedef _EngineCreateDart = Pointer<Void> Function(Pointer<_NativeConfig>);

typedef _EngineDestroyC = Void Function(Pointer<Void>);
typedef _EngineDestroyDart = void Function(Pointer<Void>);

typedef _SlotCreateC = Uint64 Function(Pointer<Void>, Int32, Int32);
typedef _SlotCreateDart = int Function(Pointer<Void>, int, int);

typedef _SlotDestroyC = Void Function(Pointer<Void>, Uint64);
typedef _SlotDestroyDart = void Function(Pointer<Void>, int);

typedef _SlotBindGenC = Uint64 Function(Pointer<Void>, Uint64, Uint64);
typedef _SlotBindGenDart = int Function(Pointer<Void>, int, int);

typedef _SlotAcquireC =
    Bool Function(Pointer<Void>, Uint64, Pointer<_NativeFrameView>);
typedef _SlotAcquireDart =
    bool Function(Pointer<Void>, int, Pointer<_NativeFrameView>);

typedef _SlotReleaseC = Void Function(Pointer<Void>, Pointer<Void>);
typedef _SlotReleaseDart = void Function(Pointer<Void>, Pointer<Void>);

typedef _PollEventsC =
    IntPtr Function(Pointer<Void>, Pointer<NativeEvent>, IntPtr);
typedef _PollEventsDart = int Function(Pointer<Void>, Pointer<NativeEvent>, int);

// TEST-ONLY (M1): publishes a solid BGRA color for a slot. Replaced in M2
// by the real photo_thumb_request pipeline. Kept on Engine so integration
// code doesn't need implementation_import to reach the symbol.
typedef _TestPublishSolidC =
    Void Function(Pointer<Void>, Uint64, Uint8, Uint8, Uint8, Uint8);
typedef _TestPublishSolidDart =
    void Function(Pointer<Void>, int, int, int, int, int);

// M2 — request pipeline hot path. Scalar args; no per-call alloc on the
// Dart side beyond the UTF-8 path buffer (reused via RequestArena).
typedef _ThumbRequestFastC = Uint64 Function(
    Pointer<Void>,    // engine
    Uint64,           // asset_id
    Uint64,           // slot_id
    Uint64,           // generation
    Pointer<Utf8>,    // path_utf8
    Uint32,           // target_w
    Uint32,           // target_h
    Uint32,           // wanted_stages_mask
    Uint32,           // priority
    Uint32);          // flags
typedef _ThumbRequestFastDart = int Function(
    Pointer<Void>,
    int, int, int,
    Pointer<Utf8>,
    int, int, int, int, int);

typedef _ThumbCancelC = Void Function(Pointer<Void>, Uint64);
typedef _ThumbCancelDart = void Function(Pointer<Void>, int);

// M6/M7 — face pipeline. Async: each returns a non-zero request id and
// reports completion via PHOTO_EVT_SCAN_PROGRESS / PHOTO_EVT_CLUSTER_UPDATED.
typedef _FaceScanC = Uint64 Function(Pointer<Void>, Uint64, Uint32);
typedef _FaceScanDart = int Function(Pointer<Void>, int, int);

// Import + catalog. import/rescan are async (return a request id; emit
// PHOTO_EVT_IMPORT_*); list_assets is synchronous grow-and-retry.
typedef _ImportPathC = Uint64 Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _ImportPathDart = int Function(Pointer<Void>, Pointer<Utf8>, int);

typedef _RescanC = Uint64 Function(Pointer<Void>, Uint32);
typedef _RescanDart = int Function(Pointer<Void>, int);

typedef _ListAssetsC =
    IntPtr Function(Pointer<Void>, Pointer<_NativeAsset>, IntPtr);
typedef _ListAssetsDart =
    int Function(Pointer<Void>, Pointer<_NativeAsset>, int);

typedef _ListGeotaggedC =
    IntPtr Function(Pointer<Void>, Pointer<_NativeGeoPoint>, IntPtr);
typedef _ListGeotaggedDart =
    int Function(Pointer<Void>, Pointer<_NativeGeoPoint>, int);

typedef _FaceApproveC = Uint64 Function(Pointer<Void>, Uint64, Uint64);
typedef _FaceApproveDart = int Function(Pointer<Void>, int, int);

typedef _ClusterRebuildC = Uint64 Function(Pointer<Void>, Uint32);
typedef _ClusterRebuildDart = int Function(Pointer<Void>, int);

typedef _ProviderProbeC = Int32 Function(Pointer<Void>, Int32);
typedef _ProviderProbeDart = int Function(Pointer<Void>, int);

// Face read-back: fill up to `cap` rows, return total count available.
typedef _ListPeopleC =
    IntPtr Function(Pointer<Void>, Pointer<_NativePerson>, IntPtr);
typedef _ListPeopleDart =
    int Function(Pointer<Void>, Pointer<_NativePerson>, int);

typedef _ListClusterFacesC =
    IntPtr Function(Pointer<Void>, Int64, Pointer<_NativeFace>, IntPtr);
typedef _ListClusterFacesDart =
    int Function(Pointer<Void>, int, Pointer<_NativeFace>, int);

typedef _ListFacesByIdC =
    IntPtr Function(Pointer<Void>, Uint64, Pointer<_NativeFace>, IntPtr);
typedef _ListFacesByIdDart =
    int Function(Pointer<Void>, int, Pointer<_NativeFace>, int);

typedef _NamePersonC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _NamePersonDart = int Function(Pointer<Void>, int, Pointer<Utf8>);

typedef _NameClusterC = Uint64 Function(Pointer<Void>, Int64, Pointer<Utf8>);
typedef _NameClusterDart = int Function(Pointer<Void>, int, Pointer<Utf8>);

// ---------------------------------------------------------------------------
// EngineConfig (Dart-side, immutable)
// ---------------------------------------------------------------------------

final class EngineConfig {
  const EngineConfig({
    required this.catalogPath,
    required this.cachePath,
    this.modelsPath,
    this.memoryBudgetBytes = 0,
    this.diskBudgetBytes = 0,
    this.decodeThreads = 0,
    this.ioThreads = 0,
    this.mlThreads = 0,
    this.logLevel = LogLevel.info,
  });

  final String catalogPath;
  final String cachePath;
  final String? modelsPath;
  final int memoryBudgetBytes;
  final int diskBudgetBytes;
  final int decodeThreads;
  final int ioThreads;
  final int mlThreads;
  final int logLevel;
}

// ---------------------------------------------------------------------------
// Engine — handle wrapper
// ---------------------------------------------------------------------------

final class Engine {
  Engine._(this._handle) : _arena = RequestArena();

  /// Create the engine from [config]. Returns null on failure (invalid paths,
  /// cache dir not writable, etc.).
  static Engine? open(EngineConfig config) {
    final cfg = calloc<_NativeConfig>();
    final cat = config.catalogPath.toNativeUtf8();
    final cache = config.cachePath.toNativeUtf8();
    final models = config.modelsPath?.toNativeUtf8();
    try {
      cfg.ref
        ..catalog_path_utf8 = cat
        ..cache_path_utf8 = cache
        ..models_path_utf8 = models ?? nullptr
        ..memory_budget_bytes = config.memoryBudgetBytes
        ..disk_budget_bytes = config.diskBudgetBytes
        ..decode_threads = config.decodeThreads
        ..io_threads = config.ioThreads
        ..ml_threads = config.mlThreads
        ..log_level = config.logLevel
        ..flags = 0;
      final h = _Bindings.engineCreate(cfg);
      if (h == nullptr) return null;
      return Engine._(h);
    } finally {
      calloc.free(cfg);
      calloc.free(cat);
      calloc.free(cache);
      if (models != null) calloc.free(models);
    }
  }

  Pointer<Void> _handle;
  final RequestArena _arena;

  /// Raw pointer address. Internal — used to hand the engine to the platform
  /// plugin via [TextureRegistry.attachEngine] so the plugin's texture
  /// callback can call photo_slot_acquire_latest. Do not expose to UI code.
  int get nativeHandle => _handle.address;

  static int get abiVersion => _Bindings.abiVersion();
  static String get engineVersion =>
      _Bindings.engineVersion().toDartString();

  /// Create a render slot for a visible tile.
  int createSlot({required int initialW, required int initialH}) =>
      _Bindings.slotCreate(_handle, initialW, initialH);

  void destroySlot(int slotId) => _Bindings.slotDestroy(_handle, slotId);

  /// Rebind a slot's generation token. Returns the previous generation.
  int bindGeneration(int slotId, int generation) =>
      _Bindings.slotBindGen(_handle, slotId, generation);

  /// Drain up to [cap] events into the supplied buffer. Returns the count.
  int pollEvents(Pointer<NativeEvent> out, int cap) =>
      _Bindings.pollEvents(_handle, out, cap);

  /// Submit a thumbnail request. Returns a non-zero request id on
  /// acceptance; 0 if rejected (invalid slot, no stages requested, etc.).
  /// The path string is copied into an engine-owned scratch arena so no
  /// per-call heap allocation reaches the C ABI on the hot path.
  ///
  /// Caller must invoke this from the Dart main isolate (the arena is
  /// not thread-safe and the Texture callbacks expect the engine to be
  /// driven from a single Dart thread).
  ///
  /// Target: p99 < 50 µs end-to-end.
  int requestThumbnail({
    required int assetId,
    required int slotId,
    required int generation,
    required String path,
    required int targetW,
    required int targetH,
    int wantedStagesMask = Stage.maskDefault,
    int priority = Priority.viewport,
    int flags = 0,
  }) {
    final pathPtr = _arena.utf8(path);
    return _Bindings.thumbRequestFast(
      _handle,
      assetId,
      slotId,
      generation,
      pathPtr,
      targetW,
      targetH,
      wantedStagesMask,
      priority,
      flags,
    );
  }

  /// Cancel a previously submitted thumbnail request. Safe with unknown ids.
  void cancelRequest(int requestId) {
    if (requestId == 0) return;
    _Bindings.thumbCancel(_handle, requestId);
  }

  // -------------------------------------------------------------------------
  // Faces (M6/M7). All async: the returned request id matches the
  // `request_id` on the resulting PHOTO_EVT_SCAN_PROGRESS / CLUSTER_UPDATED
  // event drained via [pollEvents]. Returns 0 if rejected (faces unavailable).
  // -------------------------------------------------------------------------

  /// Schedule a face scan (detect → align → embed → online-assign) for an
  /// imported asset. Emits PHOTO_EVT_SCAN_PROGRESS with the kept-face count
  /// in `aux64`.
  int scanFaces({required int assetId, int flags = 0}) =>
      _Bindings.faceScan(_handle, assetId, flags);

  // -------------------------------------------------------------------------
  // Import + catalog
  // -------------------------------------------------------------------------

  /// Recursively import [path] into the catalog. Async: returns a non-zero
  /// request id (0 if there is no catalog) and emits PHOTO_EVT_IMPORT_PROGRESS
  /// (aux64 = files done, aux64B = total) / PHOTO_EVT_IMPORT_COMPLETE with the
  /// same request id.
  int importPath(String path, {int flags = 0}) {
    final p = path.toNativeUtf8();
    try {
      return _Bindings.importPath(_handle, p, flags);
    } finally {
      calloc.free(p);
    }
  }

  /// Re-walk every recorded import root (refresh stats, prune gone files).
  /// Same event contract as [importPath].
  int rescan({int flags = 0}) => _Bindings.rescan(_handle, flags);

  /// Snapshot of catalog assets (hidden excluded), ordered by path. Used once
  /// at boot to hydrate the stable asset-id ⇄ path mapping.
  List<AssetRow> listAssets() {
    var cap = 1024;
    var buf = calloc<_NativeAsset>(cap);
    try {
      var n = _Bindings.listAssets(_handle, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeAsset>(cap);
        n = _Bindings.listAssets(_handle, buf, cap);
      }
      final count = n < cap ? n : cap;
      return [for (var i = 0; i < count; i++) AssetRow._(buf[i])];
    } finally {
      calloc.free(buf);
    }
  }

  /// Every geotagged asset (those with GPS EXIF). Drives the map.
  List<GeoPoint> listGeotagged() {
    var cap = 256;
    var buf = calloc<_NativeGeoPoint>(cap);
    try {
      var n = _Bindings.listGeotagged(_handle, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeGeoPoint>(cap);
        n = _Bindings.listGeotagged(_handle, buf, cap);
      }
      final count = n < cap ? n : cap;
      return [
        for (var i = 0; i < count; i++)
          GeoPoint(buf[i].asset_id, buf[i].lat, buf[i].lon),
      ];
    } finally {
      calloc.free(buf);
    }
  }

  /// Confirm a face's membership in a cluster/person. Folds its embedding into
  /// the person prototype. Emits PHOTO_EVT_CLUSTER_UPDATED.
  int approveFace({required int clusterId, required int embeddingId}) =>
      _Bindings.faceApprove(_handle, clusterId, embeddingId);

  /// Reject a face's suggested membership. Emits PHOTO_EVT_CLUSTER_UPDATED.
  int rejectFace({required int clusterId, required int embeddingId}) =>
      _Bindings.faceReject(_handle, clusterId, embeddingId);

  /// Full agglomerative re-cluster over every embedded face (idle lane).
  /// Emits PHOTO_EVT_CLUSTER_UPDATED on completion.
  int rebuildClusters({int flags = 0}) =>
      _Bindings.clusterRebuild(_handle, flags);

  /// Probe whether an ML [Provider] is usable. Synchronous; returns a
  /// photo_status_t (0 == OK/usable).
  int probeProvider(int provider) =>
      _Bindings.providerProbe(_handle, provider);

  // -------------------------------------------------------------------------
  // Face read-back (UI queries). Synchronous; metadata only — no image bytes
  // cross the boundary. A returned [FaceRow] carries its asset id + source
  // box; the UI clips the asset thumbnail to render the face.
  // -------------------------------------------------------------------------

  /// Confirmed/named people.
  List<FacePerson> listPeople() =>
      _readPeople((b, c) => _Bindings.listPeople(_handle, b, c));

  /// Unconfirmed cluster buckets (the "unnamed faces" groups).
  List<FacePerson> listClusters() =>
      _readPeople((b, c) => _Bindings.listClusters(_handle, b, c));

  /// Members of one cluster, highest quality first.
  List<FaceRow> listClusterFaces(int clusterId) => _readFaces(
        (b, c) => _Bindings.listClusterFaces(_handle, clusterId, b, c),
      );

  /// Unconfirmed (suggested) faces for a person — the confirm queue.
  List<FaceRow> listSuggestions(int personId) => _readFaces(
        (b, c) => _Bindings.listSuggestions(_handle, personId, b, c),
      );

  /// Faces detected in one asset (info-panel People tab).
  List<FaceRow> listFacesForAsset(int assetId) => _readFaces(
        (b, c) => _Bindings.listForAsset(_handle, assetId, b, c),
      );

  /// Name (or rename) a person. Returns a photo_status_t (0 == OK).
  int namePerson(int personId, String name) {
    final p = name.toNativeUtf8();
    try {
      return _Bindings.namePerson(_handle, personId, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Promote an unconfirmed cluster into a named person: confirms every face in
  /// the cluster into a person named [name] (merging into an existing person of
  /// the same name, else creating one). Returns a request id; emits
  /// PHOTO_EVT_CLUSTER_UPDATED on completion.
  int nameCluster(int clusterId, String name) {
    final p = name.toNativeUtf8();
    try {
      return _Bindings.nameCluster(_handle, clusterId, p);
    } finally {
      calloc.free(p);
    }
  }

  // Grow-and-retry read into a native buffer; the C side returns the total
  // count, so a single re-call covers the case where the first buffer was
  // too small.
  List<FacePerson> _readPeople(int Function(Pointer<_NativePerson>, int) call) {
    var cap = 64;
    var buf = calloc<_NativePerson>(cap);
    try {
      var n = call(buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativePerson>(cap);
        n = call(buf, cap);
      }
      final count = n < cap ? n : cap;
      return [for (var i = 0; i < count; i++) FacePerson._(buf[i])];
    } finally {
      calloc.free(buf);
    }
  }

  List<FaceRow> _readFaces(int Function(Pointer<_NativeFace>, int) call) {
    var cap = 128;
    var buf = calloc<_NativeFace>(cap);
    try {
      var n = call(buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeFace>(cap);
        n = call(buf, cap);
      }
      final count = n < cap ? n : cap;
      return [for (var i = 0; i < count; i++) FaceRow._(buf[i])];
    } finally {
      calloc.free(buf);
    }
  }

  /// **M1 TEST HOOK** — publishes a solid BGRA color as the slot's current
  /// frame. Replaced in M2 by the real `requestThumbnail` pipeline that
  /// dispatches actual decode jobs. Kept on Engine so that integration
  /// callers do not need to reach into `implementation_imports`.
  ///
  /// Channel values are 0..255. Alpha is straight (premultiplication is done
  /// inside the engine).
  void testPublishSolid(int slotId, int r, int g, int b, int a) {
    _Bindings.testPublishSolid(_handle, slotId, r, g, b, a);
  }

  /// Borrow the latest frame for [slotId]. The caller must call [releaseFrame]
  /// with the returned release context exactly once. Returns null if no frame
  /// is yet available.
  FrameView? acquireFrame(int slotId) {
    final view = calloc<_NativeFrameView>();
    try {
      final ok = _Bindings.slotAcquire(_handle, slotId, view);
      if (!ok) return null;
      return FrameView._(
        bgra: view.ref.bgra,
        width: view.ref.width,
        height: view.ref.height,
        stride: view.ref.stride,
        releaseCtx: view.ref.release_ctx,
      );
    } finally {
      calloc.free(view);
    }
  }

  void releaseFrame(FrameView frame) =>
      _Bindings.slotRelease(_handle, frame.releaseCtx);

  void dispose() {
    if (_handle == nullptr) return;
    _Bindings.engineDestroy(_handle);
    _handle = nullptr;
    _arena.dispose();
  }
}

final class FrameView {
  FrameView._({
    required this.bgra,
    required this.width,
    required this.height,
    required this.stride,
    required this.releaseCtx,
  });

  final Pointer<Uint8> bgra;
  final int width;
  final int height;
  final int stride;
  final Pointer<Void> releaseCtx;
}

/// A person (confirmed/named cluster) or an unnamed cluster bucket
/// (personId == 0, name empty). Immutable projection of photo_person_t.
final class FacePerson {
  FacePerson._(_NativePerson p)
    : personId = p.person_id,
      clusterId = p.cluster_id,
      coverFaceId = p.cover_face_id,
      faceCount = p.face_count,
      confirmedCount = p.confirmed_count,
      confirmed = p.confirmed != 0,
      name = _readCName(p.name, 128);

  final int personId;
  final int clusterId;
  final int coverFaceId;
  final int faceCount;
  final int confirmedCount;
  final bool confirmed;
  final String name;

  bool get isUnnamed => personId == 0 || name.isEmpty;
}

/// One face: detection metadata + cluster/person links. Immutable projection
/// of photo_face_t. Render by clipping the asset thumbnail to the box.
final class FaceRow {
  FaceRow._(_NativeFace f)
    : faceId = f.face_id,
      assetId = f.asset_id,
      clusterId = f.cluster_id,
      personId = f.person_id,
      boxX = f.box_x,
      boxY = f.box_y,
      boxW = f.box_w,
      boxH = f.box_h,
      score = f.det_score,
      quality = f.quality,
      confirmed = f.confirmed != 0;

  final int faceId;
  final int assetId;
  final int clusterId;
  final int personId;
  final double boxX;
  final double boxY;
  final double boxW;
  final double boxH;
  final double score;
  final double quality;
  final bool confirmed;
}

/// One catalog asset, for library hydration. Immutable projection of
/// photo_asset_t. The [assetId] is engine-assigned and stable across runs.
final class AssetRow {
  AssetRow._(_NativeAsset a)
    : assetId = a.asset_id,
      size = a.size,
      mtimeNs = a.mtime_ns,
      width = a.width,
      height = a.height,
      orientation = a.orientation,
      starred = a.starred != 0,
      rating = a.rating,
      hidden = (a.flags & _kAssetFlagHidden) != 0,
      path = _readCName(a.path, 4096);

  final int assetId;
  final String path;
  final int size;
  final int mtimeNs;
  final int width;
  final int height;
  final int orientation;
  final bool starred;
  final int rating;
  final bool hidden;
}

/// A geotagged asset: id + decimal-degree coordinates. Immutable projection of
/// photo_geopoint_t.
final class GeoPoint {
  const GeoPoint(this.assetId, this.lat, this.lon);
  final int assetId;
  final double lat;
  final double lon;
}

/// Decode a NUL-terminated UTF-8 name out of a fixed-size native char array.
String _readCName(Array<Uint8> arr, int maxLen) {
  final bytes = <int>[];
  for (var i = 0; i < maxLen; i++) {
    final c = arr[i];
    if (c == 0) break;
    bytes.add(c);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

// ---------------------------------------------------------------------------
// Bindings table — late-initialized on first use
// ---------------------------------------------------------------------------

final class _Bindings {
  static final DynamicLibrary _dylib = openPhotoCore();

  static final _AbiVersionDart abiVersion = _dylib
      .lookupFunction<_AbiVersionC, _AbiVersionDart>('photo_abi_version');

  static final _EngineVersionDart engineVersion = _dylib
      .lookupFunction<_EngineVersionC, _EngineVersionDart>(
        'photo_engine_version',
      );

  static final _EngineCreateDart engineCreate = _dylib
      .lookupFunction<_EngineCreateC, _EngineCreateDart>(
        'photo_engine_create',
      );

  static final _EngineDestroyDart engineDestroy = _dylib
      .lookupFunction<_EngineDestroyC, _EngineDestroyDart>(
        'photo_engine_destroy',
      );

  static final _SlotCreateDart slotCreate = _dylib
      .lookupFunction<_SlotCreateC, _SlotCreateDart>('photo_slot_create');

  static final _SlotDestroyDart slotDestroy = _dylib
      .lookupFunction<_SlotDestroyC, _SlotDestroyDart>('photo_slot_destroy');

  static final _SlotBindGenDart slotBindGen = _dylib
      .lookupFunction<_SlotBindGenC, _SlotBindGenDart>(
        'photo_slot_bind_generation',
      );

  static final _SlotAcquireDart slotAcquire = _dylib
      .lookupFunction<_SlotAcquireC, _SlotAcquireDart>(
        'photo_slot_acquire_latest',
      );

  static final _SlotReleaseDart slotRelease = _dylib
      .lookupFunction<_SlotReleaseC, _SlotReleaseDart>('photo_slot_release');

  static final _PollEventsDart pollEvents = _dylib
      .lookupFunction<_PollEventsC, _PollEventsDart>('photo_poll_events');

  static final _TestPublishSolidDart testPublishSolid = _dylib
      .lookupFunction<_TestPublishSolidC, _TestPublishSolidDart>(
        'photo_test_publish_solid',
      );

  static final _ThumbRequestFastDart thumbRequestFast = _dylib
      .lookupFunction<_ThumbRequestFastC, _ThumbRequestFastDart>(
        'photo_thumb_request_fast',
      );

  static final _ThumbCancelDart thumbCancel = _dylib
      .lookupFunction<_ThumbCancelC, _ThumbCancelDart>('photo_thumb_cancel');

  static final _FaceScanDart faceScan = _dylib
      .lookupFunction<_FaceScanC, _FaceScanDart>('photo_face_scan');

  static final _ImportPathDart importPath = _dylib
      .lookupFunction<_ImportPathC, _ImportPathDart>('photo_import_path');

  static final _RescanDart rescan =
      _dylib.lookupFunction<_RescanC, _RescanDart>('photo_rescan');

  static final _ListAssetsDart listAssets = _dylib
      .lookupFunction<_ListAssetsC, _ListAssetsDart>('photo_list_assets');

  static final _ListGeotaggedDart listGeotagged = _dylib
      .lookupFunction<_ListGeotaggedC, _ListGeotaggedDart>(
        'photo_list_geotagged',
      );

  static final _FaceApproveDart faceApprove = _dylib
      .lookupFunction<_FaceApproveC, _FaceApproveDart>('photo_face_approve');

  static final _FaceApproveDart faceReject = _dylib
      .lookupFunction<_FaceApproveC, _FaceApproveDart>('photo_face_reject');

  static final _ClusterRebuildDart clusterRebuild = _dylib
      .lookupFunction<_ClusterRebuildC, _ClusterRebuildDart>(
        'photo_cluster_rebuild',
      );

  static final _ProviderProbeDart providerProbe = _dylib
      .lookupFunction<_ProviderProbeC, _ProviderProbeDart>(
        'photo_provider_probe',
      );

  static final _ListPeopleDart listPeople = _dylib
      .lookupFunction<_ListPeopleC, _ListPeopleDart>('photo_face_list_people');

  static final _ListPeopleDart listClusters = _dylib
      .lookupFunction<_ListPeopleC, _ListPeopleDart>('photo_face_list_clusters');

  static final _ListClusterFacesDart listClusterFaces = _dylib
      .lookupFunction<_ListClusterFacesC, _ListClusterFacesDart>(
        'photo_face_list_cluster_faces',
      );

  static final _ListFacesByIdDart listSuggestions = _dylib
      .lookupFunction<_ListFacesByIdC, _ListFacesByIdDart>(
        'photo_face_list_suggestions',
      );

  static final _ListFacesByIdDart listForAsset = _dylib
      .lookupFunction<_ListFacesByIdC, _ListFacesByIdDart>(
        'photo_face_list_for_asset',
      );

  static final _NamePersonDart namePerson = _dylib
      .lookupFunction<_NamePersonC, _NamePersonDart>('photo_face_name_person');

  static final _NameClusterDart nameCluster = _dylib
      .lookupFunction<_NameClusterC, _NameClusterDart>('photo_face_name_cluster');
}
