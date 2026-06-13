// core_api.dart — typed Dart facade over the photo_core C ABI.
//
// During M1 this file hand-writes the FFI bindings for the engine/slot/event
// subset so the Dart side works end-to-end without the ffigen step. In M2,
// when ffigen runs and `bindings_generated.dart` becomes real, this file is
// refactored to delegate to PhotoBindings and only keep the typed wrappers.

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
}
