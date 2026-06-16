// library.dart — the real photo library, built from a folder on disk.
//
// This replaces the old mock data layer entirely. Pablo imports a directory
// (the Flickr30k set for the dry run, or any folder the user points at) and
// derives everything shown in the UI from the real filesystem:
//
//   • the gallery photo list (real files, rendered via the native texture seam)
//   • the Folders tree (the actual directory structure under the import root)
//   • the Timeline (grouped by each file's modified date)
//   • per-photo EXIF / size / dimensions (read lazily from the file itself)
//
// People / faces are NOT here — those come from the native face pipeline
// (FaceRepository). Albums don't exist yet. Map locations come from GPS EXIF,
// which the Flickr30k set effectively lacks, so the map is empty by design.
//
// The library is built once in main() and held in [Library.instance]. Widget
// code reaches it through the top-level query shims at the bottom of this file
// (photosFor / photoById / aspectFor / getPhotoExif / getPhotoTags), so the
// call sites stay tiny.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'aspect_store.dart';
import 'models.dart';
import '../utils/exif.dart';
import '../utils/hash.dart';
import '../utils/image_dims.dart';

/// Bumped when [Library.instance] is replaced (e.g. when the background boot
/// scan finishes), so the app can rebuild against the freshly-scanned library.
final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

/// True while the initial background scan is still in flight.
bool libraryScanning = false;

const Set<String> _kImageExts = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};

const List<String> _kMonthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

// Stable per-photo aspect fallback (width / height) for the masonry layout,
// used until real header dimensions are read. Derived from the id hash so a
// tile keeps the same shape across rebuilds.
const List<double> _kAspects = [0.66, 0.75, 0.8, 1.0, 1.0, 1.33, 1.5, 0.7, 1.78, 1.0];

class Library {
  Library({
    required this.root,
    required this.allPhotos,
    required this.byId,
    required this.folderTree,
    required this.folderSections,
    required this.photosByFolder,
    required this.timelineYears,
    required this.timelineMonths,
    required this.photosByTimeline,
  });

  /// Absolute path of the imported root folder ('' for the empty library).
  final String root;

  /// Every imported photo, in stable (path-sorted) order.
  final List<Photo> allPhotos;

  /// id (== file path) → photo.
  final Map<String, Photo> byId;

  /// Top-level folder node(s) — the import root and its subtree. Drives the
  /// sidebar Folders tree.
  final List<FolderNode> folderTree;

  /// Flattened list of folders that directly contain photos (gallery sections).
  final List<FolderNode> folderSections;

  /// folder id (dir path) → photos directly inside it.
  final Map<String, List<Photo>> photosByFolder;

  /// Year nodes (each with month children) for the sidebar Timeline tree.
  final List<TimelineNode> timelineYears;

  /// Flattened month nodes — the Timeline gallery sections.
  final List<TimelineNode> timelineMonths;

  /// timeline node id → photos.
  final Map<String, List<Photo>> photosByTimeline;

  bool get isEmpty => allPhotos.isEmpty;

  /// id of the first folder that contains photos — the app's default selection.
  String? get firstPhotoFolderId =>
      folderSections.isEmpty ? null : folderSections.first.id;

  /// The active library. Replaced by [scan] in main(); empty until then so the
  /// widget tree (and tests that pump it directly) always has something valid.
  static Library instance = Library.empty();

  static Library empty() => Library(
        root: '',
        allPhotos: const [],
        byId: const {},
        folderTree: const [],
        folderSections: const [],
        photosByFolder: const {},
        timelineYears: const [],
        timelineMonths: const [],
        photosByTimeline: const {},
      );

  /// Synchronous walk of [rootPath] — used by tests over small folders. The app
  /// boot path uses [scanAsync] so the first frame isn't blocked.
  static Library scan(String rootPath) {
    final rootDir = Directory(rootPath);
    if (rootPath.isEmpty || !rootDir.existsSync()) return Library.empty();
    final ctx = _ScanCtx(rootDir.absolute.path)..init();
    List<FileSystemEntity> entries;
    try {
      entries = rootDir.listSync(recursive: true, followLinks: false);
    } catch (_) {
      entries = const [];
    }
    for (final e in entries) {
      if (e is! File) continue;
      DateTime? when;
      try {
        when = e.statSync().modified;
      } catch (_) {}
      ctx.addFile(e.path, when);
    }
    return ctx.assemble();
  }

  /// Background walk of [rootPath]: streams the directory listing and stats each
  /// file with `await`, yielding to the event loop between entries so the UI
  /// stays responsive while a large library (tens of thousands of files) is
  /// indexed. Returns the empty library if the path is missing/unreadable.
  static Future<Library> scanAsync(String rootPath) async {
    final rootDir = Directory(rootPath);
    if (rootPath.isEmpty || !await rootDir.exists()) return Library.empty();
    final ctx = _ScanCtx(rootDir.absolute.path)..init();
    try {
      await for (final e in rootDir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        DateTime? when;
        try {
          when = (await e.stat()).modified;
        } catch (_) {}
        ctx.addFile(e.path, when);
      }
    } catch (_) {}
    return ctx.assemble();
  }

