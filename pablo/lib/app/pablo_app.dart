// Root MaterialApp providing the AppScope and the WindowShell.

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../backend/native_backend.dart';
import '../components/context_menu.dart';
import '../components/resize_handle.dart';
import '../data/boot.dart';
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
import '../features/info_panel/info_panel.dart';
import '../features/people/face_ingestion.dart';
import '../features/people/people_controller.dart';
import '../features/people/people_scope.dart';
import '../features/photo_tray/photo_tray.dart' show FloatingPhotoTray;
import '../features/sidebar/sidebar.dart';
import '../layouts/shell.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../utils/asset_id.dart';
import 'app_scope.dart';
import 'app_state.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = NativeBackendScope.maybeOf(context);
    _backend = backend; // for the on-exit catalog cleanup
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

    final photos = photosFor(st.selectedItem);
    return Scaffold(
      backgroundColor: PabloColors.backgroundShell,
      body: WindowShell(
        statusPhotoCount: photos.length,
        body: st.dedupOpen ? const FindDuplicatesFlow() : _Body(),
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

  // Toggle the photo's star (catalog-persisted) and refresh the gallery.
  void _toggleStar(String photoId) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine == null) return;
    final aid = assetIdFor(photoId);
    final v = !isStarredAsset(aid);
    engine.setStarred(aid, v);
    setStarredLocal(aid, v);
    final st = AppScope.of(context);
    st.reloadSmartCollections(engine); // Starred collection changed
    st.notifyStar();
  }

  // Toggle the photo's hidden flag (catalog-persisted). Rebuilds the gallery so
  // a hidden photo vanishes (unless "Show hidden" is on).
  void _toggleHidden(String photoId) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine == null) return;
    final v = !isHiddenPhoto(photoId);
    engine.setHidden(assetIdFor(photoId), v);
    setHiddenLocal(photoId, v);
    final st = AppScope.of(context);
    st.reloadSmartCollections(engine); // hidden affects All/Recent/Starred
    st.libraryChanged();
  }

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

  // Remove the right-clicked photo from the current album, then reload.
  void _removeFromCurrentAlbum(String photoId) {
    final backend = NativeBackendScope.maybeOf(context);
    final st = AppScope.of(context);
    final albumId = _currentAlbumId(st);
    if (backend == null || albumId == null) return;
    backend.engine.removeFromAlbum(albumId, assetIdFor(photoId));
    st.reloadAlbums(backend.engine);
  }

  // Add a photo to an album the user picks (or a new one), then reload.
  Future<void> _addToAlbum(String photoId) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) return;
    final st = AppScope.of(context);
    final albumId = await _pickAlbum(st);
    if (!mounted) return;
    if (albumId == null || albumId == 0) return;
    backend.engine.addToAlbum(albumId, assetIdFor(photoId));
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
                                        onPhotoSecondary: (pos, id) {
                                          final photo = _resolvePhotoById(id);
                                          PabloContextMenu.show(
                                            context,
                                            position: pos,
                                            items: [
                                              ContextMenuItem(
                                                label: 'View',
                                                iconCharacter: '👁',
                                                onPressed: () =>
                                                    st.openLightbox(id),
                                              ),
                                              ContextMenuItem(
                                                label: 'Edit',
                                                iconCharacter: '✏️',
                                                onPressed: () =>
                                                    st.openLightbox(id),
                                              ),
                                              ContextMenuItem(
                                                label: ((photo?.starred ??
                                                            false) ||
                                                        isStarredAsset(
                                                            assetIdFor(id)))
                                                    ? 'Unstar'
                                                    : 'Star',
                                                iconCharacter:
                                                    ((photo?.starred ??
                                                                false) ||
                                                            isStarredAsset(
                                                                assetIdFor(id)))
                                                        ? '☆'
                                                        : '★',
                                                onPressed: () =>
                                                    _toggleStar(id),
                                              ),
                                              ContextMenuItem(
                                                label: 'Add to Album',
                                                iconCharacter: '+',
                                                onPressed: () =>
                                                    _addToAlbum(id),
                                              ),
                                              if (_currentAlbumId(st) !=
                                                  null) ...[
                                                ContextMenuItem(
                                                  label: 'Set as Album Cover',
                                                  iconCharacter: '🖼',
                                                  onPressed: () =>
                                                      _setAlbumCover(id),
                                                ),
                                                ContextMenuItem(
                                                  label: 'Remove from Album',
                                                  iconCharacter: '−',
                                                  onPressed: () =>
                                                      _removeFromCurrentAlbum(
                                                          id),
                                                ),
                                              ],
                                              ContextMenuItem(
                                                label: isHiddenPhoto(id)
                                                    ? 'Unhide'
                                                    : 'Hide',
                                                iconCharacter: isHiddenPhoto(id)
                                                    ? '◉'
                                                    : '⊘',
                                                onPressed: () =>
                                                    _toggleHidden(id),
                                              ),
                                              ContextMenuItem(
                                                label: 'Share',
                                                iconCharacter: '📤',
                                              ),
                                              ContextMenuItem.separator(),
                                              ContextMenuItem(
                                                label: 'Print',
                                                iconCharacter: '🖨',
                                              ),
                                              ContextMenuItem(
                                                label: 'Rotate Left',
                                                iconCharacter: '↺',
                                              ),
                                              ContextMenuItem(
                                                label: 'Rotate Right',
                                                iconCharacter: '↻',
                                              ),
                                              ContextMenuItem.separator(),
                                              ContextMenuItem(
                                                label: 'Delete',
                                                iconCharacter: '🗑',
                                                destructive: true,
                                              ),
                                            ],
                                          );
                                        },
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
