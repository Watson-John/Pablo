// Real exact-duplicate detection in pure Dart — the cheap "hash-only" pass that
// runs on import. Byte-identical files are grouped by (size, content hash):
// size is a free stat-based pre-filter, so we only read+hash files that could
// possibly match. No Flutter imports, so it runs inside Isolate.run().
//
// Near-duplicate (visual) detection is NOT done here — that needs SSCD and lives
// in the native DedupService.

import 'dart:io';

/// A file to consider: its app photo id and absolute path.
typedef ScanFile = ({String id, String path});

/// Group byte-identical files. Returns one list of photo ids per duplicate
/// group (size > 1); unique files are omitted. Safe to call in an isolate.
List<List<String>> findExactGroups(List<ScanFile> files) {
  // 1) Bucket by file size (a free pre-filter — different sizes can't match).
  final bySize = <int, List<ScanFile>>{};
  for (final f in files) {
    final int len;
    try {
      len = File(f.path).lengthSync();
    } catch (_) {
      continue; // unreadable / missing — skip
    }
    (bySize[len] ??= []).add(f);
  }

  // 2) Within each same-size bucket, hash contents and group equal hashes.
  final groups = <List<String>>[];
  bySize.forEach((_, bucket) {
    if (bucket.length < 2) return;
    final byHash = <int, List<String>>{};
    for (final f in bucket) {
      final h = _hashFile(f.path);
      if (h == null) continue;
      (byHash[h] ??= []).add(f.id);
    }
    for (final ids in byHash.values) {
      if (ids.length > 1) groups.add(ids);
    }
  });
  return groups;
}

/// FNV-1a 64-bit over the file's bytes. Dart VM ints are 64-bit and wrap, so the
/// multiply is implicitly mod 2^64. Combined with the size bucket, collisions
/// are negligible for a personal library. Returns null on read failure.
int? _hashFile(String path) {
  const int prime = 0x100000001b3;
  try {
    final bytes = File(path).readAsBytesSync();
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h *= prime;
    }
    return h;
  } catch (_) {
    return null;
  }
}