  // ── Per-photo metadata (lazy; read straight from the file, then cached) ────

  final Map<String, ExifData> _exifCache = {};

  /// Best-effort EXIF + file facts for the info panel. Dimensions, size and
  /// format always come from the file; camera/date/GPS fields are filled from
  /// EXIF when present (most Flickr30k images have none → those stay null).
  ExifData exifFor(String id) {
    // File metadata is immutable for a session, and the info panel / lightbox
    // re-query it on every rebuild (hover, arrow-key paging…) — cache so the
    // ~320 KB of header/EXIF reads happen at most once per photo.
    final cached = _exifCache[id];
    if (cached != null) return cached;
    final photo = byId[id];
    final path = photo?.filePath ?? id;
    final dims = readImageDimensions(path);
    int sizeBytes = 0;
    DateTime? modified;
    try {
      final st = File(path).statSync();
      sizeBytes = st.size;
      modified = st.modified;
    } catch (_) {}

    final exif = readExif(path);
    final date = exif?.dateTimeOriginal ?? modified;

    String? exposureLabel;
    final exp = exif?.exposureSeconds;
    if (exp != null && exp > 0) {
      // Self-contained label (carries its own 's' unit) so the UI never appends
      // another: "2.0s" for long exposures, "1/250s" for fast ones.
      exposureLabel =
          exp >= 1 ? '${exp.toStringAsFixed(1)}s' : '1/${(1 / exp).round()}s';
    }

    final result = ExifData(
      camera: _joinCamera(exif?.make, exif?.model),
      lens: null,
      aperture: exif?.fNumber != null
          ? 'f/${exif!.fNumber!.toStringAsFixed(1)}'
          : null,
      shutter: exposureLabel,
      iso: exif?.iso,
      focalLength:
          exif?.focalLength != null ? '${exif!.focalLength!.round()}mm' : null,
      dateLabel: date != null ? _dateLabel(date) : null,
      timeLabel: date != null ? _timeLabel(date) : null,
      width: dims?.width ?? 0,
      height: dims?.height ?? 0,
      fileSize: _humanSize(sizeBytes),
      format: _formatOf(path),
      location: (exif?.gpsLat != null && exif?.gpsLon != null)
          ? '${exif!.gpsLat!.toStringAsFixed(5)}, ${exif.gpsLon!.toStringAsFixed(5)}'
          : null,
    );
    _exifCache[id] = result;
    return result;
  }
}

/// Accumulates a scan: one pass over the files (sync or async) feeds [addFile],
/// then [assemble] builds the folder tree, timeline, and indexes once.
class _ScanCtx {
  _ScanCtx(this.absRoot);

  final String absRoot;
  final Map<String, _DirAcc> dirs = {};
  final Map<String, Photo> byId = {};
  final Map<int, Map<int, List<Photo>>> years = {};

  _DirAcc _accFor(String path) => dirs.putIfAbsent(path, () => _DirAcc(path));

  /// Ensure the root exists as a node even if it holds no images directly.
  void init() => _accFor(absRoot);

  void addFile(String path, DateTime? when) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return;
    if (!_kImageExts.contains(path.substring(dot).toLowerCase())) return;

    final name = path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
    final photo = Photo(id: path, label: name, filePath: path);
    byId[path] = photo;

    final dirPath = path.substring(
        0, path.lastIndexOf(Platform.pathSeparator).clamp(0, path.length));
    _accFor(dirPath).photos.add(photo);
    _linkAncestors(dirs, absRoot, dirPath);

    // Timeline bucket by modified date (the most reliable signal this set has;
    // EXIF capture dates exist on only a few percent of files and are read
    // lazily for the info panel instead).
    if (when != null) {
      (years[when.year] ??= <int, List<Photo>>{})
          .putIfAbsent(when.month, () => <Photo>[])
          .add(photo);
    }
  }

  Library assemble() {
    for (final acc in dirs.values) {
      acc.photos.sort((a, b) => a.id.compareTo(b.id));
    }
    final folderTree = _buildFolderTree(dirs, absRoot);
    final folderSections = <FolderNode>[];
    void collect(List<FolderNode> nodes) {
      for (final n in nodes) {
        if (n.count > 0) folderSections.add(n);
        if (n.children.isNotEmpty) collect(n.children);
      }
    }

    collect(folderTree);

    final photosByFolder = <String, List<Photo>>{
      for (final e in dirs.entries) e.key: e.value.photos,
    };

    // allPhotos = concat of the already-sorted per-dir lists (avoids a second
    // O(n log n) sort over what is, for a flat folder, the same ~31k list).
    final allPhotos = <Photo>[];
    final dirKeys = dirs.keys.toList()..sort();
    for (final k in dirKeys) {
      allPhotos.addAll(dirs[k]!.photos);
    }

    final timeline = _buildTimeline(years);

    return Library(
      root: absRoot,
      allPhotos: allPhotos,
      byId: byId,
      folderTree: folderTree,
      folderSections: folderSections,
      photosByFolder: photosByFolder,
      timelineYears: timeline.years,
      timelineMonths: timeline.months,
      photosByTimeline: timeline.photos,
    );
  }
}

