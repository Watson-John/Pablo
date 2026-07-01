// models_dir: env-override + per-platform resolution of the merged models
// dir, and symlink-merging of the bundled face models into it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/models_dir.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('models_dir_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('resolveMergedModelsDir', () {
    test('PABLO_MODELS_DIR env override wins and the dir is created', () {
      final want = '${tmp.path}/custom/models';
      final dir = resolveMergedModelsDir(
          env: {'PABLO_MODELS_DIR': want, 'HOME': tmp.path}, os: 'macos');
      expect(dir.path, want);
      expect(dir.existsSync(), isTrue);
    });

    test('macOS defaults to ~/Library/Application Support/Pablo/models', () {
      final dir = resolveMergedModelsDir(env: {'HOME': tmp.path}, os: 'macos');
      expect(dir.path, '${tmp.path}/Library/Application Support/Pablo/models');
      expect(dir.existsSync(), isTrue);
    });

    test('Linux honors XDG_DATA_HOME', () {
      final dir = resolveMergedModelsDir(
        env: {'HOME': tmp.path, 'XDG_DATA_HOME': '${tmp.path}/xdg'},
        os: 'linux',
      );
      expect(dir.path, '${tmp.path}/xdg/pablo/models');
      expect(dir.existsSync(), isTrue);
    });

    test('Linux falls back to ~/.local/share', () {
      final dir = resolveMergedModelsDir(env: {'HOME': tmp.path}, os: 'linux');
      expect(dir.path, '${tmp.path}/.local/share/pablo/models');
    });

    test('Windows uses APPDATA', () {
      final dir = resolveMergedModelsDir(
          env: {'APPDATA': '${tmp.path}/Roaming'}, os: 'windows');
      expect(dir.path, '${tmp.path}/Roaming/Pablo/models');
      expect(dir.existsSync(), isTrue);
    });
  });

  group('mergeBundledModels', () {
    late Directory bundled;
    late Directory merged;

    setUp(() {
      bundled = Directory('${tmp.path}/bundled')..createSync();
      merged = Directory('${tmp.path}/merged')..createSync();
    });

    test('symlinks each bundled *.onnx and ignores other files', () {
      File('${bundled.path}/a.onnx').writeAsStringSync('AAA');
      File('${bundled.path}/b.onnx').writeAsStringSync('BBB');
      File('${bundled.path}/MANIFEST.md').writeAsStringSync('doc');

      mergeBundledModels(merged, bundled);

      expect(FileSystemEntity.isLinkSync('${merged.path}/a.onnx'), isTrue);
      expect(File('${merged.path}/a.onnx').readAsStringSync(), 'AAA');
      expect(File('${merged.path}/b.onnx').readAsStringSync(), 'BBB');
      expect(File('${merged.path}/MANIFEST.md').existsSync(), isFalse);

      // Idempotent — a second merge leaves everything intact.
      mergeBundledModels(merged, bundled);
      expect(File('${merged.path}/a.onnx').readAsStringSync(), 'AAA');
    });

    test('replaces broken links but leaves real files alone', () {
      File('${bundled.path}/a.onnx').writeAsStringSync('AAA');
      File('${bundled.path}/b.onnx').writeAsStringSync('BUNDLED');
      // A dangling link (bundle moved) and a user-provided real file.
      Link('${merged.path}/a.onnx').createSync('${bundled.path}/missing.onnx');
      File('${merged.path}/b.onnx').writeAsStringSync('LOCAL');

      mergeBundledModels(merged, bundled);

      expect(File('${merged.path}/a.onnx').readAsStringSync(), 'AAA');
      expect(File('${merged.path}/b.onnx').readAsStringSync(), 'LOCAL');
    });

    test('a missing bundled dir is a no-op', () {
      mergeBundledModels(merged, Directory('${tmp.path}/nope'));
      expect(merged.listSync(), isEmpty);
    });
  });
}
