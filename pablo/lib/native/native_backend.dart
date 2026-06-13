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

const bool kUseNativeTextureThumbs = bool.fromEnvironment(
  'PABLO_NATIVE_THUMBS',
  defaultValue: false,
);

class NativeBackend {
  NativeBackend._(this.engine);

  final Engine engine;

  static Future<NativeBackend?> initialize() async {
    if (!kUseNativeTextureThumbs) return null;

    try {
      final tmp = '${Directory.systemTemp.path}/pablo_native_backend';
      final dir = Directory(tmp);
      if (!await dir.exists()) await dir.create(recursive: true);

      final engine = Engine.open(
        EngineConfig(catalogPath: '$tmp/catalog.db', cachePath: '$tmp/cache'),
      );
      if (engine == null) {
        debugPrint('[pablo] Engine.open returned null');
        return null;
      }
      await TextureRegistry.instance.attachEngine(engine);
      debugPrint(
        '[pablo] native backend engine=${Engine.engineVersion} '
        'abi=${Engine.abiVersion} platform=${Platform.operatingSystem}',
      );
      return NativeBackend._(engine);
    } catch (e, st) {
      debugPrint('[pablo] native backend init failed: $e\n$st');
      return null;
    }
  }

  void dispose() => engine.dispose();
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
