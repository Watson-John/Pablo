// Single ChangeNotifier holding the whole app's UI state.
// Per-feature state stays local in the relevant widget.

import 'package:flutter/foundation.dart';
import 'package:photo_native/photo_native.dart' show Album, Engine;

import '../data/library.dart';
import '../data/models.dart';
import '../data/scheme_store.dart';
import '../data/storage_scheme.dart';
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

  // Gallery sort. Mirrored into the library.dart shim so the [photosFor] filter
  // (a plain function) can read it without an AppState reference.
  String photoSort = PhotoSort.name;
  bool sortReversed = false;

  /// One of `'people' | 'tags' | 'info'` or null to hide the right info panel.
  String? infoPanelTab;

  // Lightbox
  String? lightboxPhotoId;

  /// Immersive lightbox: hides all app chrome (menu/search bars, sidebar, edit
  /// panel, controls bar) for edge-to-edge viewing. Only meaningful while a
  /// lightbox photo is open; reset whenever the lightbox opens or closes.
  bool lightboxFullscreen = false;

  // Compare view — 2-up side-by-side of selected/tray photos. Mutually
  // exclusive with the lightbox.
  List<String> compareIds = const [];

  // Find Duplicates workflow (full-screen flow; its stage/cluster/selection
  // state stays local to the FindDuplicatesFlow widget).
  bool dedupOpen = false;

  /// Redundant exact copies found by the background import scan (menu badge).
  int dupCount = 0;

  // Tasks (background activity). Real tasks are added by their owners (e.g. the
  // face-scan ingestion); there is no seeded placeholder.
  final List<TaskInfo> tasks = <TaskInfo>[];

  // Storage schemes (organization templates). Empty until [loadSchemes] runs at
  // startup, so widget tests that pump the app never touch the filesystem.
  final List<StorageScheme> schemes = <StorageScheme>[];
  String? activeSchemeId;

  /// The active scheme, or the first available, or null when none are loaded.
  StorageScheme? get activeScheme {
    for (final s in schemes) {
      if (s.id == activeSchemeId) return s;
    }
    return schemes.isEmpty ? null : schemes.first;
  }

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

  /// How many of the newest imports the "Recently Added" smart collection holds.
  static const int recentLimit = 500;

  /// Rebuild the seeded smart collections (All Photos / Recently Added /
  /// Starred) from the catalog into `smart:*` keys. Resolves catalog asset ids
  /// back to library photos, exactly like [reloadAlbums]. Call on library-ready,
  /// after import, and after a star/hide toggle.
  void reloadSmartCollections(Engine? engine) {
    if (engine == null) {
      setSmartSectionPhotos(const {});
      notifyListeners();
      return;
    }
    Photo? resolve(int assetId) {
      final path = pathForAssetId(assetId);
      return path == null ? null : Library.instance.byId[path];
    }

    final recent = <Photo>[
      for (final id in engine.recentAssets(recentLimit))
        if (resolve(id) case final p?) p,
    ];
    final starred = <Photo>[
      for (final id in engine.starredAssets())
        if (resolve(id) case final p?) p,
    ];
    setSmartSectionPhotos({
      'smart:all': Library.instance.allPhotos,
      'smart:recent': recent,
      'smart:starred': starred,
    });
    notifyListeners();
  }

  /// Notify after toggling an asset's star (the cache lives in library.dart) so
  /// the gallery + info panel rebuild.
  void notifyStar() => notifyListeners();

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

  void setPhotoSort(String key) {
    photoSort = key;
    setLibrarySort(photoSort, sortReversed);
    notifyListeners();
  }

  void setSortReversed(bool v) {
    sortReversed = v;
    setLibrarySort(photoSort, sortReversed);
    notifyListeners();
  }

  /// Whether hidden photos/folders are shown. Mirrored into a top-level shim in
  /// library.dart so the [photosFor] gallery filter (a plain function) can read
  /// it without an AppState reference.
  bool showHidden = false;
  void setShowHidden(bool v) {
    showHidden = v;
    setLibraryShowHidden(v);
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

  void openFindDuplicates() {
    dedupOpen = true;
    notifyListeners();
  }

  void closeFindDuplicates() {
    dedupOpen = false;
    notifyListeners();
  }

  void setDupCount(int n) {
    dupCount = n;
    notifyListeners();
  }

  void openLightbox(String photoId) {
    lightboxPhotoId = photoId;
    lightboxFullscreen = false;
    compareIds = const [];
    notifyListeners();
  }

  /// Open the 2-up compare view over [ids] (the first two are shown). Closes any
  /// open lightbox first.
  void openCompare(List<String> ids) {
    if (ids.length < 2) return;
    compareIds = List<String>.from(ids);
    lightboxPhotoId = null;
    lightboxFullscreen = false;
    notifyListeners();
  }

  void closeCompare() {
    compareIds = const [];
    notifyListeners();
  }

  void closeLightbox() {
    lightboxPhotoId = null;
    lightboxFullscreen = false;
    notifyListeners();
  }

  void toggleLightboxFullscreen() {
    lightboxFullscreen = !lightboxFullscreen;
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

  // ── Storage schemes ──

  /// Load schemes from disk (seeding presets on first run). Called once from
  /// main(); intentionally not in the constructor so tests stay filesystem-free.
  void loadSchemes() {
    final data = SchemeStore.load();
    schemes
      ..clear()
      ..addAll(data.schemes);
    activeSchemeId = data.activeId;
    notifyListeners();
  }

  void setActiveScheme(String id) {
    activeSchemeId = id;
    _persistSchemes();
    notifyListeners();
  }

  /// Insert or replace [scheme] (matched by id) and make it active.
  void upsertScheme(StorageScheme scheme) {
    final i = schemes.indexWhere((s) => s.id == scheme.id);
    if (i >= 0) {
      schemes[i] = scheme;
    } else {
      schemes.add(scheme);
    }
    activeSchemeId = scheme.id;
    _persistSchemes();
    notifyListeners();
  }

  void deleteScheme(String id) {
    schemes.removeWhere((s) => s.id == id);
    if (activeSchemeId == id) {
      activeSchemeId = schemes.isEmpty ? null : schemes.first.id;
    }
    _persistSchemes();
    notifyListeners();
  }

  void _persistSchemes() =>
      SchemeStore.save(SchemeStoreData(schemes, activeSchemeId));

  /// Force AppScope dependents (sidebar, gallery) to rebuild against a freshly
  /// re-scanned [Library.instance] — e.g. after an in-app reorganize move.
  void libraryChanged() => notifyListeners();
}
