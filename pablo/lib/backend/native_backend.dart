// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// native_backend.dart — bootstraps the photo_native engine and exposes it to
// the widget tree.
//
// Gated by [BootConfig.nativeThumbs] (on by default): the photo thumbnail
// routes its pixels through a TextureSlot backed by photo_core. Bootstrap
// failures fall back to a neutral loading surface — degraded but not broken.

import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/widgets.dart';
import 'package:photo_native/photo_native.dart';

import '../data/app_config.dart';
import '../data/boot.dart';
import '../data/sources/face_repository.dart';

class NativeBackend {
  NativeBackend._(this.engine, this._pump, this.faces);

  final Engine engine;
  final EventPump _pump;

  /// The People UI's data source over the live engine (face read-back +
  /// confirm/reject/scan/name). Subscribes to native events for `changes`.
  final FaceRepository faces;

  /// Broadcast stream of native events (stage-ready/-failed, import progress…).
  /// Thumbnail surfaces listen for STAGE_READY to learn the decoded frame's
  /// real dimensions so they can cover-fit the texture without distortion.
  Stream<PhotoEvent> get events => _pump.stream;

  static Future<NativeBackend?> initialize(BootConfig config) async {
    if (!config.nativeThumbs) return null;
    final modelsDir = config.modelsDir;

    try {
      // The catalog directory is user-relocatable (Tools → Relocate Library…),
      // persisted in AppConfig; defaults to the legacy temp location.
      final tmp = AppConfig.load().catalogDir;
      final dir = Directory(tmp);
      if (!await dir.exists()) await dir.create(recursive: true);

      final engine = Engine.open(
        EngineConfig(
          catalogPath: '$tmp/catalog.db',
          cachePath: '$tmp/cache',
          modelsPath: modelsDir.isEmpty ? null : modelsDir,
          // 512px thumbnails are 4× the pixels of the old 256px; give the LRU
          // more room so scrolling a large library doesn't thrash the cache.
          memoryBudgetBytes: 512 * 1024 * 1024,
        ),
      );
      if (engine == null) {
        debugPrint('[pablo] Engine.open returned null');
        return null;
      }
      await TextureRegistry.instance.attachEngine(engine);
      // Drain the native event ring so STAGE_READY dimensions reach the UI
      // (and the ring never backs up). Pull-based on a short timer.
      final pump = EventPump(engine)..start();
      final faces = createFaceRepository(engine: engine, events: pump.stream);
      debugPrint(
        '[pablo] native backend engine=${Engine.engineVersion} '
        'abi=${Engine.abiVersion} platform=${Platform.operatingSystem} '
        'models=${modelsDir.isEmpty ? "(none)" : modelsDir}',
      );
      return NativeBackend._(engine, pump, faces);
    } catch (e, st) {
      debugPrint('[pablo] native backend init failed: $e\n$st');
      return null;
    }
  }

  void dispose() {
    if (faces is NativeFaceRepository) {
      (faces as NativeFaceRepository).dispose();
    }
    _pump.dispose();
    engine.dispose();
  }
}

class NativeBackendScope extends InheritedWidget {
  const NativeBackendScope({
    super.key,
    required this.backend,
    required super.child,
  });

  final NativeBackend? backend;

  static NativeBackend? maybeOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<NativeBackendScope>();
    return scope?.backend;
  }

  @override
  bool updateShouldNotify(NativeBackendScope oldWidget) =>
      backend != oldWidget.backend;
}
