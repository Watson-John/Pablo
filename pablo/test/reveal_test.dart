// reveal_test.dart — "Show on Disk" builds the exact per-OS invocation
// (including Explorer's /select, comma syntax and dbus URI encoding) and the
// Linux path falls back to xdg-open; Copy Path lands newline-joined text on
// the clipboard. No processes are spawned — the runner seam records argv.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/utils/reveal_in_file_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('revealCommandFor', () {
    test('macOS selects the file, opens a directory', () {
      expect(revealCommandFor('/pics/a.jpg', os: 'macos'),
          ['open', '-R', '/pics/a.jpg']);
      expect(revealCommandFor('/pics', os: 'macos', isDirectory: true),
          ['open', '/pics']);
    });

    test(r'Windows uses explorer /select,<path> as ONE argument', () {
      expect(revealCommandFor(r'C:\pics\a.jpg', os: 'windows'),
          ['explorer', r'/select,C:\pics\a.jpg']);
      expect(revealCommandFor(r'C:\pics', os: 'windows', isDirectory: true),
          ['explorer', r'C:\pics']);
    });

    test('Linux calls FileManager1 ShowItems/ShowFolders with a file URI', () {
      final cmd = revealCommandFor('/pics/a.jpg', os: 'linux');
      expect(cmd.first, 'dbus-send');
      expect(cmd, contains('org.freedesktop.FileManager1.ShowItems'));
      expect(cmd, contains('array:string:file:///pics/a.jpg'));
      final dir =
          revealCommandFor('/pics', os: 'linux', isDirectory: true);
      expect(dir, contains('org.freedesktop.FileManager1.ShowFolders'));
    });

    test('dbus URIs percent-encode spaces and unicode', () {
      final cmd = revealCommandFor('/my pics/déjà vu.jpg', os: 'linux');
      final uriArg = cmd.firstWhere((a) => a.startsWith('array:string:'));
      expect(uriArg, isNot(contains(' ')));
      expect(uriArg, contains('%20'));
      expect(Uri.parse(uriArg.substring('array:string:'.length)).toFilePath(),
          '/my pics/déjà vu.jpg');
    });
  });

  group('revealInFileManager (recorded runner)', () {
    final calls = <List<String>>[];
    late RevealRunner original;

    setUp(() {
      calls.clear();
      original = revealRunner;
    });
    tearDown(() => revealRunner = original);

    void install({required int exitCode, Set<String>? failing}) {
      revealRunner = (exe, args) async {
        calls.add([exe, ...args]);
        final code = (failing?.contains(exe) ?? false) ? 1 : exitCode;
        return ProcessResult(0, code, '', '');
      };
    }

    test('macOS success runs exactly one open -R', () async {
      install(exitCode: 0);
      expect(await revealInFileManager('/pics/a.jpg', os: 'macos'), isTrue);
      expect(calls, [
        ['open', '-R', '/pics/a.jpg']
      ]);
    });

    test('Windows counts a spawn as success despite nonzero exit', () async {
      install(exitCode: 1);
      expect(await revealInFileManager(r'C:\pics\a.jpg', os: 'windows'), isTrue);
      expect(calls.single.first, 'explorer');
    });

    test('Linux falls back to xdg-open on the parent when dbus fails',
        () async {
      install(exitCode: 0, failing: {'dbus-send'});
      expect(await revealInFileManager('/pics/a.jpg', os: 'linux'), isTrue);
      expect(calls.length, 2);
      expect(calls[0].first, 'dbus-send');
      expect(calls[1], ['xdg-open', '/pics']);
    });

    test('macOS nonzero exit reports failure (no silent success)', () async {
      install(exitCode: 1);
      expect(await revealInFileManager('/pics/a.jpg', os: 'macos'), isFalse);
    });
  });

  test('revealActionLabel is platform-worded', () {
    expect(revealActionLabel(os: 'macos'), 'Reveal in Finder');
    expect(revealActionLabel(os: 'windows'), 'Show in Explorer');
    expect(revealActionLabel(os: 'linux'), 'Show in File Manager');
  });

  test('copyPathsToClipboard joins multi-selection with newlines', () async {
    final messenger =
        TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    Object? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments;
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await copyPathsToClipboard(['/a/1.jpg', '/b/2.jpg']);
    expect((copied as Map)['text'], '/a/1.jpg\n/b/2.jpg');
  });
}
