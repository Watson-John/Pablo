// scheme_preview_tree.dart — the live preview. Runs the scheme engine over a
// few real photos (or synthetic samples when the library is empty) and renders
// the resulting hierarchy as a tree. Reinforces the two-stage split: the folder
// path is the muted tree, the file name is the highlighted (azure) leaf.

import 'dart:io';

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/scheme_engine.dart';
import '../../data/storage_scheme.dart';
import '../../theme/tokens.dart';
import '../../utils/exif.dart';

class SchemePreviewTree extends StatefulWidget {
  const SchemePreviewTree({required this.scheme, this.samples, super.key});

  final StorageScheme scheme;

  /// Injectable sample metadata (tests). Null → read from [Library.instance].
  final List<PhotoMeta>? samples;

  @override
  State<SchemePreviewTree> createState() => _SchemePreviewTreeState();
}

class _SchemePreviewTreeState extends State<SchemePreviewTree> {
  late final List<PhotoMeta> _samples = widget.samples ?? _gatherSamples();
  late final bool _synthetic =
      widget.samples == null && Library.instance.allPhotos.isEmpty;

  @override
  Widget build(BuildContext context) {
    final root = _buildTree();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PabloSpacing.xl),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview', style: PabloTypography.sectionLabelUpper),
          Text(
            _synthetic
                ? 'Using sample photos'
                : 'Using ${_samples.length} photos from your library',
            style: PabloTypography.caption,
          ),
          const SizedBox(height: PabloSpacing.lg),
          ..._renderNode(root, 0),
        ],
      ),
    );
  }

  // ── tree model ──
  List<Widget> _renderNode(_Node node, int depth) {
    final rows = <Widget>[];
    final dirNames = node.dirs.keys.toList()..sort();
    for (final name in dirNames) {
      rows.add(_folderRow(name, depth));
      rows.addAll(_renderNode(node.dirs[name]!, depth + 1));
    }
    final files = node.files.toList()..sort();
    for (final f in files) {
      rows.add(_fileRow(f, depth));
    }
    return rows;
  }

  _Node _buildTree() {
    final root = _Node();
    final counter = CounterState(widget.scheme.options.counterBase);
    const prompts = RunPrompts({'event': 'Event'});
    for (final m in _samples) {
      final r = renderScheme(widget.scheme, m, counter, prompts);
      var node = root;
      for (final seg in r.folderSegments) {
        node = node.dirs.putIfAbsent(seg, _Node.new);
      }
      node.files.add('${r.filename}${r.ext}');
    }
    return root;
  }

  Widget _folderRow(String name, int depth) => Padding(
        padding: EdgeInsets.only(
            left: depth * 18.0, top: 1, bottom: 1),
        child: Row(
          children: [
            const PabloIcon(PabloIconName.folder,
                size: 14, color: PabloColors.iconFolderBody),
            const SizedBox(width: PabloSpacing.sm),
            Text(
              name,
              style: PabloTypography.sans(
                  fontSize: 12.5, color: PabloColors.textSecondary),
            ),
          ],
        ),
      );

  Widget _fileRow(String name, int depth) => Padding(
        padding: EdgeInsets.only(left: depth * 18.0 + 2, top: 1, bottom: 1),
        child: Text(
          name,
          style: PabloTypography.mono(
            fontSize: 12,
            color: PabloColors.accentActive,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  // ── samples ──
  List<PhotoMeta> _gatherSamples() {
    final photos = Library.instance.allPhotos;
    if (photos.isEmpty) return _syntheticSamples();
    final n = photos.length < 5 ? photos.length : 5;
    return [for (var i = 0; i < n; i++) photoMetaForPath(photos[i].filePath)];
  }
}

class _Node {
  final Map<String, _Node> dirs = {};
  final List<String> files = [];
}

/// Build [PhotoMeta] for a real file: filesystem mtime + best-effort EXIF.
PhotoMeta photoMetaForPath(String path) {
  DateTime mtime;
  try {
    mtime = File(path).statSync().modified;
  } catch (_) {
    mtime = DateTime(2024);
  }
  final exif = readExif(path);
  final parts = path.split(RegExp(r'[\\/]'))..removeWhere((e) => e.isEmpty);
  final base = parts.isEmpty ? path : parts.last;
  final dot = base.lastIndexOf('.');
  final name = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot).toLowerCase() : '.jpg';
  final parents = parts.length >= 2
      ? parts.sublist(0, parts.length - 1).reversed.toList()
      : <String>[];
  return PhotoMeta(
    fileMtime: mtime,
    captureDate: exif?.dateTimeOriginal,
    originalName: name,
    ext: ext,
    make: exif?.make,
    model: exif?.model,
    parentDirs: parents,
  );
}

List<PhotoMeta> _syntheticSamples() => [
      PhotoMeta(
        fileMtime: DateTime(2024, 3, 15, 14, 30),
        captureDate: DateTime(2024, 3, 15, 14, 30),
        originalName: 'IMG_1024',
        ext: '.jpg',
        make: 'Canon',
        model: 'EOS R5',
        parentDirs: const ['Trip'],
      ),
      PhotoMeta(
        fileMtime: DateTime(2024, 3, 16, 9, 5),
        captureDate: DateTime(2024, 3, 16, 9, 5),
        originalName: 'IMG_1025',
        ext: '.jpg',
        make: 'Sony',
        model: 'A7 IV',
        parentDirs: const ['Trip'],
      ),
      PhotoMeta(
        fileMtime: DateTime(2023, 12, 31, 23, 50),
        captureDate: DateTime(2023, 12, 31, 23, 50),
        originalName: 'IMG_0001',
        ext: '.jpg',
        make: 'Apple',
        model: 'iPhone 15',
        parentDirs: const ['Party'],
      ),
    ];
