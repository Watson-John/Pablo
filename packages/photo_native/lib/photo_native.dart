/// Pablo native backend plugin.
///
/// This package exposes a typed Dart facade over the `photo_core` C ABI,
/// plus the platform-side texture registrar bridge that the gallery uses
/// to present native-decoded frames.
///
/// Invariants:
///   * No image bytes cross the FFI boundary. Pixels live in native memory
///     and reach the screen via Flutter [Texture] widgets.
///   * The main isolate never decodes or blends images.
///   * Every request carries a generation token; stale results are dropped.
library photo_native;

export 'src/ffi/core_api.dart'
    show
        Engine,
        EngineConfig,
        LogLevel,
        Provider,
        FacePerson,
        FaceRow,
        AssetRow,
        GeoPoint,
        Album,
        Organize;
export 'src/ffi/event_pump.dart' show EventPump, PhotoEvent, PhotoEventKind;
export 'src/render/texture_slot.dart' show TextureSlot;
export 'src/render/texture_registry.dart'
    show TextureRegistry, FakeTextureRegistry;
