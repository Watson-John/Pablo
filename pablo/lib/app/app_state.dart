// Single ChangeNotifier holding the whole app's UI state.
// Per-feature state stays local in the relevant widget.

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart' show Album, Engine;

import '../data/library.dart';
import '../data/models.dart';
import '../utils/asset_id.dart';

class GridMode {
  static const grid = 'grid';
  static const masonry = 'masonry';
}

class FolderSort {
  static const tree = 'tree';
  static const alpha = 'alpha';
}

class AdvSearchCriteria {
  AdvSearchCriteria({
    this.dateMode = 'any',
    this.dateFrom = '',
    this.dateTo = '',
    this.specificMonth = 'Any',
    this.dayOfMonth = '',
    this.year = '',
    Set<String>? people,
    this.peopleMatch = 'or',
    this.starred = false,
    this.videosOnly = false,
    this.hasLocation = false,
    this.notInAlbum = false,
    this.hasBeenEdited = false,
    this.camera = 'Any',
    this.lens = '',
    this.isoMin = '',
    this.isoMax = '',
    this.apertureMin = '',
    this.apertureMax = '',
    this.focalMin = '',
    this.focalMax = '',
    this.tags = '',
    this.fileType = 'Any',
    this.album = 'Any',
  }) : people = people ?? <String>{};

  String dateMode;
  String dateFrom;
  String dateTo;
  String specificMonth;
  String dayOfMonth;
  String year;
  final Set<String> people;
  String peopleMatch;
  bool starred;
  bool videosOnly;
  bool hasLocation;
  bool notInAlbum;
  bool hasBeenEdited;
  String camera;
  String lens;
  String isoMin;
  String isoMax;
  String apertureMin;
  String apertureMax;
  String focalMin;
  String focalMax;
  String tags;
  String fileType;
  String album;

  int get activeCount {
    var n = 0;
    if (dateMode != 'any') n++;
    if (people.isNotEmpty) n += people.length;
    if (starred) n++;
    if (videosOnly) n++;
    if (hasLocation) n++;
    if (notInAlbum) n++;
    if (camera != 'Any') n++;
    if (tags.isNotEmpty) n++;
    if (fileType != 'Any') n++;
    if (album != 'Any') n++;
    return n;
  }
}

class PabloAppState extends ChangeNotifier {
  // Layout
  double sidebarWidth = 260;

  // Navigation. The real default folder is selected at startup (PabloApp) once
  // the library is scanned.
  String selectedItem = '';
  NavSection activeSection = NavSection.folders;
  String folderSort = FolderSort.tree;

  // User-created albums (from the native catalog). Reloaded on library-ready
  // and after any album mutation.
  List<Album> albums = const [];

  // Selection
  final Set<String> selectedPhotos = <String>{};
  String? activePhotoId;

  // Tray
  final List<String> trayPhotos = <String>[];
  bool trayLocked = false;

  // Search
  String searchText = '';
  AdvSearchCriteria? advCriteria;

  // View. Zoom range 60–512 px (512 matches the native thumbnail decode size);
  // 200 is the default.
  double thumbSize = 200;
  String gridMode = GridMode.grid;

  /// One of `'people' | 'tags' | 'info'` or null to hide the right info panel.
  String? infoPanelTab;

  // Lightbox
  String? lightboxPhotoId;

  // Tasks (background activity). Real tasks are added by their owners (e.g. the
  // face-scan ingestion); there is no seeded placeholder.
  final List<TaskInfo> tasks = <TaskInfo>[];

  // ── Mutators ──
  void setSelectedItem(String id, NavSection section) {
    selectedItem = id;
    activeSection = section;
    selectedPhotos.clear();
    notifyListeners();
  }

