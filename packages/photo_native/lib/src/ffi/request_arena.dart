// request_arena.dart — per-isolate scratch arena for hot-path FFI allocations.
//
// The M2 acceptance gate requires p99 < 50 µs for photo_thumb_request_fast,
// which is incompatible with per-request `calloc<Utf8>` (~10–30 µs each).
// The arena keeps a single resizable buffer that gets reused for every path
// string and event scratch. Calls are not thread-safe by design — one arena
// per isolate.
//
// M1 stubs the surface so M2 can drop in the real wired arena without
// touching call sites.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

final class RequestArena {
  RequestArena({int initialCapacity = 1024})
    : _buffer = calloc<Uint8>(initialCapacity),
      _capacity = initialCapacity;

  Pointer<Uint8> _buffer;
  int _capacity;

  /// Encode [s] as NUL-terminated UTF-8 into the arena and return a pointer
  /// valid until the next call to [utf8] or [dispose].
  Pointer<Utf8> utf8(String s) {
    final bytes = const Utf8Encoder().convert(s);
    final needed = bytes.length + 1;
    if (needed > _capacity) {
      calloc.free(_buffer);
      // Grow with headroom to avoid thrashing.
      _capacity = _nextPow2(needed);
      _buffer = calloc<Uint8>(_capacity);
    }
    final native = _buffer.asTypedList(_capacity);
    native.setRange(0, bytes.length, bytes);
    native[bytes.length] = 0;
    return _buffer.cast<Utf8>();
  }

  void dispose() {
    calloc.free(_buffer);
    _capacity = 0;
  }

  static int _nextPow2(int v) {
    var x = 1;
    while (x < v) {
      x <<= 1;
    }
    return x;
  }
}
