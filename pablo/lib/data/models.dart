// Data models for Pablo.
//
// Every Photo is a real file on disk imported from the user's library. Pixels
// reach the screen through the native libvips → GPU-texture pipeline keyed by
// [Photo.filePath]; no synthetic/gradient placeholders exist.

class Person {
  const Person({
    required this.id,
    required this.name,
    required this.count,
    required this.lastDate,
    required this.hue,
    this.confirmed = true,
  });

  final String id;
  final String name;
  final int count;
  final String lastDate;
  final int hue;
  final bool confirmed;

  Person copyWith({String? name, int? hue, bool? confirmed}) => Person(
        id: id,
        name: name ?? this.name,
        count: count,
        lastDate: lastDate,
        hue: hue ?? this.hue,
        confirmed: confirmed ?? this.confirmed,
      );
}

class FolderNode {
  const FolderNode({
    required this.id,
    required this.name,
    this.count = 0,
    this.date = '',
    this.path = '',
    this.children = const [],
  });

  final String id;
  final String name;
  final int count;
  final String date;
  final String path;
  final List<FolderNode> children;

  bool get isGroup => children.isNotEmpty;
}

class TimelineNode {
  const TimelineNode({
    required this.id,
    required this.label,
    this.count = 0,
    this.children = const [],
  });

  final String id;
  final String label;
  final int count;
  final List<TimelineNode> children;

  bool get isLeaf => children.isEmpty;
}

class UnnamedFace {
  const UnnamedFace({required this.id, required this.hue, required this.count});
  final String id;
  final int hue;
  final int count;
}

class Photo {
  const Photo({
    required this.id,
    required this.label,
    required this.filePath,
    this.starred = false,
    this.aspect,
    this.modified,
    this.sizeBytes = 0,
  });

  final String id;
  final String label;

  /// Absolute path to the real image file on disk. PhotoThumb routes this to
  /// the native libvips decoder via the TextureSlot seam.
  final String filePath;

  final bool starred;

  /// True aspect ratio (width / height) when known (read from the file
  /// header). Null at import time — the masonry layout then falls back to a
  /// stable hash-derived ratio until real dimensions are read.
  final double? aspect;

  /// File modified time, captured during the scan's `stat()`. Drives the
  /// gallery's "Sort by Date". Null when the stat failed.
  final DateTime? modified;

  /// File size in bytes, captured during the scan's `stat()`. Drives the
  /// gallery's "Sort by Size". 0 when unknown.
  final int sizeBytes;
}

/// EXIF / file metadata for one photo. Fields that the file doesn't carry are
/// null (most Flickr30k images, e.g., have no camera/date/GPS) and the UI shows
/// an em-dash. [width]/[height] are 0 when the header can't be read; [fileSize]
/// and [format] are always best-effort from the file itself.
class ExifData {
  const ExifData({
    this.camera,
    this.lens,
    this.aperture,
    this.shutter,
    this.iso,
    this.focalLength,
    this.dateLabel,
    this.timeLabel,
    required this.width,
    required this.height,
    required this.fileSize,
    required this.format,
    this.location,
  });

  final String? camera;
  final String? lens;
  final String? aperture;
  final String? shutter;
  final int? iso;
  final String? focalLength;
  final String? dateLabel;
  final String? timeLabel;
  final int width;
  final int height;
  final String fileSize;
  final String format;

  /// "lat, lon" from GPS EXIF when present, else null.
  final String? location;
}

class MapLocation {
  const MapLocation({
    required this.id,
    required this.name,
    required this.cx,
    required this.cy,
    required this.count,
    this.lat = 0,
    this.lon = 0,
  });
  final String id;
  final String name;
  // Normalized coordinates on the legacy stylized USA map (kept for that widget).
  final double cx;
  final double cy;
  final int count;
  // True cluster-centroid coordinates (decimal degrees) — drives the world map,
  // reverse-geocoding, and KML export.
  final double lat;
  final double lon;
}

class TaskInfo {
  TaskInfo({required this.id, required this.name, required this.percent});
  final String id;
  final String name;
  double percent;
}

enum NavSection {
  folders,
  people,
  albums,
  timeline,
  map,
  unnamed,
  smart,
  searchResults,
}