  /// Reload albums + their member photos from the catalog. The members resolve
  /// stable asset ids back to library photos so the gallery can render them.
  void reloadAlbums(Engine? engine) {
    if (engine == null) {
      albums = const [];
      setAlbumSectionPhotos(const {});
      notifyListeners();
      return;
    }
    albums = engine.listAlbums();
    final map = <String, List<Photo>>{};
    for (final a in albums) {
      final photos = <Photo>[];
      for (final assetId in engine.albumMembers(a.id)) {
        final path = pathForAssetId(assetId);
        final p = path == null ? null : Library.instance.byId[path];
        if (p != null) photos.add(p);
      }
      map['album:${a.id}'] = photos;
    }
    setAlbumSectionPhotos(map);
    notifyListeners();
  }

  void setFolderSort(String sort) {
    folderSort = sort;
    notifyListeners();
  }

  void setSidebarWidth(double w) {
    sidebarWidth = w.clamp(180, 360);
    notifyListeners();
  }

  void setSearchText(String q) {
    searchText = q;
    notifyListeners();
  }

  void setAdvCriteria(AdvSearchCriteria? c) {
    advCriteria = c;
    notifyListeners();
  }

  void setThumbSize(double s) {
    thumbSize = s.clamp(60, 512);
    notifyListeners();
  }

  void setGridMode(String mode) {
    gridMode = mode;
    notifyListeners();
  }

  void setInfoPanelTab(String? tab) {
    infoPanelTab = tab;
    notifyListeners();
  }

  void toggleTrayLock() {
    trayLocked = !trayLocked;
    notifyListeners();
  }

  void clearTray() {
    trayPhotos.clear();
    notifyListeners();
  }

  void removeFromTray(String id) {
    trayPhotos.remove(id);
    notifyListeners();
  }

  void addToTray(String id) {
    if (!trayPhotos.contains(id)) trayPhotos.add(id);
    notifyListeners();
  }

  /// Used by gallery click handler. Mirrors the React logic in pablo3-app.jsx.
  void selectPhoto(
    String id, {
    bool ctrl = false,
    bool shift = false,
    required List<String> contextPhotoIds,
  }) {
    if (ctrl) {
      if (selectedPhotos.contains(id)) {
        selectedPhotos.remove(id);
        trayPhotos.remove(id);
      } else {
        selectedPhotos.add(id);
        if (!trayPhotos.contains(id)) trayPhotos.add(id);
      }
      activePhotoId = id;
    } else if (shift && activePhotoId != null) {
      final startIdx = contextPhotoIds.indexOf(activePhotoId!);
      final endIdx = contextPhotoIds.indexOf(id);
      if (startIdx >= 0 && endIdx >= 0) {
        final lo = startIdx < endIdx ? startIdx : endIdx;
        final hi = startIdx < endIdx ? endIdx : startIdx;
        for (var i = lo; i <= hi; i++) {
          selectedPhotos.add(contextPhotoIds[i]);
          if (!trayPhotos.contains(contextPhotoIds[i])) {
            trayPhotos.add(contextPhotoIds[i]);
          }
        }
      }
    } else {
      if (trayLocked) {
        selectedPhotos.add(id);
        if (!trayPhotos.contains(id)) trayPhotos.add(id);
      } else {
        selectedPhotos
          ..clear()
          ..add(id);
      }
      activePhotoId = id;
    }
    notifyListeners();
  }

  void openLightbox(String photoId) {
    lightboxPhotoId = photoId;
    notifyListeners();
  }

  void closeLightbox() {
    lightboxPhotoId = null;
    notifyListeners();
  }

  /// Add (or replace) a background task and notify. Used by face ingestion.
  void startTask(TaskInfo task) {
    tasks.removeWhere((t) => t.id == task.id);
    tasks.add(task);
    notifyListeners();
  }

  /// Update a task's progress and notify. No-op if the id is unknown.
  void updateTaskPercent(String id, double percent) {
    for (final t in tasks) {
      if (t.id == id) t.percent = percent.clamp(0, 100);
    }
    notifyListeners();
  }

  /// Retire finished tasks. Real progress is driven by each task's owner via
  /// [updateTaskPercent]; this just sweeps completed ones off the indicator.
  void tickTasks() {
    final before = tasks.length;
    tasks.removeWhere((t) => t.percent >= 100);
    if (tasks.length != before) notifyListeners();
  }
}
