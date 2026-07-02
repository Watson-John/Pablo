// MenuBar — File / Edit / View / People / Albums / Tools / Help.
// Each menu opens a dropdown of MenuItems. Hover-tracks the active menu.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app/app_scope.dart';
import '../app/app_state.dart';
import '../backend/native_backend.dart';
import '../data/catalog_maintenance.dart';
import '../data/library.dart' show PhotoSort;
import '../data/library_location.dart';
import '../features/editor/edit_settings_dialog.dart';
import '../features/organize/reorganize_controller.dart';
import '../features/organize/storage_scheme_modal.dart';
import '../features/people/face_ingestion.dart';
import '../features/people/people_scope.dart';
import '../theme/tokens.dart';

class _MenuEntry {
  const _MenuEntry({
    required this.label,
    this.shortcut,
    this.isSeparator = false,
    this.checked,
    this.onTap,
  });

  factory _MenuEntry.sep() => const _MenuEntry(label: '', isSeparator: true);

  final String label;
  final String? shortcut;
  final bool isSeparator;
  final bool? checked;
  final VoidCallback? onTap;
}

class PabloMenuBar extends StatefulWidget {
  const PabloMenuBar({super.key});

  @override
  State<PabloMenuBar> createState() => _PabloMenuBarState();
}

class _PabloMenuBarState extends State<PabloMenuBar> {
  String? _open;

  Map<String, List<_MenuEntry>> _menus(
    PabloAppState st,
    VoidCallback? onScanFaces,
  ) =>
      {
        'File': const [
          _MenuEntry(label: 'Add Folder to Pablo…'),
          _MenuEntry(label: 'Import From…'),
          _MenuEntry(label: '', isSeparator: true),
          _MenuEntry(label: 'Export as Web Page…'),
          _MenuEntry(label: 'Print…'),
          _MenuEntry(label: '', isSeparator: true),
          _MenuEntry(label: 'Exit'),
        ],
        'Edit': [
          // Live file-op undo (shares the UndoStack with Cmd/Ctrl+Z); label
          // names the op it would reverse. Display-only when the stack is
          // empty. Redo stays display-only (no redo by design).
          _MenuEntry(
            label: st.undoStack.top == null
                ? 'Undo'
                : 'Undo ${st.undoStack.top!.label}',
            shortcut: 'Ctrl+Z',
            onTap: st.undoStack.top == null
                ? null
                : () => undoLastFileOp(context, st),
          ),
          const _MenuEntry(label: 'Redo', shortcut: 'Ctrl+Y'),
          _MenuEntry.sep(),
          const _MenuEntry(label: 'Select All', shortcut: 'Ctrl+A'),
          const _MenuEntry(label: 'Deselect All'),
        ],
        'View': [
          _MenuEntry(
            label: 'Folder Sort: Tree View',
            checked: st.folderSort == FolderSort.tree,
            onTap: () => st.setFolderSort(FolderSort.tree),
          ),
          _MenuEntry(
            label: 'Folder Sort: Alphabetical',
            checked: st.folderSort == FolderSort.alpha,
            onTap: () => st.setFolderSort(FolderSort.alpha),
          ),
          _MenuEntry.sep(),
          _MenuEntry(
            label: 'Sort Photos: Name',
            checked: st.photoSort == PhotoSort.name,
            onTap: () => st.setPhotoSort(PhotoSort.name),
          ),
          _MenuEntry(
            label: 'Sort Photos: Date',
            checked: st.photoSort == PhotoSort.date,
            onTap: () => st.setPhotoSort(PhotoSort.date),
          ),
          _MenuEntry(
            label: 'Sort Photos: Size',
            checked: st.photoSort == PhotoSort.size,
            onTap: () => st.setPhotoSort(PhotoSort.size),
          ),
          _MenuEntry(
            label: 'Sort Photos: Rating',
            checked: st.photoSort == PhotoSort.rating,
            onTap: () => st.setPhotoSort(PhotoSort.rating),
          ),
          _MenuEntry(
            label: 'Reverse Order',
            checked: st.sortReversed,
            onTap: () => st.setSortReversed(!st.sortReversed),
          ),
          _MenuEntry.sep(),
          const _MenuEntry(label: 'Thumbnail Size: Small'),
          const _MenuEntry(label: 'Thumbnail Size: Medium'),
          const _MenuEntry(label: 'Thumbnail Size: Large'),
          _MenuEntry.sep(),
          const _MenuEntry(label: 'Show Sidebar', checked: true),
          const _MenuEntry(label: 'Show Photo Tray', checked: true),
          _MenuEntry.sep(),
          _MenuEntry(
            label: 'Show Hidden Photos',
            checked: st.showHidden,
            onTap: () => st.setShowHidden(!st.showHidden),
          ),
        ],
        'People': [
          const _MenuEntry(label: 'Show People Panel'),
          _MenuEntry(
            label: onScanFaces == null
                ? 'Scan for Faces (needs native backend)'
                : 'Scan for Faces',
            onTap: onScanFaces,
          ),
        ],
        'Albums': const [
          _MenuEntry(label: 'New Album…'),
          _MenuEntry(label: 'New Smart Album…'),
        ],
        'Tools': [
          _MenuEntry(
            label: st.dupCount > 0
                ? 'Find Duplicates… (${st.dupCount})'
                : 'Find Duplicates…',
            onTap: st.openFindDuplicates,
          ),
          _MenuEntry.sep(),
          const _MenuEntry(label: 'Batch Edit…'),
          _MenuEntry(
            label: 'Organization Scheme…',
            onTap: () => openStorageSchemeBuilder(context, st),
          ),
          _MenuEntry(
            label: 'Compact Database',
            onTap: () => CatalogMaintenance.compact(
              backend: NativeBackendScope.maybeOf(context),
              appState: st,
            ),
          ),
          _MenuEntry(
            label: 'Relocate Library…',
            onTap: () => _relocateLibrary(context),
          ),
          _MenuEntry(
            label: 'Options…',
            onTap: () => showEditSettingsDialog(context),
          ),
        ],
        'Help': const [
          _MenuEntry(label: 'Pablo Help'),
          _MenuEntry(label: '', isSeparator: true),
          _MenuEntry(label: 'About Pablo'),
        ],
      };

