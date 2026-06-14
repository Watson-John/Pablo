// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// scroll_harness — M1 acceptance harness for the photo_native texture
// pipeline. Renders a virtualized grid of TextureSlot-backed cells. Each
// cell publishes a solid color via the test publish hook and rebinds when
// recycled to a different asset, exercising the generation token.
//
// Validates:
//   * No black frames during sustained scroll.
//   * No wrong-tile colors (generation-token correctness).
//   * No texture handle leaks (RSS stable over time).
//
// Run:
//   cd tools/scroll_harness
//   flutter run -d macos     # or -d windows / -d linux

import 'dart:async';
// Hide dart:ffi's `Size` so it doesn't shadow Flutter's Material Size.
import 'dart:ffi' hide Size;
import 'dart:io' show Directory, Platform;

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';
// The harness reaches into the plugin's internals to access nativeHandle
// and the test-only publish hook. Public surface lands in M2.
// ignore_for_file: implementation_imports
import 'package:photo_native/src/ffi/load_library.dart';
import 'package:photo_native/src/render/texture_registry.dart';

typedef _PublishSolidC = Void Function(
    Pointer<Void>, Uint64, Uint8, Uint8, Uint8, Uint8);
typedef _PublishSolidDart = void Function(
    Pointer<Void>, int, int, int, int, int);

void main() {
  runApp(const ScrollHarnessApp());
}

class ScrollHarnessApp extends StatelessWidget {
  const ScrollHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pablo M1 scroll harness',
      theme: ThemeData.dark(),
      home: const HarnessHome(),
    );
  }
}

class HarnessHome extends StatefulWidget {
  const HarnessHome({super.key});

  @override
  State<HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<HarnessHome> {
  Engine? _engine;
  _PublishSolidDart? _publishSolid;
  String _status = 'initializing…';

  // 10 000 logical assets, fixed pseudo-random colors per id.
  static const int _assetCount = 10000;
  static const int _columns = 10;

  late final List<Color> _assetColors = List<Color>.generate(_assetCount, (i) {
    final h = (i * 137) % 360;
    return HSVColor.fromAHSV(1.0, h.toDouble(), 0.65, 0.85).toColor();
  });

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final dylib = openPhotoCore();
      _publishSolid = dylib.lookupFunction<_PublishSolidC, _PublishSolidDart>(
        'photo_test_publish_solid',
      );

      final tmp = '${Directory.systemTemp.path}/pablo_scroll_harness';
      final dir = Directory(tmp);
      if (!await dir.exists()) await dir.create(recursive: true);

      final eng = Engine.open(EngineConfig(
        catalogPath: '$tmp/catalog.db',
        cachePath: '$tmp/cache',
      ));
      if (eng == null) throw StateError('Engine.open returned null');

      await TextureRegistry.instance.attachEngine(eng);

      setState(() {
        _engine = eng;
        _status = 'engine ${Engine.engineVersion}  abi=${Engine.abiVersion}  '
            '${Platform.operatingSystem}  $_assetCount assets';
      });
    } catch (e, st) {
      setState(() => _status = 'init failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eng = _engine;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pablo M1 scroll harness'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Text(_status, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ),
      body: eng == null
          ? const Center(child: CircularProgressIndicator())
          : _GridBody(
              engine: eng,
              publishSolid: _publishSolid!,
              assetColors: _assetColors,
              columns: _columns,
            ),
    );
  }
}

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.engine,
    required this.publishSolid,
    required this.assetColors,
    required this.columns,
  });

  final Engine engine;
  final _PublishSolidDart publishSolid;
  final List<Color> assetColors;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: assetColors.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        return _TextureCell(
          engine: engine,
          publishSolid: publishSolid,
          assetId: index,
          color: assetColors[index],
        );
      },
    );
  }
}

class _TextureCell extends StatefulWidget {
  const _TextureCell({
    required this.engine,
    required this.publishSolid,
    required this.assetId,
    required this.color,
  });

  final Engine engine;
  final _PublishSolidDart publishSolid;
  final int assetId;
  final Color color;

  @override
  State<_TextureCell> createState() => _TextureCellState();
}

class _TextureCellState extends State<_TextureCell> {
  TextureSlot? _slot;
  int? _boundAssetId;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    final slot = await TextureSlot.create(
      widget.engine,
      initialW: 64,
      initialH: 64,
    );
    if (_disposed) {
      await slot.dispose();
      return;
    }
    setState(() => _slot = slot);
    _publishForCurrentAsset();
  }

  @override
  void didUpdateWidget(covariant _TextureCell old) {
    super.didUpdateWidget(old);
    if (_slot != null && old.assetId != widget.assetId) {
      _slot!.rebind();
      _publishForCurrentAsset();
    }
  }

  void _publishForCurrentAsset() {
    final slot = _slot;
    if (slot == null) return;
    if (_boundAssetId == widget.assetId) return;
    final c = widget.color;
    int b(double channel) => (channel * 255.0).round().clamp(0, 255);
    widget.publishSolid(
      Pointer<Void>.fromAddress(widget.engine.nativeHandle),
      slot.slotId,
      b(c.r),
      b(c.g),
      b(c.b),
      b(c.a),
    );
    _boundAssetId = widget.assetId;
  }

  @override
  void dispose() {
    _disposed = true;
    _slot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slot;
    if (slot == null) {
      return Container(color: Colors.grey.shade900);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Texture(textureId: slot.textureId),
    );
  }
}
