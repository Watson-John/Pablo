// Root MaterialApp providing the AppScope and the WindowShell.

import 'dart:async';
import 'dart:io' show Directory, File;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart'
    show Engine, PhotoEvent, PhotoEventKind;

import '../backend/native_backend.dart';
import '../data/indexing/indexing_controller.dart';
import '../components/resize_handle.dart';
import '../data/boot.dart';
import '../data/model_fetcher.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../data/sources/dedup_repository.dart';
import '../data/sources/face_repository.dart';
import '../features/controls_bar/controls_bar.dart';
import '../features/editor/edit_session.dart';
import '../features/editor/photo_edit_panel.dart';
import '../features/find_duplicates/dedup_scope.dart';
import '../features/find_duplicates/find_duplicates_flow.dart';
import '../features/gallery/compare_view.dart';
import '../features/gallery/lightbox_view.dart';
import '../features/gallery/main_grid.dart';
import '../features/gallery/photo_context_menu.dart';
import '../features/info_panel/info_panel.dart';
import '../features/organize/reorganize_controller.dart';
import '../features/people/face_ingestion.dart';
import '../features/people/people_controller.dart';
import '../features/people/people_scope.dart';
import '../features/photo_tray/photo_tray.dart' show FloatingPhotoTray;
import '../features/search/first_run_indexing_screen.dart';
import '../features/search/search_controller.dart';
import '../features/sidebar/sidebar.dart';
import '../layouts/shell.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../utils/asset_id.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'key_actions.dart';

class PabloApp extends StatefulWidget {
  const PabloApp({super.key});

  @override
  State<PabloApp> createState() => _PabloAppState();
}

class _PabloAppState extends State<PabloApp> with WidgetsBindingObserver {
  /// Captured in [didChangeDependencies] so the on-exit cleanup can reach the
  /// engine without a BuildContext during teardown.
  NativeBackend? _backend;

  // Only VACUUM on exit when there is meaningful space to reclaim, so quitting
  // stays fast; the cheap WAL checkpoint runs unconditionally.
  static const int _vacuumThresholdBytes = 16 * 1024 * 1024;
  late final PabloAppState _state = PabloAppState();

  /// People-feature state, derived from the native backend if one is mounted
  /// above us (live), else the mock repository. Built here (not in main) so
  /// the app — and widget tests that pump it directly — always has a
  /// PeopleScope. Initialized in didChangeDependencies where the backend
  /// InheritedWidget is reachable.
  PeopleController? _people;
  Timer? _ticker;

  bool _autoScanned = false;

  /// Import-time auto-scan: run the cheap exact-duplicate pass over the library
  /// once on load and badge the count on the Tools menu. (A real "Import From…"
  /// action would call the same path for just the newly-added photos.)
  bool _dedupScanned = false;

  // Semantic-embedding indexing (Stage 9), sequenced AFTER the face pass.
  IndexingController? _indexing;
  StreamSubscription<PhotoEvent>? _eventSub;
  bool _indexingStarted = false;

