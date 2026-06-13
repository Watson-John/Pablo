// texture_slot.dart — Dart-side handle to a native render slot + Flutter texture.
//
// One TextureSlot pairs:
//   * a native slot ID (owned by photo_core)
//   * a stable Flutter texture ID (registered by the platform plugin)
//
// Per DECISIONS.md §D7: the texture registration lives for the slot's
// lifetime. Stage upgrades swap the underlying native frame; the texture ID
// never changes. M1 wires the lifecycle; the per-platform texture bridges
// (M1e) supply the texture IDs via texture_registry.dart.

import 'package:flutter/widgets.dart';

import '../ffi/core_api.dart';
import 'texture_registry.dart';

final class TextureSlot {
  TextureSlot._({
    required this.engine,
    required this.slotId,
    required this.textureId,
    required int initialW,
    required int initialH,
  }) : _generation = 0;

  final Engine engine;
  final int slotId;
  final int textureId;
  int _generation;

  /// Create both a native slot and a Flutter texture registration paired to
  /// it. Pass to a [Texture] widget via [textureId].
  static Future<TextureSlot> create(
    Engine engine, {
    required int initialW,
    required int initialH,
  }) async {
    final slotId = engine.createSlot(initialW: initialW, initialH: initialH);
    if (slotId == 0) {
      throw StateError('failed to create native slot');
    }
    final textureId = await TextureRegistry.instance.register(slotId);
    return TextureSlot._(
      engine: engine,
      slotId: slotId,
      textureId: textureId,
      initialW: initialW,
      initialH: initialH,
    );
  }

  /// Rebind to a new asset. Bumps the slot's generation so any in-flight
  /// stale decode does not present.
  int rebind() {
    _generation += 1;
    engine.bindGeneration(slotId, _generation);
    return _generation;
  }

  int get currentGeneration => _generation;

  Future<void> dispose() async {
    await TextureRegistry.instance.unregister(slotId);
    engine.destroySlot(slotId);
  }
}
