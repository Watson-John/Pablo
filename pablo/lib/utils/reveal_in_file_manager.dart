// reveal_in_file_manager.dart — "Show on Disk": open the OS file manager with
// a file selected (or a folder opened). dart:io Process only — no plugin dep.
//
//   macOS    open -R <file>            / open <dir>
//   Windows  explorer /select,<file>   / explorer <dir>
//   Linux    org.freedesktop.FileManager1 ShowItems/ShowFolders over dbus
//            (URI-encoded), falling back to xdg-open on the parent directory
//            when no FileManager1 implementation is around.
//
// The argv builder is pure ([revealCommandFor]) and the process spawn is an
// injectable seam ([revealRunner]) so tests assert exact commands without
// launching anything.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Injectable process seam (tests record argv instead of spawning).
typedef RevealRunner = Future<ProcessResult> Function(
    String executable, List<String> args);

RevealRunner revealRunner = (exe, args) => Process.run(exe, args);

/// Platform-appropriate menu label for the action.
String revealActionLabel({String? os}) {
  switch (os ?? Platform.operatingSystem) {
    case 'macos':
      return 'Reveal in Finder';
    case 'windows':
      return 'Show in Explorer';
    default:
      return 'Show in File Manager';
  }
}

/// `file://` URI with percent-encoding (space/unicode-safe) for dbus.
String fileUriFor(String path) => Uri.file(path).toString();

/// The exact (executable + args) invocation that reveals [path] on [os].
/// Files are selected in their parent window; a directory ([isDirectory])
/// opens as a window of its own contents.
List<String> revealCommandFor(String path,
    {required String os, bool isDirectory = false}) {
  switch (os) {
    case 'macos':
      return isDirectory ? ['open', path] : ['open', '-R', path];
    case 'windows':
      // Explorer's select syntax is one comma-joined argument. Process.run
      // passes argv directly (no shell), so no quoting is needed.
      return isDirectory ? ['explorer', path] : ['explorer', '/select,$path'];
    default:
      final method = isDirectory ? 'ShowFolders' : 'ShowItems';
      return [
        'dbus-send',
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.FileManager1',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.$method',
        'array:string:${fileUriFor(path)}',
        'string:',
      ];
  }
}

/// Open the OS file manager at [path]. Returns whether a launch succeeded —
/// callers may surface a snackbar on false, but silence is acceptable too.
/// [os] is injectable for tests; defaults to the host platform.
Future<bool> revealInFileManager(String path,
    {bool isDirectory = false, String? os}) async {
  os ??= Platform.operatingSystem;
  final cmd = revealCommandFor(path, os: os, isDirectory: isDirectory);
  try {
    final r = await revealRunner(cmd.first, cmd.sublist(1));
    // Explorer routinely exits nonzero even when the window opened — a
    // successful spawn is the best signal Windows gives us.
    if (os == 'windows') return true;
    if (r.exitCode == 0) return true;
  } catch (e) {
    debugPrint('[reveal] $path: $e');
  }
  if (os == 'linux') return _xdgOpenFallback(path, isDirectory: isDirectory);
  return false;
}

/// No FileManager1 on the bus (or dbus-send missing): open the directory
/// itself without selection — still lands the user next to the file.
Future<bool> _xdgOpenFallback(String path, {required bool isDirectory}) async {
  try {
    final dir = isDirectory ? path : File(path).parent.path;
    final r = await revealRunner('xdg-open', [dir]);
    return r.exitCode == 0;
  } catch (e) {
    debugPrint('[reveal] xdg-open fallback: $e');
    return false;
  }
}

/// Copy [paths] to the system clipboard, newline-joined (multi-selection
/// pastes as one path per line).
Future<void> copyPathsToClipboard(List<String> paths) =>
    Clipboard.setData(ClipboardData(text: paths.join('\n')));
