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

/// photo_provider_t mirror (for [Engine.probeProvider]). Values MUST match the
/// C enum order in photo_core.h (CPU, WINML, DML, COREML, CUDA, OPENVINO).
abstract final class Provider {
  static const int cpu = 0;
  static const int winml = 1;
  static const int directml = 2;
  static const int coreml = 3;
  static const int cuda = 4;
  static const int openvino = 5;
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

/// photo_catalog_stats_t mirror.
final class _NativeCatalogStats extends Struct {
  @Int64()
  external int page_count;
  @Int64()
  external int freelist_count;
  @Int64()
  external int page_size;
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
  external int ignored;
  @Int32()
  external int manual;
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

/// photo_organize_t mirror.
final class _NativeOrganize extends Struct {
  @Int32()
  external int starred;
  @Int32()
  external int rating;
  @Array(512)
  external Array<Uint8> caption;
}

/// photo_album_t mirror.
final class _NativeAlbum extends Struct {
  @Uint64()
  external int album_id;
  @Uint64()
  external int cover_asset_id;
  @Int32()
  external int count;
  @Int32()
  external int pad;
  @Int64()
  external int created;
  @Array(128)
  external Array<Uint8> name;
}

// Stage 9 — semantic search. Field order/sizes mirror the C structs exactly.
final class _NativeEmbedCounts extends Struct {
  @Int64()
  external int done;
  @Int64()
  external int pending;
  @Int64()
  external int processing;
  @Int64()
  external int failed;
  @Int64()
  external int skipped;
  @Int64()
  external int total;
}

final class _NativeSearchHit extends Struct {
  @Uint64()
  external int asset_id;
  @Float()
  external double score;
  @Float()
  external double pad;
}

final class _NativeAssetColor extends Struct {
  @Uint64()
  external int asset_id;
  @Int32()
  external int rgb;
  @Int32()
  external int pad;
}

final class _NativeSavedSearch extends Struct {
  @Uint64()
  external int id;
  @Int64()
  external int created;
  @Array(128)
  external Array<Uint8> name;
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

// Albums.
typedef _AlbumCreateC = Uint64 Function(Pointer<Void>, Pointer<Utf8>);
typedef _AlbumCreateDart = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _AlbumRenameC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _AlbumRenameDart = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _AlbumIdC = Int32 Function(Pointer<Void>, Uint64);
typedef _AlbumIdDart = int Function(Pointer<Void>, int);
typedef _AlbumIdIdC = Int32 Function(Pointer<Void>, Uint64, Uint64);
typedef _AlbumIdIdDart = int Function(Pointer<Void>, int, int);
typedef _AlbumListC =
    IntPtr Function(Pointer<Void>, Pointer<_NativeAlbum>, IntPtr);
typedef _AlbumListDart = int Function(Pointer<Void>, Pointer<_NativeAlbum>, int);
typedef _AlbumMembersC =
    IntPtr Function(Pointer<Void>, Uint64, Pointer<Uint64>, IntPtr);
typedef _AlbumMembersDart =
    int Function(Pointer<Void>, int, Pointer<Uint64>, int);

// Smart collections — id arrays (recent takes a limit; starred does not).
typedef _SmartRecentC =
    IntPtr Function(Pointer<Void>, Int32, Pointer<Uint64>, IntPtr);
typedef _SmartRecentDart =
    int Function(Pointer<Void>, int, Pointer<Uint64>, int);
typedef _SmartStarredC = IntPtr Function(Pointer<Void>, Pointer<Uint64>, IntPtr);
typedef _SmartStarredDart = int Function(Pointer<Void>, Pointer<Uint64>, int);

// Maintenance — compact (returns request id), stats (struct out), checkpoint.
typedef _CatalogCompactC = Uint64 Function(Pointer<Void>);
typedef _CatalogCompactDart = int Function(Pointer<Void>);
typedef _CatalogStatsC =
    Int32 Function(Pointer<Void>, Pointer<_NativeCatalogStats>);
typedef _CatalogStatsDart =
    int Function(Pointer<Void>, Pointer<_NativeCatalogStats>);
typedef _EngineToInt32C = Int32 Function(Pointer<Void>);
typedef _EngineToInt32Dart = int Function(Pointer<Void>);
typedef _LibraryRebaseC =
    Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _LibraryRebaseDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

// Organize (star/rating/caption/tags).
typedef _AssetSetIntC = Int32 Function(Pointer<Void>, Uint64, Int32);
typedef _AssetSetIntDart = int Function(Pointer<Void>, int, int);
typedef _AssetSetStrC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _AssetSetStrDart = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _AssetOrganizeC =
    Int32 Function(Pointer<Void>, Uint64, Pointer<_NativeOrganize>);
typedef _AssetOrganizeDart =
    int Function(Pointer<Void>, int, Pointer<_NativeOrganize>);
typedef _AssetTagsC =
    IntPtr Function(Pointer<Void>, Uint64, Pointer<Uint8>, IntPtr);
typedef _AssetTagsDart =
    int Function(Pointer<Void>, int, Pointer<Uint8>, int);

// Hide (folder set-hidden + hidden-folders NUL-buffer). Per-asset set-hidden
// reuses _AssetSetIntC/Dart (photo_asset_set_hidden).
typedef _FolderSetHiddenC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _FolderSetHiddenDart = int Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _HiddenFoldersC =
    IntPtr Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _HiddenFoldersDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

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

// Stage 9 — semantic search & discovery.
typedef _EmbedScanC = Uint64 Function(Pointer<Void>, Uint64);
typedef _EmbedScanDart = int Function(Pointer<Void>, int);
typedef _EmbedCountsC = Int32 Function(Pointer<Void>, Pointer<_NativeEmbedCounts>);
typedef _EmbedCountsDart = int Function(Pointer<Void>, Pointer<_NativeEmbedCounts>);
typedef _EmbedPendingC =
    IntPtr Function(Pointer<Void>, Int32, Pointer<Uint64>, IntPtr);
typedef _EmbedPendingDart =
    int Function(Pointer<Void>, int, Pointer<Uint64>, int);
typedef _EmbedColorsC =
    IntPtr Function(Pointer<Void>, Pointer<_NativeAssetColor>, IntPtr);
typedef _EmbedColorsDart =
    int Function(Pointer<Void>, Pointer<_NativeAssetColor>, int);
typedef _EmbedTextC =
    Uint32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, Uint32);
typedef _EmbedTextDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Float>, int);
typedef _SemanticSearchC = IntPtr Function(Pointer<Void>, Pointer<Float>, Uint32,
    Pointer<Uint64>, IntPtr, Pointer<_NativeSearchHit>, IntPtr);
typedef _SemanticSearchDart = int Function(Pointer<Void>, Pointer<Float>, int,
    Pointer<Uint64>, int, Pointer<_NativeSearchHit>, int);
typedef _SemanticReleaseC = Void Function(Pointer<Void>, Uint32);
typedef _SemanticReleaseDart = void Function(Pointer<Void>, int);
typedef _SavedCreateC =
    Uint64 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SavedCreateDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SavedListC =
    IntPtr Function(Pointer<Void>, Pointer<_NativeSavedSearch>, IntPtr);
typedef _SavedListDart =
    int Function(Pointer<Void>, Pointer<_NativeSavedSearch>, int);
typedef _SavedQueryC =
    IntPtr Function(Pointer<Void>, Uint64, Pointer<Uint8>, IntPtr);
typedef _SavedQueryDart = int Function(Pointer<Void>, int, Pointer<Uint8>, int);
// Face editing (§7): ignore / manual rect / assign / remove / XMP write-back.
typedef _FaceSetIgnoredC = Int32 Function(Pointer<Void>, Uint64, Int32);
typedef _FaceSetIgnoredDart = int Function(Pointer<Void>, int, int);
typedef _FaceAddManualC =
    Uint64 Function(Pointer<Void>, Uint64, Float, Float, Float, Float);
typedef _FaceAddManualDart =
    int Function(Pointer<Void>, int, double, double, double, double);
typedef _FaceAssignC = Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>);
typedef _FaceAssignDart = int Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _FaceRemoveC = Int32 Function(Pointer<Void>, Uint64);
typedef _FaceRemoveDart = int Function(Pointer<Void>, int);
typedef _WriteFaceXmpC =
    Int32 Function(Pointer<Void>, Uint64, Pointer<Utf8>, IntPtr);