// ── Folder tree construction ─────────────────────────────────────────────────

class _DirAcc {
  _DirAcc(this.path);
  final String path;
  final List<Photo> photos = [];
  final Set<String> childDirs = {};
}

/// Register [dirPath] (and each ancestor up to [root]) so the full chain of
/// directories exists in [dirs] and parent→child links are recorded.
void _linkAncestors(Map<String, _DirAcc> dirs, String root, String dirPath) {
  var cur = dirPath;
  while (cur.length >= root.length && cur.contains(Platform.pathSeparator)) {
    dirs.putIfAbsent(cur, () => _DirAcc(cur));
    if (cur == root) break;
    final parent = cur.substring(0, cur.lastIndexOf(Platform.pathSeparator));
    if (parent.isEmpty || parent.length < root.length) break;
    dirs.putIfAbsent(parent, () => _DirAcc(parent)).childDirs.add(cur);
    cur = parent;
  }
}

List<FolderNode> _buildFolderTree(Map<String, _DirAcc> dirs, String root) {
  FolderNode build(String path) {
    final acc = dirs[path];
    final childPaths = (acc?.childDirs.toList() ?? <String>[])
      ..sort();
    final children = [for (final c in childPaths) build(c)];
    final name = path == root
        ? (path.split(Platform.pathSeparator).last)
        : path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
    return FolderNode(
      id: path,
      name: name.isEmpty ? path : name,
      count: acc?.photos.length ?? 0,
      path: _breadcrumb(root, path),
      children: children,
    );
  }

  return [build(root)];
}

String _breadcrumb(String root, String path) {
  if (path == root) return path.split(Platform.pathSeparator).last;
  final rel = path.length > root.length ? path.substring(root.length + 1) : path;
  final rootName = root.split(Platform.pathSeparator).last;
  return '$rootName / ${rel.replaceAll(Platform.pathSeparator, ' / ')}';
}

// ── Timeline construction ────────────────────────────────────────────────────

class _Timeline {
  _Timeline(this.years, this.months, this.photos);
  final List<TimelineNode> years;
  final List<TimelineNode> months;
  final Map<String, List<Photo>> photos;
}

_Timeline _buildTimeline(Map<int, Map<int, List<Photo>>> raw) {
  final years = <TimelineNode>[];
  final months = <TimelineNode>[];
  final photos = <String, List<Photo>>{};

  final sortedYears = raw.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final y in sortedYears) {
    final monthMap = raw[y]!;
    final sortedMonths = monthMap.keys.toList()..sort((a, b) => b.compareTo(a));
    final monthNodes = <TimelineNode>[];
    final yearPhotos = <Photo>[];
    for (final m in sortedMonths) {
      final ps = monthMap[m]!..sort((a, b) => a.id.compareTo(b.id));
      yearPhotos.addAll(ps);
      final id = 'tm$y${m.toString().padLeft(2, '0')}';
      final node = TimelineNode(
        id: id,
        label: '${_kMonthNames[m]} $y',
        count: ps.length,
      );
      monthNodes.add(node);
      months.add(node);
      photos[id] = ps;
    }
    final yearId = 'ty$y';
    years.add(TimelineNode(
      id: yearId,
      label: '$y',
      count: yearPhotos.length,
      children: monthNodes,
    ));
    photos[yearId] = yearPhotos;
  }
  return _Timeline(years, months, photos);
}

// ── Formatting helpers ───────────────────────────────────────────────────────

String? _joinCamera(String? make, String? model) {
  if (make == null && model == null) return null;
  if (make == null) return model;
  if (model == null) return make;
  // Avoid "Canon Canon EOS R5" duplication.
  if (model.toLowerCase().startsWith(make.toLowerCase())) return model;
  return '$make $model';
}

String _humanSize(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

String _formatOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return '—';
  final ext = path.substring(dot + 1).toUpperCase();
  return ext == 'JPG' ? 'JPEG' : ext;
}

const List<String> _kMonAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateLabel(DateTime d) =>
    '${_kMonAbbr[d.month]} ${d.day}, ${d.year}';

String _timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// ── Top-level query shims (stable names used across the widget tree) ──────────

/// Photos for a gallery section id — a folder id (dir path) or a timeline id.
List<Photo> photosFor(String id) =>
    Library.instance.photosByFolder[id] ??
    Library.instance.photosByTimeline[id] ??
    const [];

/// Look up a single photo by its id (== file path).
Photo? photoById(String id) => Library.instance.byId[id];

/// Aspect ratio (width / height) to lay a photo's masonry tile out at: the real
/// header-read ratio when known, else a stable hash-derived fallback.
double aspectFor(Photo p) =>
    AspectStore.instance.aspectOf(p.filePath) ??
    p.aspect ??
    _kAspects[pabloHash(p.id) % _kAspects.length];

/// Best-effort EXIF + file metadata for the info panel.
ExifData getPhotoExif(String id) => Library.instance.exifFor(id);

/// Tags for a photo. The imported library carries none yet, so this is empty —
/// the info panel shows its "No tags" state.
List<String> getPhotoTags(String id) => const [];