  // Model-download gating (Stage 9 v1): indexing waits for the semantic model
  // stage to resolve — embeddings built with the fallback model would all be
  // re-queued the moment the real model lands. null = probe still running.
  bool? _modelsMissing;
  bool _modelStageResolved = false;
  bool _modelDownloadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // for didRequestAppExit
    _selectDefaultFolder();
    // The library is scanned in the background; rebuild + select + face-scan
    // once it's ready.
    libraryRevision.addListener(_onLibraryReady);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _state.tickTasks(),
    );
  }

  /// On quit, tidy the catalog: always checkpoint the WAL (near-instant, keeps
  /// the file from growing) and VACUUM only when there is real space to reclaim
  /// (so quitting stays fast). Synchronous so it completes before teardown.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final engine = _backend?.engine;
    if (engine != null) {
      try {
        engine.catalogCheckpoint();
        final s = engine.catalogStats();
        if (s != null && s.reclaimableBytes > _vacuumThresholdBytes) {
          engine.compactCatalogSync();
        }
      } catch (_) {
        // Best-effort cleanup — never block the user from quitting.
      }
    }
    return AppExitResponse.exit;
  }

  void _selectDefaultFolder() {
    final first = Library.instance.firstPhotoFolderId;
    if (first != null && _state.selectedItem.isEmpty) {
      _state.setSelectedItem(first, NavSection.folders);
    }
  }

  void _onLibraryReady() {
    if (!mounted) return;
    _selectDefaultFolder();
    // Albums + smart collections reference library photos, so (re)load them
    // once the library is in.
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    _state.reloadAlbums(engine);
    _state.reloadSmartCollections(engine);
    setState(() {}); // rebuild the tree against the freshly-scanned library
    _maybeAutoScan(); // now that photos exist, kick off the face scan
  }

  /// Start the background face scan once — but only when faces can run live and
  /// the library has photos (returns null otherwise, so a boot-time call before
  /// the scan finishes is a harmless no-op that re-arms via [_onLibraryReady]).
  void _maybeAutoScan() {
    if (!BootConfig.instance.autoScan || _autoScanned || _people == null) {
      return;
    }
    final scan = FaceIngestion.scanLibraryAction(
      backend: NativeBackendScope.maybeOf(context),
      controller: _people!,
      appState: _state,
    );
    if (scan != null) {
      _autoScanned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => scan());
    }
  }

  /// Install the real search runner + the semantic indexing runner once the
  /// native backend is available. The embedding pass is SEQUENCED after faces
  /// (started on the face pipeline's terminal cluster-updated event) so the two
  /// heavy ML passes never run at full tilt together.
  void _installBackendServices(NativeBackend backend) {
    _state.searchRunner ??= PabloSearchController(backend).run;
    if (_indexing != null) return;
    final controller = IndexingController(
      NativeEmbeddingBackend(
        scanFn: backend.engine.embeddingScan,
        pendingFn: () => backend.engine.pendingEmbeddingIds(),
        retryFn: backend.engine.retryFailedEmbeddings,
        countsFn: backend.engine.embeddingCounts,
        eventStream: backend.events,
      ),
      // Reclaim the image encoder's RAM the moment the queue drains — it is
      // only needed while indexing; the next run lazily reloads it (~1 s).
      onDrained: () => backend.engine
          .releaseSemanticSessions(Engine.releaseImageTower),
    );
    _indexing = controller;
    _state.indexing = controller;
    controller.addListener(_onIndexingProgress);
    _eventSub = backend.events.listen((e) {
      if (e.kind == PhotoEventKind.clusterUpdated) _maybeStartIndexing();
    });
    // No face pass will fire clusterUpdated → start embeddings after load.
    if (!BootConfig.instance.autoScan) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeStartIndexing());
    }
    _probeSemanticModels();
  }

  /// Check whether the SigLIP2 files are present in the merged models dir and
  /// arm the download plumbing if not. Re-enters [_maybeStartIndexing] either
  /// way (it is gated on this probe's outcome).
  Future<void> _probeSemanticModels() async {
    var missing = false;
    try {
      final dir = Directory(BootConfig.instance.modelsDir);
      missing = (await ModelFetcher().missing(dir)).isNotEmpty;
    } catch (_) {
      missing = false; // unprobeable dir → proceed with whatever the engine has
    }
    if (!mounted) return;
    _modelsMissing = missing;
    if (missing) {
      _state.needsModelDownload = true;
      _state.modelDownloadRunner = (onProgress) => ModelFetcher().ensureModels(
          Directory(BootConfig.instance.modelsDir),
          onProgress: onProgress);
      _state.onModelsReady = _onModelsArrived;
      _state.onModelStageResolved = _onModelStageResolved;
    } else {
      _modelStageResolved = true;
    }
    _maybeStartIndexing();
  }

  /// Model files just landed: swap the real embedder in (no restart) — stale
  /// fallback-model rows re-queue automatically via the pending query.
  void _onModelsArrived() {
    _backend?.engine.reloadSemantic();
    _state.setNeedsModelDownload(false);
  }

  void _onModelStageResolved() {
    _modelStageResolved = true;
    _maybeStartIndexing();
  }

  /// Small-library path (no safe-mode screen): fetch the model quietly with an
  /// activity-pill task, then swap it in and start indexing. Offline/failed →
  /// proceed with the fallback embedder; the probe retries next launch.
  void _startBackgroundModelDownload() {
    if (_modelDownloadStarted) return;
    _modelDownloadStarted = true;
    _state.startTask(
      TaskInfo(id: 'model-dl', name: 'Downloading search model', percent: 1),
    );
    final specs = ModelFetcher.defaultSpecs;
    ModelFetcher()
        .ensureModels(Directory(BootConfig.instance.modelsDir),
            onProgress: (file, received, total) {
      final i = specs.indexWhere((s) => s.destName == file);
      final frac = total > 0 ? received / total : 0.0;
      final pct = (i < 0 ? frac : (i + frac) / specs.length) * 99;
      _state.updateTaskPercent('model-dl', pct.clamp(1, 99));
    }).then((_) {
      _state.updateTaskPercent('model-dl', 100);
      _onModelsArrived();
      _onModelStageResolved();
    }).catchError((Object e) {
      debugPrint('model download failed (continuing with fallback): $e');
      _state.updateTaskPercent('model-dl', 100);
      _onModelStageResolved();
    });
  }

  void _maybeStartIndexing() {
    final backend = _backend;
    if (_indexingStarted || _indexing == null || backend == null) return;
    final counts = backend.engine.embeddingCounts();
    // Resolve the model download before indexing (see _probeSemanticModels).
    if (!_modelStageResolved) {
      if (_modelsMissing != true) return; // probe still running — it re-enters
      if (IndexingController.recommendSafeMode(counts.pending)) {
        // Large first run: the safe-mode screen shows the download stage and
        // fires onModelStageResolved when it completes or is skipped.
        _state.setShowIndexingScreen(true);
      } else {
        _startBackgroundModelDownload();
      }
      return; // indexing starts from _onModelStageResolved
    }
    _indexingStarted = true;
    if (counts.pending == 0) return;
    if (IndexingController.recommendSafeMode(counts.pending)) {
      _state.setShowIndexingScreen(true);
    }
    _state.startTask(
      TaskInfo(id: 'embed-index', name: 'Building search index', percent: 1),
    );
    _indexing!.start();
  }

  void _onIndexingProgress() {
    final p = _indexing?.progress;
    if (p == null) return;
    _state.updateTaskPercent('embed-index', (p.fraction * 100).clamp(1, 100));
    if (p.isDone) _state.setShowIndexingScreen(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = NativeBackendScope.maybeOf(context);
    _backend = backend; // for the on-exit catalog cleanup
    if (backend != null) _installBackendServices(backend);
    _people ??= PeopleController(backend?.faces ?? const MockFaceRepository());
    _maybeAutoScan();
    if (!_dedupScanned) {
      _dedupScanned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final clusters =
            await createDedupRepository().findExact(allLibraryPhotos());
        final n = clusters.fold<int>(0, (s, c) => s + c.discards.length);
        if (mounted) _state.setDupCount(n);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    libraryRevision.removeListener(_onLibraryReady);
    _ticker?.cancel();
    _eventSub?.cancel();
    _indexing?.removeListener(_onIndexingProgress);
    _indexing?.dispose();
    _people?.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pablo',
      debugShowCheckedModeBanner: false,
      theme: buildPabloTheme(),
      home: AppScope(
        notifier: _state,
        child: PeopleScope(
          notifier: _people!,
          child: const _Home(),
        ),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);

    // Immersive fullscreen: render only the lightbox, edge-to-edge, bypassing
    // all app chrome (menu/search bars, sidebar, edit panel, controls bar,
    // tray). Toggled with the F key / toolbar button inside the lightbox.
    final fsPhoto = (st.lightboxFullscreen && st.lightboxPhotoId != null)
        ? _resolvePhotoById(st.lightboxPhotoId!)
        : null;
    if (fsPhoto != null) {
      return Scaffold(
        backgroundColor: PabloColors.lightboxBackground,
        body: LightboxView(
          photos: _contextPhotosFor(st, fsPhoto),
          initialId: fsPhoto.id,
          onClose: st.closeLightbox,
          fullscreen: true,
          onToggleFullscreen: st.toggleLightboxFullscreen,
          onCurrentChanged: st.setLightboxCurrent,
        ),
      );
    }

    // Safe first-launch mode: while a large library is being indexed, show the
    // progress screen instead of rendering the full grid (which would fight the
    // face + embedding passes for CPU/GPU/disk). Resumable, so the user can drop
    // it to the background at any time.
    if (st.showIndexingScreen) {
      return Scaffold(
        backgroundColor: PabloColors.backgroundShell,
        body: FirstRunIndexingScreen(
          needsModelDownload: st.needsModelDownload,
          modelDownload: st.modelDownloadRunner,
          onModelsReady: st.onModelsReady,
          onModelStageResolved: st.onModelStageResolved,
        ),
      );
    }

    final photos = photosFor(st.selectedItem);
    return Scaffold(
      backgroundColor: PabloColors.backgroundShell,
      body: KeyActions(
        onUndo: () => undoLastFileOp(context, st),
        onMoveSelection: () =>
            promptMoveToFolder(context, st, st.selectedPhotos.toList()),
        child: WindowShell(
          statusPhotoCount: photos.length,
          body: st.dedupOpen ? const FindDuplicatesFlow() : _Body(),
        ),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  @override
  State<_Body> createState() => _BodyState();
}

Photo? _resolveActivePhoto(PabloAppState st) {
  final id = st.activePhotoId;
  return id == null ? null : photoById(id);
}

class _BodyState extends State<_Body> {
  double _sidebarStart = 260;

  // The action bundle handed to the photo context menu. Multi-capable actions
  // take the selection-aware target list; Reveal/Cover stay single (the menu
  // anchors them to the clicked photo).
  PhotoMenuActions _photoMenuActions() => PhotoMenuActions(
        onView: (id) => AppScope.of(context).openLightbox(id),
        onToggleStar: _toggleStar,
        onToggleHidden: _toggleHidden,
        onAddToAlbum: _addToAlbum,
        onMoveToFolder: _moveToFolder,
        onSetAlbumCover: _setAlbumCover,
        onRemoveFromAlbum: _removeFromCurrentAlbum,
        onShowInPablo: _showInPablo,
        isStarred: (id) => isStarredAsset(assetIdFor(id)),
        isHidden: isHiddenPhoto,
      );

  // Jump from a virtual view (search/album/smart/people/timeline) to the
  // photo's home folder in the Folders view: select the folder, scroll it into
  // view with the photo, select + flash the photo.
  void _showInPablo(String id) {
    final st = AppScope.of(context);
    final folder = File(id).parent.path;
    st.setSelectedItem(folder, NavSection.folders);
    st.requestGalleryScroll(folder, photoId: id);
    st.selectPhoto(id,
        contextPhotoIds: photosFor(folder).map((p) => p.id).toList());
    st.flashPhoto(id);
  }

  // Star/unstar the whole target set: if any is unstarred, star all; else
  // unstar all (matches the menu's verb). Catalog-persisted.
  void _toggleStar(List<String> ids) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine == null || ids.isEmpty) return;
    final v = ids.any((id) => !isStarredAsset(assetIdFor(id)));
    for (final id in ids) {
      final aid = assetIdFor(id);
      engine.setStarred(aid, v);
      setStarredLocal(aid, v);
    }
    final st = AppScope.of(context);
    st.reloadSmartCollections(engine); // Starred collection changed
    st.notifyStar();
  }

  // Hide/unhide the whole target set; rebuilds the gallery.
  void _toggleHidden(List<String> ids) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine == null || ids.isEmpty) return;
    final v = ids.any((id) => !isHiddenPhoto(id));
    for (final id in ids) {
      engine.setHidden(assetIdFor(id), v);
      setHiddenLocal(id, v);
    }
    final st = AppScope.of(context);
    st.reloadSmartCollections(engine); // hidden affects All/Recent/Starred
    st.libraryChanged();
  }

  // Move the target set into a folder chosen from the palette (existing or
  // newly created). Delegates to the shared reorganize path.
  Future<void> _moveToFolder(List<String> ids) =>
      promptMoveToFolder(context, AppScope.of(context), ids);

  // The album currently being viewed (album:ID), or null if not in one.
  int? _currentAlbumId(PabloAppState st) {
    if (st.activeSection != NavSection.albums) return null;
    final sel = st.selectedItem;
    return sel.startsWith('album:') ? int.tryParse(sel.substring(6)) : null;
  }

  // Set the right-clicked photo as the current album's cover, then reload.
  void _setAlbumCover(String photoId) {
    final backend = NativeBackendScope.maybeOf(context);
    final st = AppScope.of(context);
    final albumId = _currentAlbumId(st);
    if (backend == null || albumId == null) return;
    backend.engine.setAlbumCover(albumId, assetIdFor(photoId));
    st.reloadAlbums(backend.engine);
  }

  // Remove the target photos from the current album, then reload.
  void _removeFromCurrentAlbum(List<String> ids) {
    final backend = NativeBackendScope.maybeOf(context);
    final st = AppScope.of(context);
    final albumId = _currentAlbumId(st);
    if (backend == null || albumId == null) return;
    for (final id in ids) {
      backend.engine.removeFromAlbum(albumId, assetIdFor(id));
    }
    st.reloadAlbums(backend.engine);
  }

  // Add the target photos to an album the user picks (or a new one), reload.
  Future<void> _addToAlbum(List<String> ids) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null || ids.isEmpty) return;
    final st = AppScope.of(context);
    final albumId = await _pickAlbum(st);
    if (!mounted) return;
    if (albumId == null || albumId == 0) return;
    for (final id in ids) {
      backend.engine.addToAlbum(albumId, assetIdFor(id));
    }
    st.reloadAlbums(backend.engine);
  }

  /// Pick an existing album or create a new one. Returns its id, or null if
  /// cancelled.
  Future<int?> _pickAlbum(PabloAppState st) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine == null) return Future.value();
    return showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add to Album'),
        children: [
          for (final a in st.albums)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(a.id),
              child: Text(a.name.isEmpty ? 'Untitled album' : a.name),
            ),
          SimpleDialogOption(
            onPressed: () async {
              final name = await _promptAlbumName(ctx);
              if (!ctx.mounted) return;
              if (name == null || name.trim().isEmpty) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(engine.createAlbum(name.trim()));
            },
            child: const Text('New Album…'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptAlbumName(BuildContext context) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c2) => AlertDialog(
        title: const Text('New Album'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Album name'),
          onSubmitted: (v) => Navigator.of(c2).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c2).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c2).pop(ctl.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final lightboxPhoto = st.lightboxPhotoId != null
        ? _resolvePhotoById(st.lightboxPhotoId!)
        : null;
    final contextPhotos = lightboxPhoto != null
        ? _contextPhotosFor(st, lightboxPhoto)
        : <Photo>[];

    final Widget shell = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lightboxPhoto != null)
          PhotoEditPanel(photo: lightboxPhoto, width: st.sidebarWidth)
        else
          const Sidebar(),
        ResizeHandle(
          direction: ResizeDirection.column,
          onResize: (delta, isStart) {
            if (isStart) {
              _sidebarStart = st.sidebarWidth;
            } else {
              st.setSidebarWidth(_sidebarStart + delta);
              _sidebarStart = st.sidebarWidth;
            }
          },
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: st.compareIds.length >= 2
                    ? CompareView(
                        ids: st.compareIds,
                        onClose: st.closeCompare,
                      )
                    : lightboxPhoto != null
                        ? LightboxView(
                            photos: contextPhotos,
                            initialId: lightboxPhoto.id,
                            onClose: st.closeLightbox,
                            onToggleFullscreen: st.toggleLightboxFullscreen,
                            onCurrentChanged: st.setLightboxCurrent,
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: MainGrid(
                                        onPhotoSecondary: (pos, id) =>
                                            showPhotoContextMenu(
                                          context,
                                          position: pos,
                                          clickedId: id,
                                          st: st,
                                          albumId: _currentAlbumId(st),
                                          actions: _photoMenuActions(),
                                        ),
                                      ),
                                    ),
                                    if (st.infoPanelTab != null)
                                      PhotoInfoPanel(
                                        photo: _resolveActivePhoto(st),
                                        activeTab: st.infoPanelTab!,
                                        onClose: () => st.setInfoPanelTab(null),
                                        onTabChange: (t) =>
                                            st.setInfoPanelTab(t),
                                      ),
                                  ],
                                ),
                              ),
                              // Floating tray overlay — bottom-anchored, sized to
                              // its content, and click-through everywhere else.
                              const Positioned(
                                left: 0,
                                right: 0,
                                bottom: PabloSpacing.xxxl,
                                child: FloatingPhotoTray(),
                              ),
                            ],
                          ),
              ),
              const ControlsBar(),
            ],
          ),
        ),
      ],
    );

    // When a photo is open, provide a shared EditSession above both the edit
    // panel (left) and the lightbox image (right) so they edit/preview the same
    // spec for the asset currently on screen.
    if (lightboxPhoto == null) return shell;
    return EditSessionProvider(
      engine: NativeBackendScope.maybeOf(context)?.engine,
      assetId: assetIdFor(lightboxPhoto.id),
      path: lightboxPhoto.filePath,
      child: shell,
    );
  }
}

Photo? _resolvePhotoById(String id) => photoById(id);

List<Photo> _contextPhotosFor(PabloAppState st, Photo photo) {
  // Use the currently selected sidebar item's photo set if available;
  // otherwise fall back to a single-photo list.
  final sel = photosFor(st.selectedItem);
  if (sel.any((p) => p.id == photo.id)) return sel;
  return [photo];
}
