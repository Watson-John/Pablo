// Resolves photo sets for duplicate scanning. Shared by the Find Duplicates
// flow (scope picker) and the import-time auto-scan.

import '../../data/library.dart';
import '../../data/models.dart';

/// All photos under the folder tree's leaves, de-duplicated by id. When
/// [onlyFolderIds] is given, only those leaf folders are included.
List<Photo> photosForLeaves({Set<String>? onlyFolderIds}) {
  final out = <Photo>[];
  final seen = <String>{};
  void walk(FolderNode n) {
    if (n.isGroup) {
      for (final c in n.children) {
        walk(c);
      }
      return;
    }
    if (onlyFolderIds == null || onlyFolderIds.contains(n.id)) {
      for (final p in photosFor(n.id)) {
        if (seen.add(p.id)) out.add(p);
      }
    }
  }
  for (final f in Library.instance.folderTree) {
    walk(f);
  }
  return out;
}

/// Every photo Pablo manages (the whole library).
List<Photo> allLibraryPhotos() => photosForLeaves();
