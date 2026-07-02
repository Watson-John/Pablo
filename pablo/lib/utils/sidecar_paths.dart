// sidecar_paths.dart — the path-adjacent companion files that belong to a
// photo and must travel with it when the file moves or is renamed:
//
//   * `<path>.xmp`        — the opt-in MWG face-region sidecar (xmp/face_xmp
//                           on the native side writes it next to the source).
//   * `<stem>.pablo.tif`  — the layered-TIFF edit save (original + edited
//                           pages; see EditSession.saveLayered).
//
// Kept as pure string helpers so both the editor (which writes them) and the
// move service (which relocates them) derive the exact same paths.

/// The face-region XMP sidecar beside [src].
String xmpSidecarPathFor(String src) => '$src.xmp';

/// The `<stem>.pablo.tif` layered-TIFF save beside [src].
String layeredTiffPathFor(String src) {
  final dot = src.lastIndexOf('.');
  final base = dot > 0 ? src.substring(0, dot) : src;
  return '$base.pablo.tif';
}

/// (from, to) pairs for every sidecar that should follow a `from → to` move
/// of the photo itself. Callers move each pair best-effort — a missing
/// sidecar is the normal case.
List<(String, String)> sidecarMovesFor(String from, String to) => [
      (xmpSidecarPathFor(from), xmpSidecarPathFor(to)),
      (layeredTiffPathFor(from), layeredTiffPathFor(to)),
    ];
