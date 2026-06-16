// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// native_backend.dart — bootstraps the photo_native engine and exposes it to
// the widget tree.
//
// Gated by [kUseNativeTextureThumbs]: when false (default), the rest of the
// app behaves exactly as the M0 mockup and the engine is not initialized.
// When true, the photo thumbnail routes its pixels through a TextureSlot
// backed by photo_core. Bootstrap failures fall back to the gradient
// mockup — degraded but not broken.

import 'dart:async';
import 'dart:io' show Directory, Platform;

import 'package:flutter/widgets.dart';
import 'package:photo_native/photo_native.dart';

import '../data/sources/face_repository.dart';

const bool kUseNativeTextureThumbs = bool.fromEnvironment(
  'PABLO_NATIVE_THUMBS',
  defaultValue: false,
);

/// Directory holding the face ONNX models (scrfd_10g.onnx, auraface.onnx).
/// Empty (the default) leaves modelsPath null → face scans report unavailable.
const String kModelsDir = String.fromEnvironment(
  'PABLO_MODELS_DIR',
  defaultValue: '',
);

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

  static Future<NativeBackend?> initialize() async {
    if (!kUseNativeTextureThumbs) return null;

    try {
      final tmp = '${Directory.systemTemp.path}/pablo_native_backend';
      final dir = Directory(tmp);
      if (!await dir.exists()) await dir.create(recursive: true);

      final engine = Engine.open(
        EngineConfig(
          catalogPath: '$tmp/catalog.db',
          cachePath: '$tmp/cache',
          modelsPath: kModelsDir.isEmpty ? null : kModelsDir,
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
        'models=${kModelsDir.isEmpty ? "(none)" : kModelsDir}',
      );
      return NativeBackend._(engine, pump, faces);
    } catch (e, st) {
      debugPrint('[pablo] native backend init failed: $e\n$st');
      return null;
    }
  }

  void dispose() {
    if (faces is NativeFaceRepository) (faces as NativeFaceRepository).dispose();
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