  // Tools → Relocate Library…: pick a destination folder (native OS dialog),
  // copy the catalog there, and persist it. Takes effect on the next launch.
  Future<void> _relocateLibrary(BuildContext context) async {
    final backend = NativeBackendScope.maybeOf(context);
    if (backend == null) return;
    final dest = await getDirectoryPath(confirmButtonText: 'Relocate Here');
    if (dest == null || dest.isEmpty || !context.mounted) return;
    try {
      final moved =
          await LibraryLocation.relocate(backend: backend, destDir: dest);
      if (!context.mounted) return;
      await _info(
        context,
        moved ? 'Library relocated' : 'No change',
        moved
            ? 'The catalog was copied to:\n$dest\n\n'
                'Restart Pablo to use the new location.'
            : 'That is already the current catalog location.',
      );
    } catch (e) {
      if (!context.mounted) return;
      await _info(context, 'Could not relocate', '$e');
    }
  }

  Future<void> _info(BuildContext context, String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    // Enable "Scan for Faces" only with a live engine + library (null otherwise).
    final onScanFaces = FaceIngestion.scanLibraryAction(
      backend: NativeBackendScope.maybeOf(context),
      controller: PeopleScope.read(context),
      appState: st,
    );
    final menus = _menus(st, onScanFaces);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(
          bottom: BorderSide(color: PabloColors.borderSubtle),
        ),
      ),
      child: Row(
        children: menus.keys
            .map((label) => _MenuButton(
                  label: label,
                  active: _open == label,
                  onHover: (h) {
                    if (h && _open != null && _open != label) {
                      setState(() => _open = label);
                    }
                  },
                  onTap: () =>
                      setState(() => _open = _open == label ? null : label),
                  items: menus[label]!,
                  onDismiss: () => setState(() => _open = null),
                ))
            .toList(),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.label,
    required this.active,
    required this.onHover,
    required this.onTap,
    required this.items,
    required this.onDismiss,
  });

  final String label;
  final bool active;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;
  final List<_MenuEntry> items;
  final VoidCallback onDismiss;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  bool _hover = false;

  @override
  void didUpdateWidget(covariant _MenuButton old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active) _removeOverlay();
    if (!old.active && widget.active) _showOverlay();
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _showOverlay() {
    _overlay?.remove();
    _overlay = OverlayEntry(builder: (_) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
            ),
          ),
          Positioned(
            width: 240,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: const Offset(0, 30),
              child: Material(
                color: Colors.transparent,
                child: _MenuPanel(
                  items: widget.items,
                  onPick: () => widget.onDismiss(),
                ),
              ),
            ),
          ),
        ],
      );
    });
    // _showOverlay runs from didUpdateWidget, i.e. during the menu bar's build;
    // inserting an OverlayEntry synchronously there throws "markNeedsBuild
    // called during build". Defer the insert to just after the frame.
    final entry = _overlay!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlay == entry) Overlay.of(context).insert(entry);
    });
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _hover = true);
          widget.onHover(true);
        },
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: PabloDurations.hover,
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.lg,
              vertical: PabloSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: widget.active || _hover
                  ? PabloColors.backgroundHover
                  : Colors.transparent,
              borderRadius: PabloRadius.smAll,
            ),
            child: Text(
              widget.label,
              style: PabloTypography.sans(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: widget.active
                    ? PabloColors.textPrimary
                    : PabloColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.items, required this.onPick});
  final List<_MenuEntry> items;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PabloSpacing.sm),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.lgAll,
        boxShadow: PabloShadows.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((e) {
          if (e.isSeparator) {
            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: PabloSpacing.base,
                vertical: PabloSpacing.sm,
              ),
              height: 1,
              color: PabloColors.borderSubtle,
            );
          }
          return _MenuItem(entry: e, onPick: onPick);
        }).toList(),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({required this.entry, required this.onPick});
  final _MenuEntry entry;
  final VoidCallback onPick;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.entry.onTap?.call();
          widget.onPick();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xl,
            vertical: PabloSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _hover ? PabloColors.backgroundHover : Colors.transparent,
            borderRadius: PabloRadius.smAll,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Center(
                  child: widget.entry.checked == true
                      ? const Text(
                          '✓',
                          style: TextStyle(
                            color: PabloColors.accentPrimary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                ),
              ),
              Expanded(
                  child:
                      Text(widget.entry.label, style: PabloTypography.bodyMd)),
              if (widget.entry.shortcut != null) ...[
                const SizedBox(width: PabloSpacing.xxl),
                Text(widget.entry.shortcut!,
                    style: PabloTypography.mono(fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
