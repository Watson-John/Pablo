// Root MaterialApp providing the AppScope and the WindowShell.

import 'dart:async';

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
import '../features/editor/photo_edit_panel.dart';
import '../features/find_duplicates/dedup_scope.dart';
import '../features/find_duplicates/find_duplicates_flow.dart';
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
import 'app_scope.dart';
import 'app_state.dart';

class PabloApp extends StatefulWidget {
  const PabloApp({super.key});

  @override
  State<PabloApp> createState() => _PabloAppState();
}

class _PabloAppState extends State<PabloApp> {
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
    _selectDefaultFolder();
    // The library is scanned in the background; rebuild + select + face-scan
    // once it's ready.
    libraryRevision.addListener(_onLibraryReady);
    _ticker = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _state.tickTasks(),
    );
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
    _people ??= PeopleController(backend?.faces ?? const MockFaceRepository());
    _maybeAutoScan();
    if (!_dedupScanned) {
      _dedupScanned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final clusters = await createDedupRepository().findExact(allLibraryPhotos());
        final n = clusters.fold<int>(0, (s, c) => s + c.discards.length);
        if (mounted) _state.setDupCount(n);
      });
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final lightboxPhoto = st.lightboxPhotoId != null
        ? _resolvePhotoById(st.lightboxPhotoId!)
        : null;
    final contextPhotos = lightboxPhoto != null
        ? _contextPhotosFor(st, lightboxPhoto)
        : <Photo>[];

    return Row(
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
                child: lightboxPhoto != null
                    ? LightboxView(
                        photos: contextPhotos,
                        initialId: lightboxPhoto.id,
                        onClose: st.closeLightbox,
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                            label: (photo?.starred ?? false)
                                                ? 'Unstar'
                                                : 'Star',
                                            iconCharacter:
                                                (photo?.starred ?? false)
                                                    ? '☆'
                                                    : '★',
                                          ),
                                          ContextMenuItem(
                                            label: 'Add to Album',
                                            iconCharacter: '+',
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
                                    onTabChange: (t) => st.setInfoPanelTab(t),
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
