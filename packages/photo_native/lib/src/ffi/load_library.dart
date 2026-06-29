// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.
//
// load_library.dart — per-platform DynamicLibrary loader.
//
// Per docs/DECISIONS.md §D6: explicit DynamicLibrary.open with per-platform paths.
// `DynamicLibrary.process()` is unreliable on macOS because Flutter plugins
// ship as embedded frameworks and symbols may not be globally visible.
//
// In Pablo's v1 the native (photo_core) C++ sources are compiled directly
// into the photo_native plugin binary (Podspec on macOS, CMake on Windows
// and Linux). So the loader opens the *plugin* binary on production paths,
// with a `libphoto_core.*` fallback for standalone native tests where the
// core is built as its own shared library.

import 'dart:ffi';
import 'dart:io' show Platform;

/// Open the `photo_core` shared library for the current platform.
///
/// Throws [UnsupportedError] on unsupported platforms, [StateError] when no
/// candidate path loads successfully.
DynamicLibrary openPhotoCore() {
  final candidates = _candidatesForPlatform();
  Object? lastErr;
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (e) {
      lastErr = e;
    }
  }
  throw StateError(
    'photo_native: failed to load native library. Tried: '
    '${candidates.join(", ")}. Last error: $lastErr',
  );
}

List<String> _candidatesForPlatform() {
  // Explicit override (absolute path or loader-resolvable name). Lets a dev or
  // the cross-FFI integration test point at a standalone libphoto_core build
  // without relying on DYLD_/LD_LIBRARY_PATH (macOS SIP strips DYLD_* env vars).
  final override = Platform.environment['PHOTO_CORE_LIB'];
  final prefix = (override != null && override.isNotEmpty) ? [override] : const <String>[];
  if (Platform.isMacOS) {
    return [
      ...prefix,
      // Production: photo_core symbols are linked into the Flutter plugin's
      // framework binary. @rpath inside the app bundle resolves to
      'photo_native.framework/photo_native',
      // Standalone native test fallback.
      'libphoto_core.dylib',
    ];
  }
  if (Platform.isWindows) {
    return [...prefix, 'photo_native_plugin.dll', 'photo_core.dll'];
  }
  if (Platform.isLinux) {
    return [...prefix, 'libphoto_native_plugin.so', 'libphoto_core.so'];
  }
  throw UnsupportedError(
    'photo_native is desktop-only (macOS/Windows/Linux); '
    'running on ${Platform.operatingSystem}',
  );
}