typedef _WriteFaceXmpDart = int Function(Pointer<Void>, int, Pointer<Utf8>, int);

// Manual geotag (§8).
typedef _AssetSetGeoC = Int32 Function(Pointer<Void>, Uint64, Double, Double);
typedef _AssetSetGeoDart = int Function(Pointer<Void>, int, double, double);
typedef _AssetClearGeoC = Int32 Function(Pointer<Void>, Uint64);
typedef _AssetClearGeoDart = int Function(Pointer<Void>, int);

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

  // -------------------------------------------------------------------------
  // Albums. Mutators return a photo_status_t (0 == OK); createAlbum returns the
  // new album id (0 on failure / no catalog).
  // -------------------------------------------------------------------------

  int createAlbum(String name) {
    final p = name.toNativeUtf8();
    try {
      return _Bindings.albumCreate(_handle, p);
    } finally {
      calloc.free(p);
    }
  }

  int renameAlbum(int albumId, String name) {
    final p = name.toNativeUtf8();
    try {
      return _Bindings.albumRename(_handle, albumId, p);
    } finally {
      calloc.free(p);
    }
  }

  int deleteAlbum(int albumId) => _Bindings.albumDelete(_handle, albumId);

  int setAlbumCover(int albumId, int coverAssetId) =>
      _Bindings.albumSetCover(_handle, albumId, coverAssetId);

  int addToAlbum(int albumId, int assetId) =>
      _Bindings.albumAdd(_handle, albumId, assetId);

  int removeFromAlbum(int albumId, int assetId) =>
      _Bindings.albumRemove(_handle, albumId, assetId);

  List<Album> listAlbums() {
    var cap = 64;
    var buf = calloc<_NativeAlbum>(cap);
    try {
      var n = _Bindings.albumList(_handle, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeAlbum>(cap);
        n = _Bindings.albumList(_handle, buf, cap);
      }
      final count = n < cap ? n : cap;
      return [for (var i = 0; i < count; i++) Album._(buf[i])];
    } finally {
      calloc.free(buf);
    }
  }

  // -------------------------------------------------------------------------
  // Organize state — star / rating / caption / tags. Catalog-only (D1).
  // Mutators return a photo_status_t (0 == OK).
  // -------------------------------------------------------------------------

  int setStarred(int assetId, bool v) =>
      _Bindings.assetSetStarred(_handle, assetId, v ? 1 : 0);

  int setRating(int assetId, int rating) =>
      _Bindings.assetSetRating(_handle, assetId, rating);

  int setCaption(int assetId, String caption) {
    final p = caption.toNativeUtf8();
    try {
      return _Bindings.assetSetCaption(_handle, assetId, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Hide/unhide a single asset (excludes it from [listAssets]).
  int setHidden(int assetId, bool v) =>
      _Bindings.assetSetHidden(_handle, assetId, v ? 1 : 0);

  /// Hide/unhide a whole folder ([path] is a directory) and persist the rule so
  /// assets re-imported beneath it stay hidden. Sweeps existing assets too.
  int setFolderHidden(String path, bool v) {
    final p = path.toNativeUtf8();
    try {
      return _Bindings.folderSetHidden(_handle, p, v ? 1 : 0);
    } finally {
      calloc.free(p);
    }
  }

  /// Hidden folder paths. Decoded from the NUL-separated native buffer.
  List<String> hiddenFolders() =>
      _decodeNulStrings((b, c) => _Bindings.hiddenFolders(_handle, b, c));

  /// Paths of individually-hidden assets (list_assets excludes hidden, so this
  /// is how the UI hydrates its hide filter on startup).
  List<String> hiddenAssets() =>
      _decodeNulStrings((b, c) => _Bindings.hiddenAssets(_handle, b, c));

  /// Decode a NUL-separated UTF-8 string buffer filled by a grow-and-return-
  /// total native call (hidden folders/assets, …).
  List<String> _decodeNulStrings(
      int Function(Pointer<Uint8> buf, int cap) fill,
      {int cap = 1024}) {
    var buf = calloc<Uint8>(cap);
    try {
      var n = fill(buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<Uint8>(cap);
        n = fill(buf, cap);
      }
      final len = n < cap ? n : cap;
      final bytes = buf.asTypedList(len);
      final out = <String>[];
      var start = 0;
      for (var i = 0; i < len; i++) {
        if (bytes[i] == 0) {
          if (i > start) {
            out.add(utf8.decode(bytes.sublist(start, i), allowMalformed: true));
          }
          start = i + 1;
        }
      }
      return out;
    } finally {
      calloc.free(buf);
    }
  }

  /// Star / rating / caption for an asset, or null if unknown.
  Organize? organize(int assetId) {
    final out = calloc<_NativeOrganize>();
    try {
      if (_Bindings.assetOrganize(_handle, assetId, out) != 0) return null;
      return Organize._(out.ref);
    } finally {
      calloc.free(out);
    }
  }

  int addTag(int assetId, String tag) {
    final p = tag.toNativeUtf8();
    try {
      return _Bindings.assetAddTag(_handle, assetId, p);
    } finally {
      calloc.free(p);
    }
  }

  int removeTag(int assetId, String tag) {
    final p = tag.toNativeUtf8();
    try {
      return _Bindings.assetRemoveTag(_handle, assetId, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Tags for an asset (sorted). Decoded from the NUL-separated native buffer.
  List<String> assetTags(int assetId) {
    var cap = 256;
    var buf = calloc<Uint8>(cap);
    try {
      var n = _Bindings.assetTags(_handle, assetId, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<Uint8>(cap);
        n = _Bindings.assetTags(_handle, assetId, buf, cap);
      }
      final len = n < cap ? n : cap;
      final bytes = buf.asTypedList(len);
      final tags = <String>[];
      var start = 0;
      for (var i = 0; i < len; i++) {
        if (bytes[i] == 0) {
          if (i > start) {
            tags.add(utf8.decode(bytes.sublist(start, i), allowMalformed: true));
          }
          start = i + 1;
        }
      }
      return tags;
    } finally {
      calloc.free(buf);
    }
  }

  /// Member asset ids of an album, in order.
  List<int> albumMembers(int albumId) =>
      _collectIds((b, c) => _Bindings.albumMembers(_handle, albumId, b, c));

  /// The [limit] most-recently-imported asset ids (smart "Recently Added").
  List<int> recentAssets(int limit) =>
      _collectIds((b, c) => _Bindings.smartRecent(_handle, limit, b, c));

  /// Starred asset ids (smart "Starred").
  List<int> starredAssets() =>
      _collectIds((b, c) => _Bindings.smartStarred(_handle, b, c));

  /// Compact the catalog (WAL checkpoint + VACUUM) on the idle lane. Returns a
  /// request id; a [PhotoEventKind.maintenanceComplete] event fires on done.
  int compactCatalog() => _Bindings.catalogCompact(_handle);

  /// Current catalog size stats, or null if unavailable.
  CatalogStats? catalogStats() {
    final out = calloc<_NativeCatalogStats>();
    try {
      if (_Bindings.catalogStats(_handle, out) != 0) return null;
      final r = out.ref;
      return CatalogStats(
        pageCount: r.page_count,
        freelistCount: r.freelist_count,
        pageSize: r.page_size,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// Synchronous checkpoint + VACUUM (blocks until done). Used by the on-exit
  /// cleanup, which must finish before the process tears down.
  int compactCatalogSync() => _Bindings.catalogCompactSync(_handle);

  /// Flush the WAL into the main DB (cheap; used before moving the DB file).
  int catalogCheckpoint() => _Bindings.catalogCheckpoint(_handle);

  /// Rebase every stored path from [oldPrefix] to [newPrefix] after the photo
  /// library moved on disk (preserves asset ids). Returns a photo_status_t
  /// (0 == OK; NOT_FOUND when [newPrefix] does not exist).
  int rebaseLibrary(String oldPrefix, String newPrefix) {
    final o = oldPrefix.toNativeUtf8();
    final n = newPrefix.toNativeUtf8();
    try {
      return _Bindings.libraryRebase(_handle, o, n);
    } finally {
      calloc.free(o);
      calloc.free(n);
    }
  }

  // -------------------------------------------------------------------------
  // Semantic search & discovery (Stage 9).
  // -------------------------------------------------------------------------

  /// Schedule embedding for one asset on the idle lane. Emits a
  /// [PhotoEventKind.embedProgress] event on completion. Returns a request id.
  int embeddingScan(int assetId) => _Bindings.embeddingScan(_handle, assetId);

  /// Embedding-index progress counts for the indexing UI.
  EmbeddingCounts embeddingCounts() {
    final out = calloc<_NativeEmbedCounts>();
    try {
      if (_Bindings.embeddingCounts(_handle, out) != 0) {
        return const EmbeddingCounts.empty();
      }
      final r = out.ref;
      return EmbeddingCounts(
        done: r.done,
        pending: r.pending,
        processing: r.processing,
        failed: r.failed,
        skipped: r.skipped,
        total: r.total,
      );
    } finally {
      calloc.free(out);
    }
  }

  /// Asset ids still needing embedding for the active model (the resume queue).
  /// [limit] < 0 means no cap.
  List<int> pendingEmbeddingIds({int limit = -1}) =>
      _collectIds((b, c) => _Bindings.embeddingPending(_handle, limit, b, c));

  /// Flip every failed embedding back to pending (explicit "retry failed").
  int retryFailedEmbeddings() => _Bindings.embeddingRetryFailed(_handle);

  /// (assetId → 0xRRGGBB dominant colour) for every embedded asset — colour
  /// search reads this.
  Map<int, int> embeddingColors() {
    var cap = 1024;
    var buf = calloc<_NativeAssetColor>(cap);
    try {
      var n = _Bindings.embeddingColors(_handle, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeAssetColor>(cap);
        n = _Bindings.embeddingColors(_handle, buf, cap);
      }
      final count = n < cap ? n : cap;
      return {for (var i = 0; i < count; i++) buf[i].asset_id: buf[i].rgb};
    } finally {
      calloc.free(buf);
    }
  }

  /// Embed a text query into the active model's vector space (empty if there is
  /// no embedder).
  List<double> embedText(String query) {
    final q = query.toNativeUtf8();
    var cap = 1024;
    var buf = calloc<Float>(cap);
    try {
      var dim = _Bindings.embedText(_handle, q, buf, cap);
      if (dim > cap) {
        calloc.free(buf);
        cap = dim;
        buf = calloc<Float>(cap);
        dim = _Bindings.embedText(_handle, q, buf, cap);
      }
      final n = dim < cap ? dim : cap;
      return [for (var i = 0; i < n; i++) buf[i]];
    } finally {
      calloc.free(buf);
      calloc.free(q);
    }
  }

  /// Cosine-rank [queryVec] over the done embeddings, optionally restricted to
  /// [candidates]. Returns up to [cap] hits, score-descending.
  List<SearchHit> semanticSearch(
    List<double> queryVec, {
    List<int> candidates = const [],
    int cap = 500,
  }) {
    if (queryVec.isEmpty) return const [];
    final q = calloc<Float>(queryVec.length);
    Pointer<Uint64> cand = nullptr;
    final out = calloc<_NativeSearchHit>(cap);
    try {
      for (var i = 0; i < queryVec.length; i++) {
        q[i] = queryVec[i];
      }
      if (candidates.isNotEmpty) {
        cand = calloc<Uint64>(candidates.length);
        for (var i = 0; i < candidates.length; i++) {
          cand[i] = candidates[i];
        }
      }
      final n = _Bindings.semanticSearch(
          _handle, q, queryVec.length, cand, candidates.length, out, cap);
      final count = n < cap ? n : cap;
      return [
        for (var i = 0; i < count; i++)
          SearchHit(assetId: out[i].asset_id, score: out[i].score),
      ];
    } finally {
      calloc.free(q);
      if (cand != nullptr) calloc.free(cand);
      calloc.free(out);
    }
  }

  /// Reclaim the RAM of lazily-loaded semantic inference sessions. Call with
  /// [releaseImageTower] when the embedding-indexing queue drains (the image
  /// tower is only needed while indexing) and [releaseTextTower] after a
  /// search idle timeout. The next embed/search transparently reloads (~1 s).
  static const int releaseImageTower = 1 << 0;
  static const int releaseTextTower = 1 << 1;
  void releaseSemanticSessions(int mask) =>
      _Bindings.semanticReleaseSessions(_handle, mask);

  /// Re-probe the models directory and swap the semantic embedder in — call
  /// after the first-run model download lands so real text→image search
  /// activates without an app restart. Returns the active model's dim.
  int reloadSemantic() => _Bindings.semanticReload(_handle);

  /// Persist a saved search ([queryJson] opaque). Returns its id (0 on failure).
  int createSavedSearch(String name, String queryJson) {
    final nptr = name.toNativeUtf8();
    final jptr = queryJson.toNativeUtf8();
    try {
      return _Bindings.savedSearchCreate(_handle, nptr, jptr);
    } finally {
      calloc.free(nptr);
      calloc.free(jptr);
    }
  }

  /// Delete a saved search. Returns a photo_status_t (0 == OK).
  int deleteSavedSearch(int id) => _Bindings.savedSearchDelete(_handle, id);

  /// List saved searches (newest first), each with its query hydrated.
  List<SavedSearch> listSavedSearches() {
    var cap = 64;
    var buf = calloc<_NativeSavedSearch>(cap);
    try {
      var n = _Bindings.savedSearchList(_handle, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<_NativeSavedSearch>(cap);
        n = _Bindings.savedSearchList(_handle, buf, cap);
      }
      final count = n < cap ? n : cap;
      return [
        for (var i = 0; i < count; i++)
          SavedSearch(
            id: buf[i].id,
            created: buf[i].created,
            name: _readCName(buf[i].name, 128),
            queryJson: savedSearchQuery(buf[i].id),
          ),
      ];
    } finally {
      calloc.free(buf);
    }
  }

  /// The opaque query_json of one saved search.
  String savedSearchQuery(int id) {
    var cap = 1024;
    var buf = calloc<Uint8>(cap);
    try {
      var n = _Bindings.savedSearchQuery(_handle, id, buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<Uint8>(cap);
        n = _Bindings.savedSearchQuery(_handle, id, buf, cap);
      }
      // n includes the NUL terminator.
      final len = n < cap ? n : cap;
      final strlen = len > 0 ? len - 1 : 0;
      return utf8.decode(buf.asTypedList(strlen), allowMalformed: true);
    } finally {
      calloc.free(buf);
    }
  }

  /// Collect a uint64 id array from a grow-and-return-total native call.
  List<int> _collectIds(int Function(Pointer<Uint64> buf, int cap) fill,
      {int cap = 256}) {
    var buf = calloc<Uint64>(cap);
    try {
      var n = fill(buf, cap);
      if (n > cap) {
        calloc.free(buf);
        cap = n;
        buf = calloc<Uint64>(cap);
        n = fill(buf, cap);
      }
      final count = n < cap ? n : cap;
      return [for (var i = 0; i < count; i++) buf[i]];
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

  /// Hide (ignore) or restore a detected face. Ignoring detaches it from its
  /// person/cluster and excludes it from People + re-clustering. photo_status_t.
  int setFaceIgnored(int faceId, bool ignored) =>
      _Bindings.faceSetIgnored(_handle, faceId, ignored ? 1 : 0);

  /// Add a user-drawn face rectangle (source-image pixels) to an asset. Returns
  /// the new face id, or 0 on failure.
  int addManualFace(int assetId,
          {required double x,
          required double y,
          required double w,
          required double h}) =>
      _Bindings.faceAddManual(_handle, assetId, x, y, w, h);

  /// Assign a face to a named person (create/merge by name), confirming it.
  /// Works for detector and manual faces alike. Returns photo_status_t.
  int assignFace(int faceId, String name) {
    final p = name.toNativeUtf8();
    try {
      return _Bindings.faceAssign(_handle, faceId, p);
    } finally {
      calloc.free(p);
    }
  }

  /// Hard-delete a face row (undo a manual rectangle). photo_status_t.
  int removeFace(int faceId) => _Bindings.faceRemove(_handle, faceId);

  /// Write the asset's named face regions to an XMP sidecar ("<path>.xmp") in
  /// the MWG Regions schema. OPT-IN write-back — call only on explicit user
  /// action. Returns the sidecar path on success, or null (no named faces /
  /// unsupported / error).
  String? writeFaceXmp(int assetId) {
    const cap = 4096;
    final out = calloc<Uint8>(cap);
    try {
      final rc = _Bindings.writeFaceXmp(_handle, assetId, out.cast(), cap);
      if (rc != 0) return null;
      return out.cast<Utf8>().toDartString();
    } finally {
      calloc.free(out);
    }
  }

  /// Manually set an asset's map coordinates (decimal degrees). Overrides EXIF
  /// GPS and survives rescan. Returns photo_status_t.
  int setGeo(int assetId, double lat, double lon) =>
      _Bindings.assetSetGeo(_handle, assetId, lat, lon);

  /// Clear a manual geotag, falling back to EXIF GPS. Returns photo_status_t.
  int clearGeo(int assetId) => _Bindings.assetClearGeo(_handle, assetId);

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
      confirmed = f.confirmed != 0,
      ignored = f.ignored != 0,
      manual = f.manual != 0;

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
  final bool ignored;
  final bool manual;
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

/// Star / rating / caption for an asset. Immutable projection of
/// photo_organize_t.
final class Organize {
  Organize._(_NativeOrganize o)
    : starred = o.starred != 0,
      rating = o.rating,
      caption = _readCName(o.caption, 512);

  final bool starred;
  final int rating;
  final String caption;
}

/// A user-created album. Immutable projection of photo_album_t. [coverAssetId]
/// is 0 when unset.
final class Album {
  Album._(_NativeAlbum a)
    : id = a.album_id,
      coverAssetId = a.cover_asset_id,
      count = a.count,
      created = a.created,
      name = _readCName(a.name, 128);

  final int id;
  final String name;
  final int coverAssetId;
  final int count;
  final int created;
}

/// Embedding-index progress counts (Stage 9). `total` is all non-hidden
/// assets; `pending` includes assets with no embedding row yet.
final class EmbeddingCounts {
  const EmbeddingCounts({
    required this.done,
    required this.pending,
    required this.processing,
    required this.failed,
    required this.skipped,
    required this.total,
  });
  const EmbeddingCounts.empty()
      : done = 0,
        pending = 0,
        processing = 0,
        failed = 0,
        skipped = 0,
        total = 0;

  final int done;
  final int pending;
  final int processing;
  final int failed;
  final int skipped;
  final int total;

  /// Terminal (won't be retried automatically): done + skipped + failed.
  int get settled => done + skipped + failed;
  bool get isComplete => total == 0 || pending + processing == 0;
}

/// One ranked semantic-search result.
final class SearchHit {
  const SearchHit({required this.assetId, required this.score});
  final int assetId;
  final double score;
}

/// A persisted saved search (Stage 9). [queryJson] is the serialized criteria.
final class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.queryJson,
    required this.created,
  });
  final int id;
  final String name;
  final String queryJson;
  final int created;
}

/// Catalog file size stats (from `photo_catalog_stats`).
final class CatalogStats {
  const CatalogStats({
    required this.pageCount,
    required this.freelistCount,
    required this.pageSize,
  });

  final int pageCount;
  final int freelistCount;
  final int pageSize;

  /// Approximate on-disk size of the main DB file.
  int get sizeBytes => pageCount * pageSize;

  /// Bytes a compaction would reclaim (freelist pages).
  int get reclaimableBytes => freelistCount * pageSize;
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

  static final _AlbumCreateDart albumCreate = _dylib
      .lookupFunction<_AlbumCreateC, _AlbumCreateDart>('photo_album_create');
  static final _AlbumRenameDart albumRename = _dylib
      .lookupFunction<_AlbumRenameC, _AlbumRenameDart>('photo_album_rename');
  static final _AlbumIdDart albumDelete = _dylib
      .lookupFunction<_AlbumIdC, _AlbumIdDart>('photo_album_delete');
  static final _AlbumIdIdDart albumSetCover = _dylib
      .lookupFunction<_AlbumIdIdC, _AlbumIdIdDart>('photo_album_set_cover');
  static final _AlbumIdIdDart albumAdd = _dylib
      .lookupFunction<_AlbumIdIdC, _AlbumIdIdDart>('photo_album_add');
  static final _AlbumIdIdDart albumRemove = _dylib
      .lookupFunction<_AlbumIdIdC, _AlbumIdIdDart>('photo_album_remove');
  static final _AlbumListDart albumList = _dylib
      .lookupFunction<_AlbumListC, _AlbumListDart>('photo_album_list');
  static final _AlbumMembersDart albumMembers = _dylib
      .lookupFunction<_AlbumMembersC, _AlbumMembersDart>('photo_album_members');
  static final _SmartRecentDart smartRecent = _dylib
      .lookupFunction<_SmartRecentC, _SmartRecentDart>('photo_smart_recent');
  static final _SmartStarredDart smartStarred = _dylib
      .lookupFunction<_SmartStarredC, _SmartStarredDart>('photo_smart_starred');
  static final _CatalogCompactDart catalogCompact = _dylib
      .lookupFunction<_CatalogCompactC, _CatalogCompactDart>(
          'photo_catalog_compact');
  static final _CatalogStatsDart catalogStats = _dylib
      .lookupFunction<_CatalogStatsC, _CatalogStatsDart>('photo_catalog_stats');
  static final _EngineToInt32Dart catalogCompactSync = _dylib
      .lookupFunction<_EngineToInt32C, _EngineToInt32Dart>(
          'photo_catalog_compact_sync');
  static final _EngineToInt32Dart catalogCheckpoint = _dylib
      .lookupFunction<_EngineToInt32C, _EngineToInt32Dart>(
          'photo_catalog_checkpoint');
  static final _LibraryRebaseDart libraryRebase = _dylib
      .lookupFunction<_LibraryRebaseC, _LibraryRebaseDart>(
          'photo_library_rebase');

  static final _AssetSetIntDart assetSetStarred = _dylib
      .lookupFunction<_AssetSetIntC, _AssetSetIntDart>('photo_asset_set_starred');
  static final _AssetSetIntDart assetSetRating = _dylib
      .lookupFunction<_AssetSetIntC, _AssetSetIntDart>('photo_asset_set_rating');
  static final _AssetSetStrDart assetSetCaption = _dylib
      .lookupFunction<_AssetSetStrC, _AssetSetStrDart>('photo_asset_set_caption');
  static final _AssetOrganizeDart assetOrganize = _dylib
      .lookupFunction<_AssetOrganizeC, _AssetOrganizeDart>('photo_asset_organize');
  static final _AssetSetStrDart assetAddTag = _dylib
      .lookupFunction<_AssetSetStrC, _AssetSetStrDart>('photo_asset_add_tag');
  static final _AssetSetStrDart assetRemoveTag = _dylib
      .lookupFunction<_AssetSetStrC, _AssetSetStrDart>('photo_asset_remove_tag');
  static final _AssetTagsDart assetTags = _dylib
      .lookupFunction<_AssetTagsC, _AssetTagsDart>('photo_asset_tags');
  static final _AssetSetIntDart assetSetHidden = _dylib
      .lookupFunction<_AssetSetIntC, _AssetSetIntDart>('photo_asset_set_hidden');
  static final _FolderSetHiddenDart folderSetHidden =
      _dylib.lookupFunction<_FolderSetHiddenC, _FolderSetHiddenDart>(
          'photo_folder_set_hidden');
  static final _HiddenFoldersDart hiddenFolders = _dylib
      .lookupFunction<_HiddenFoldersC, _HiddenFoldersDart>(
          'photo_hidden_folders');
  static final _HiddenFoldersDart hiddenAssets = _dylib
      .lookupFunction<_HiddenFoldersC, _HiddenFoldersDart>(
          'photo_hidden_assets');

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

  // Stage 9 — semantic search & discovery.
  static final _EmbedScanDart embeddingScan = _dylib
      .lookupFunction<_EmbedScanC, _EmbedScanDart>('photo_embedding_scan');
  static final _EmbedCountsDart embeddingCounts = _dylib
      .lookupFunction<_EmbedCountsC, _EmbedCountsDart>('photo_embedding_counts');
  static final _EmbedPendingDart embeddingPending = _dylib
      .lookupFunction<_EmbedPendingC, _EmbedPendingDart>(
          'photo_embedding_pending');
  static final _EngineToInt32Dart embeddingRetryFailed = _dylib
      .lookupFunction<_EngineToInt32C, _EngineToInt32Dart>(
          'photo_embedding_retry_failed');
  static final _EmbedColorsDart embeddingColors = _dylib
      .lookupFunction<_EmbedColorsC, _EmbedColorsDart>('photo_embedding_colors');
  static final _EmbedTextDart embedText = _dylib
      .lookupFunction<_EmbedTextC, _EmbedTextDart>('photo_embed_text');
  static final _SemanticSearchDart semanticSearch = _dylib
      .lookupFunction<_SemanticSearchC, _SemanticSearchDart>(
          'photo_semantic_search');
  static final _SemanticReleaseDart semanticReleaseSessions = _dylib
      .lookupFunction<_SemanticReleaseC, _SemanticReleaseDart>(
          'photo_semantic_release_sessions');
  static final _EngineToInt32Dart semanticReload = _dylib
      .lookupFunction<_EngineToInt32C, _EngineToInt32Dart>(
          'photo_semantic_reload');
  static final _SavedCreateDart savedSearchCreate = _dylib
      .lookupFunction<_SavedCreateC, _SavedCreateDart>(
          'photo_saved_search_create');
  static final _AlbumIdDart savedSearchDelete = _dylib
      .lookupFunction<_AlbumIdC, _AlbumIdDart>('photo_saved_search_delete');
  static final _SavedListDart savedSearchList = _dylib
      .lookupFunction<_SavedListC, _SavedListDart>('photo_saved_search_list');
  static final _SavedQueryDart savedSearchQuery = _dylib
      .lookupFunction<_SavedQueryC, _SavedQueryDart>('photo_saved_search_query');
  // Face editing (§7).
  static final _FaceSetIgnoredDart faceSetIgnored = _dylib
      .lookupFunction<_FaceSetIgnoredC, _FaceSetIgnoredDart>(
        'photo_face_set_ignored',
      );
  static final _FaceAddManualDart faceAddManual = _dylib
      .lookupFunction<_FaceAddManualC, _FaceAddManualDart>(
        'photo_face_add_manual',
      );
  static final _FaceAssignDart faceAssign = _dylib
      .lookupFunction<_FaceAssignC, _FaceAssignDart>('photo_face_assign');
  static final _FaceRemoveDart faceRemove = _dylib
      .lookupFunction<_FaceRemoveC, _FaceRemoveDart>('photo_face_remove');
  static final _WriteFaceXmpDart writeFaceXmp = _dylib
      .lookupFunction<_WriteFaceXmpC, _WriteFaceXmpDart>(
        'photo_asset_write_face_xmp',
      );

  // Manual geotag (§8).
  static final _AssetSetGeoDart assetSetGeo = _dylib
      .lookupFunction<_AssetSetGeoC, _AssetSetGeoDart>('photo_asset_set_geo');
  static final _AssetClearGeoDart assetClearGeo = _dylib
      .lookupFunction<_AssetClearGeoC, _AssetClearGeoDart>(
        'photo_asset_clear_geo',
      );
}
