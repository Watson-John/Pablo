// photo_context_menu.dart — the gallery right-click menu, extracted from the
// app shell. It is selection-aware: right-clicking a photo that is part of a
// multi-selection targets the WHOLE selection (labels carry the count), while
// right-clicking outside the selection targets just that photo. Reveal-on-disk
// and Set-as-Cover stay anchored to the clicked photo even for a group.
//
// The stateful actions live in the shell (_BodyState); this file owns only the
// item list + target computation, both of which are cheap and reviewable.

import 'package:flutter/widgets.dart';

import '../../app/app_state.dart';
import '../../components/context_menu.dart';
import '../../data/library.dart' show photosFor;
import '../../data/models.dart' show NavSection;
import '../../utils/reveal_in_file_manager.dart';

/// The photos an action should operate on: the current selection (in visible
/// order) when the clicked photo is part of a multi-selection, else just the
/// clicked photo. Ids are absolute file paths.
List<String> menuTargets(PabloAppState st, String clickedId) {
  if (st.selectedPhotos.length > 1 && st.selectedPhotos.contains(clickedId)) {
    final ordered = [
      for (final p in photosFor(st.selectedItem))
        if (st.selectedPhotos.contains(p.id)) p.id,
    ];
    // Fall back to the raw set if the section list doesn't contain them (e.g.
    // a virtual view mid-transition) so we never silently drop targets.
    return ordered.isEmpty ? st.selectedPhotos.toList() : ordered;
  }
  return [clickedId];
}

/// Callbacks the shell supplies; multi-capable ones take the target list.
class PhotoMenuActions {
  const PhotoMenuActions({
    required this.onView,
    required this.onToggleStar,
    required this.onToggleHidden,
    required this.onAddToAlbum,
    required this.onMoveToFolder,
    required this.onSetAlbumCover,
    required this.onRemoveFromAlbum,
    required this.onShowInPablo,
    required this.onSplitFolder,
    required this.onRename,
    required this.onExport,
    required this.onShare,
    required this.onPrint,
    required this.isStarred,
    required this.isHidden,
  });

  final void Function(String clickedId) onView;
  final void Function(List<String> ids) onToggleStar;
  final void Function(List<String> ids) onToggleHidden;
  final void Function(List<String> ids) onAddToAlbum;
  final void Function(List<String> ids) onMoveToFolder;
  final void Function(String clickedId) onSetAlbumCover;
  final void Function(List<String> ids) onRemoveFromAlbum;

  /// Jump to the clicked photo's home folder in the Folders view.
  final void Function(String clickedId) onShowInPablo;

  /// Split the current folder at the clicked photo into a new sibling.
  final void Function(String clickedId) onSplitFolder;

  /// Rename the target photos (single dialog for one, batch modal for many).
  final void Function(List<String> ids) onRename;

  /// §10 create/output: batch export / OS share sheet / print the targets.
  final void Function(List<String> ids) onExport;
  final void Function(List<String> ids) onShare;
  final void Function(List<String> ids) onPrint;
  final bool Function(String id) isStarred;
  final bool Function(String id) isHidden;
}

/// True when the gallery is showing a real on-disk folder (Folders nav on a
/// folder-path section) — where Split Folder Here applies.
bool isRealFolderView(PabloAppState st) =>
    st.activeSection == NavSection.folders && !isVirtualView(st);

/// True when [st] is showing a virtual view (search / album / smart / people /
/// timeline) rather than the real folder tree — where "Show in Pablo" helps.
bool isVirtualView(PabloAppState st) {
  if (st.activeSection != NavSection.folders) return true;
  final id = st.selectedItem;
  return id.startsWith('album:') ||
      id.startsWith('smart:') ||
      id.startsWith('search:') ||
      id.startsWith('tm') ||
      id.startsWith('ty');
}

/// Build + show the photo context menu at [position].
void showPhotoContextMenu(
  BuildContext context, {
  required Offset position,
  required String clickedId,
  required PabloAppState st,
  required int? albumId,
  required PhotoMenuActions actions,
}) {
  PabloContextMenu.show(
    context,
    position: position,
    items: buildPhotoMenuItems(
        st: st, clickedId: clickedId, albumId: albumId, actions: actions),
  );
}

