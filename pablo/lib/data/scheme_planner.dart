// scheme_planner.dart — turn a batch of source photos + a scheme into a concrete
// filing plan: each source's final relative destination path, with name
// collisions resolved per the scheme's suffix options. This is where the
// engine's "what a photo wants to be named" becomes "what it will actually be
// named once siblings and existing files are accounted for".
//
// Pure given an injected [destExists] predicate, so it is fully unit-testable
// without a filesystem. The ingest/reorganize executors (Phase B) call this to
// build a dry-run plan, then apply it with file_ops.

import 'scheme_engine.dart';
import 'scheme_options.dart';
import 'storage_scheme.dart';

/// One source photo to be filed.
class SourcePhoto {
  const SourcePhoto(this.sourcePath, this.meta);
  final String sourcePath;
  final PhotoMeta meta;
}

/// One planned move/copy: [sourcePath] → [relPath] under the destination root.
class FilingEntry {
  const FilingEntry({
    required this.sourcePath,
    required this.folderSegments,
    required this.filename,
    required this.ext,
  });

  final String sourcePath;
  final List<String> folderSegments;
  final String filename;
  final String ext;

  /// Destination path relative to the library/destination root.
  String get relPath => [...folderSegments, '$filename$ext'].join('/');
}

class FilingPlan {
  const FilingPlan(this.entries);
  final List<FilingEntry> entries;
}

/// Plan how [sources] file under [scheme]. [destExists] reports whether a
/// relative path is already occupied at the destination (default: nothing
/// exists — useful for tests and empty targets).
FilingPlan planFiling(
  StorageScheme scheme,
  List<SourcePhoto> sources, {
  bool Function(String relPath) destExists = _never,
  RunPrompts prompts = const RunPrompts({}),
}) {
  final counter = CounterState(scheme.options.counterBase);
  final suffix = scheme.options.suffix;
  final taken = <String>{}; // claim keys for paths chosen by this batch
  final entries = <FilingEntry>[];

  for (final src in sources) {
    final r = renderScheme(scheme, src.meta, counter, prompts);
    final folderPrefix =
        r.folderSegments.isEmpty ? '' : '${r.folderSegments.join('/')}/';

    // A name "clashes" if its claim key is taken by this batch or its concrete
    // path already exists at the destination. With ignoreExtensionOnClash the
    // claim key drops the extension, so a.jpg and a.png are treated as the same.
    String claimKey(String name) => suffix.ignoreExtensionOnClash
        ? '$folderPrefix$name'
        : '$folderPrefix$name${r.ext}';
    bool clashes(String name) =>
        taken.contains(claimKey(name)) ||
        destExists('$folderPrefix$name${r.ext}');

    var name = r.filename;
    if (suffix.alwaysApply) {
      var n = 1;
      name = _withSuffix(r.filename, suffix, n);
      while (clashes(name)) {
        n++;
        name = _withSuffix(r.filename, suffix, n);
      }
    } else if (clashes(name)) {
      var n = 1;
      name = _withSuffix(r.filename, suffix, n);
      while (clashes(name)) {
        n++;
        name = _withSuffix(r.filename, suffix, n);
      }
    }

    taken.add(claimKey(name));
    entries.add(FilingEntry(
      sourcePath: src.sourcePath,
      folderSegments: r.folderSegments,
      filename: name,
      ext: r.ext,
    ));
  }

  return FilingPlan(entries);
}

String _withSuffix(String base, Suffix s, int n) =>
    '$base${s.separator}${n.toString().padLeft(s.minDigits, '0')}';

bool _never(String _) => false;
