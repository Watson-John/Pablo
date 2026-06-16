// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// texture_registry.dart — MethodChannel bridge to the per-platform plugin's
// texture registrar. The plugin maps native slot IDs to Flutter texture IDs
// 1:1; this Dart side just shuttles attach/register/unregister calls and
// stores no other state.
//
// MethodChannel API (see macos/Classes, windows/, linux/):
//   - `attachEngine`(engineHandle: int)     -> void
//   - `register`(slotId: int)               -> textureId: int
//   - `unregister`(slotId: int)             -> void
//   - `markFrameAvailable`(slotId: int)     -> void
//
// `attachEngine` must be called once, before any `register`. It hands the
// plugin the native engine pointer so the plugin's texture callback can call
// photo_slot_acquire_latest from the render thread.
//
// `markFrameAvailable` tells the embedder a new native frame has been published
// for the slot, so it re-pulls `copyPixelBuffer`. Without it the embedder only
// re-copies when the Texture widget's layout changes — so a stage upgrade that
// keeps the same frame dimensions (or a same-size re-decode) would leave a
// stale, lower-resolution frame on screen until the next relayout.

import 'package:flutter/services.dart';

import '../ffi/core_api.dart';

abstract class TextureRegistry {
  static TextureRegistry instance = _ChannelTextureRegistry();

  /// Hand the plugin the native engine pointer. Must be called once after
  /// [Engine.open] and before any [register].
  Future<void> attachEngine(Engine engine);

  /// Register a Flutter texture paired to the native [slotId]. Returns the
  /// Flutter texture ID. Stable for the slot's lifetime.
  Future<int> register(int slotId);

  /// Unregister the Flutter texture paired to [slotId]. Idempotent.
  Future<void> unregister(int slotId);

  /// Notify the embedder that a new native frame is ready for [slotId], so it
  /// re-pulls the slot's pixel buffer. Fire-and-forget; a no-op if the slot has
  /// no registered texture.
  Future<void> markFrameAvailable(int slotId);
}

class _ChannelTextureRegistry implements TextureRegistry {
  static const MethodChannel _channel = MethodChannel(
    'photo_native/texture_registry',
  );

  bool _attached = false;

  @override
  Future<void> attachEngine(Engine engine) async {
    await _channel.invokeMethod<void>('attachEngine', {
      'engineHandle': engine.nativeHandle,
    });
    _attached = true;
  }

  @override
  Future<int> register(int slotId) async {
    if (!_attached) {
      throw StateError(
        'photo_native: TextureRegistry.attachEngine must be called before register',
      );
    }
    final result = await _channel.invokeMethod<int>('register', {
      'slotId': slotId,
    });
    if (result == null) {
      throw StateError('photo_native: register returned null for slot $slotId');
    }
    return result;
  }

  @override
  Future<void> unregister(int slotId) async {
    await _channel.invokeMethod<void>('unregister', {'slotId': slotId});
  }

  @override
  Future<void> markFrameAvailable(int slotId) async {
    await _channel.invokeMethod<void>('markFrameAvailable', {'slotId': slotId});
  }
}

/// In-memory registry useful for tests before the platform bridges are
/// available or to mock the plugin in widget tests.
final class FakeTextureRegistry implements TextureRegistry {
  int _nextTextureId = 1;
  final Map<int, int> _slotToTexture = {};
  bool _attached = false;

  @override
  Future<void> attachEngine(Engine engine) async {
    _attached = true;
  }

  @override
  Future<int> register(int slotId) async {
    if (!_attached) {
      throw StateError('FakeTextureRegistry: attachEngine not called');
    }
    final tid = _nextTextureId++;
    _slotToTexture[slotId] = tid;
    return tid;
  }

  @override
  Future<void> unregister(int slotId) async {
    _slotToTexture.remove(slotId);
  }

  @override
  Future<void> markFrameAvailable(int slotId) async {}
}
