// Root MaterialApp providing the AppScope and the WindowShell.

import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/native_backend.dart';
import '../components/context_menu.dart';
import '../components/resize_handle.dart';
import '../data/models.dart';
import '../data/mock/photo_factory.dart';
import '../data/sources/face_repository.dart';
import '../features/controls_bar/controls_bar.dart';
import '../features/editor/photo_edit_panel.dart';
import '../features/gallery/lightbox_view.dart';
import '../features/gallery/main_grid.dart';
import '../features/info_panel/info_panel.dart';
import '../features/people/face_ingestion.dart';
import '../features/people/people_controller.dart';
import '../features/people/people_scope.dart';
import '../features/photo_tray/photo_tray.dart';
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

  /// Debug hook: when PABLO_AUTOSCAN is set (and a live backend + dataset are
  /// present), kick off a face scan of the dataset folder on first frame.
  /// Lets the live pipeline be exercised headlessly without the menu.
  static const bool _autoScan =
      bool.fromEnvironment('PABLO_AUTOSCAN', defaultValue: false);
  bool _autoScanned = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _state.tickTasks(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final backend = NativeBackendScope.maybeOf(context);
    _people ??= PeopleController(
      backend?.faces ?? const MockFaceRepository(),
      engine: backend?.engine,
    );
    if (_autoScan &&
        !_autoScanned &&
        backend != null &&
        _people!.isLive &&
        kDatasetDir.isNotEmpty) {
      _autoScanned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FaceIngestion(
          backend: backend,
          controller: _people!,
          appState: _state,
        ).ingestFolder(kDatasetDir);
      });
    }
  }

  @override
  void dispose() {
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
        statusSection: _sectionLabel(st),
        body: _Body(),
      ),
    );
  }

  String _sectionLabel(PabloAppState st) {
    switch (st.activeSection) {
      case NavSection.folders:
        return 'Folders';
      case NavSection.albums:
        return 'Albums';
      case NavSection.people:
        return 'People';
      case NavSection.timeline:
        return 'Timeline';
      case NavSection.map:
        return 'Map';
      case NavSection.unnamed:
        return 'Unnamed Faces';
    }
  }
}

class _Body extends StatefulWidget {
  @override
  State<_Body> createState() => _BodyState();
}

Photo? _resolveActivePhoto(PabloAppState st) {
  final id = st.activePhotoId;
  if (id == null) return null;
  final dash = id.lastIndexOf('-');
  if (dash < 0) return null;
  final setId = id.substring(0, dash);
  for (final p in photosFor(setId)) {
    if (p.id == id) return p;
  }
  return null;
}

class _BodyState extends State<_Body> {
  double _sidebarStart = 260;
  double _trayStart = 100;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final lightboxPhoto =
        st.lightboxPhotoId != null ? _resolvePhotoById(st.lightboxPhotoId!) : null;
    final contextPhotos = lightboxPhoto != null ? _contextPhotosFor(st, lightboxPhoto) : <Photo>[];

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
                    : Row(
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
                                      onPressed: () => st.openLightbox(id),
                                    ),
                                    ContextMenuItem(
                                      label: 'Edit',
                                      iconCharacter: '✏️',
                                      onPressed: () => st.openLightbox(id),
                                    ),
                                    ContextMenuItem(
                                      label: (photo?.starred ?? false)
                                          ? 'Unstar'
                                          : 'Star',
                                      iconCharacter: (photo?.starred ?? false)
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
              const ControlsBar(),
              ResizeHandle(
                direction: ResizeDirection.row,
                onResize: (delta, isStart) {
                  if (isStart) {
                    _trayStart = st.trayHeight;
                  } else {
                    st.setTrayHeight(_trayStart - delta);
                    _trayStart = st.trayHeight;
                  }
                },
              ),
              const PhotoTray(),
            ],
          ),
        ),
      ],
    );
  }
}

Photo? _resolvePhotoById(String id) {
  final dash = id.lastIndexOf('-');
  if (dash < 0) return null;
  final setId = id.substring(0, dash);
  for (final p in photosFor(setId)) {
    if (p.id == id) return p;
  }
  return null;
}

List<Photo> _contextPhotosFor(PabloAppState st, Photo photo) {
  // Use the currently selected sidebar item's photo set if available;
  // otherwise fall back to a single-photo list.
  final sel = photosFor(st.selectedItem);
  if (sel.any((p) => p.id == photo.id)) return sel;
  return [photo];
}