/// The photo context-menu item list (pure — no overlay), so labels and
/// targeting are unit-testable without pumping the menu surface.
List<ContextMenuItem> buildPhotoMenuItems({
  required PabloAppState st,
  required String clickedId,
  required int? albumId,
  required PhotoMenuActions actions,
}) {
  final targets = menuTargets(st, clickedId);
  final n = targets.length;
  final multi = n > 1;
  String withCount(String verb, String noun) =>
      multi ? '$verb $n $noun' : verb;

  final anyUnstarred = targets.any((t) => !actions.isStarred(t));
  final anyVisible = targets.any((t) => !actions.isHidden(t));

  return [
      ContextMenuItem(
        label: 'View',
        iconCharacter: '👁',
        onPressed: () => actions.onView(clickedId),
      ),
      ContextMenuItem(
        label: 'Edit',
        iconCharacter: '✏️',
        onPressed: () => actions.onView(clickedId),
      ),
      if (isVirtualView(st))
        ContextMenuItem(
          label: 'Show in Pablo',
          iconCharacter: '📍',
          onPressed: () => actions.onShowInPablo(clickedId),
        ),
      ContextMenuItem.separator(),
      ContextMenuItem(
        label: anyUnstarred ? withCount('Star', 'Photos') : withCount('Unstar', 'Photos'),
        iconCharacter: anyUnstarred ? '★' : '☆',
        onPressed: () => actions.onToggleStar(targets),
      ),
      ContextMenuItem(
        label: multi ? 'Move $n Photos to Folder…' : 'Move to Folder…',
        iconCharacter: '📁',
        onPressed: () => actions.onMoveToFolder(targets),
      ),
      if (isRealFolderView(st))
        ContextMenuItem(
          label: 'Split Folder Here…',
          iconCharacter: '✂️',
          onPressed: () => actions.onSplitFolder(clickedId),
        ),
      ContextMenuItem(
        label: multi ? 'Batch Rename $n Photos…' : 'Rename…',
        iconCharacter: '🔤',
        onPressed: () => actions.onRename(targets),
      ),
      ContextMenuItem(
        label: multi ? 'Add $n Photos to Album' : 'Add to Album',
        iconCharacter: '+',
        onPressed: () => actions.onAddToAlbum(targets),
      ),
      if (albumId != null) ...[
        ContextMenuItem(
          label: 'Set as Album Cover',
          iconCharacter: '🖼',
          onPressed: () => actions.onSetAlbumCover(clickedId),
        ),
        ContextMenuItem(
          label: multi ? 'Remove $n from Album' : 'Remove from Album',
          iconCharacter: '−',
          onPressed: () => actions.onRemoveFromAlbum(targets),
        ),
      ],
      ContextMenuItem(
        label: anyVisible ? withCount('Hide', 'Photos') : withCount('Unhide', 'Photos'),
        iconCharacter: anyVisible ? '⊘' : '◉',
        onPressed: () => actions.onToggleHidden(targets),
      ),
      ContextMenuItem.separator(),
      ContextMenuItem(
        label: revealActionLabel(),
        iconCharacter: '📂',
        onPressed: () => revealInFileManager(clickedId),
      ),
      ContextMenuItem(
        label: withCount('Copy', 'Paths'),
        iconCharacter: '📋',
        onPressed: () => copyPathsToClipboard(targets),
      ),
      ContextMenuItem.separator(),
      // §10 create/output — batch-capable: acts on the whole selection.
      ContextMenuItem(
        label: multi ? 'Export $n Photos…' : 'Export…',
        iconCharacter: '⤓',
        onPressed: () => actions.onExport(targets),
      ),
      ContextMenuItem(
        label: multi ? 'Share $n Photos…' : 'Share…',
        iconCharacter: '📤',
        onPressed: () => actions.onShare(targets),
      ),
      ContextMenuItem(
        label: multi ? 'Print $n Photos…' : 'Print…',
        iconCharacter: '🖨',
        onPressed: () => actions.onPrint(targets),
      ),
      ContextMenuItem.separator(),
      ContextMenuItem(
        label: withCount('Delete', 'Photos'),
        iconCharacter: '🗑',
        destructive: true,
      ),
    ];
}
