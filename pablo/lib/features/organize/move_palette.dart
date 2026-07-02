// move_palette.dart — the keyboard-driven "Move to Folder" picker. Type to
// fuzzy-filter every known folder (pins first, then recent destinations, then
// fuzzy-ranked rest); ↑/↓ move the highlight, Enter picks, Esc cancels. When
// the query names a folder that doesn't exist, the last row offers to create
// it (relative to the library root, `/` for nesting) — the result flags it as
// new so the caller records it for undo.
//
// The ranking + new-folder resolution are pure functions ([rankFolders],
// [resolveNewFolderPath]) so they're unit-tested without pumping a dialog.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_text_field.dart';
import '../../data/boot.dart';
import '../../data/scheme_engine.dart' show hardenComponent;
import '../../theme/tokens.dart';
import '../../utils/fuzzy_match.dart';

/// A folder the user can move into.
class FolderCandidate {
  const FolderCandidate({required this.path, required this.name});
  final String path; // absolute directory path (== FolderNode.id)
  final String name; // leaf display name
}

/// What the palette resolved to.
class MoveDestination {
  const MoveDestination(this.dir, {required this.isNew});
  final String dir; // absolute destination directory
  final bool isNew; // caller must create it (and record for undo) when true
}

/// Rank [all] for [query]: pinned entries first, then recents, then the fuzzy
/// remainder. With an empty query the pinned+recent+alphabetical order shows.
/// Pins/recents are given as absolute paths; entries not in [all] are ignored.
List<FolderCandidate> rankFolders(
  String query,
  List<FolderCandidate> all, {
  List<String> pinned = const [],
  List<String> recents = const [],
}) {
  final byPath = {for (final f in all) f.path: f};
  final priority = <FolderCandidate>[];
  final seen = <String>{};
  for (final p in [...pinned, ...recents]) {
    final f = byPath[p];
    if (f != null && seen.add(p)) priority.add(f);
  }
  final rest = [for (final f in all) if (!seen.contains(f.path)) f];

  if (query.isEmpty) {
    final sortedRest = [...rest]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...priority, ...sortedRest];
  }
  // With a query, rank the priority set and the rest by fuzzy score but keep
  // priority ahead of an equally-scored ordinary folder.
  final rankedPriority =
      fuzzyRank(query, priority, (f) => f.path);
  final rankedRest = fuzzyRank(query, rest, (f) => f.path);
  return [...rankedPriority, ...rankedRest];
}

/// Resolve the typed [query] to an absolute directory under [libraryRoot].
/// Splits on `/`, hardens each component (drops empties, sanitizes reserved
/// names), and joins with the platform separator. Returns null when nothing
/// usable remains.
String? resolveNewFolderPath(String query, String libraryRoot) {
  final sep = Platform.pathSeparator;
  final parts = query
      .split(RegExp(r'[/\\]'))
      .map((s) => hardenComponent(s.trim()))
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  final base = libraryRoot.isEmpty ? '' : '$libraryRoot$sep';
  return '$base${parts.join(sep)}';
}

/// Show the palette. Returns the chosen destination (existing or to-be-created)
/// or null on cancel. [photoCount] tunes the title only.
Future<MoveDestination?> showMovePalette(
  BuildContext context, {
  required List<FolderCandidate> folders,
  required int photoCount,
  List<String> pinned = const [],
  List<String> recents = const [],
  String? libraryRoot,
}) {
  return showDialog<MoveDestination>(
    context: context,
    builder: (_) => _MovePalette(
      folders: folders,
      photoCount: photoCount,
      pinned: pinned,
      recents: recents,
      libraryRoot: libraryRoot ?? BootConfig.instance.libraryRoot,
    ),
  );
}

class _MovePalette extends StatefulWidget {
  const _MovePalette({
    required this.folders,
    required this.photoCount,
    required this.pinned,
    required this.recents,
    required this.libraryRoot,
  });

  final List<FolderCandidate> folders;
  final int photoCount;
  final List<String> pinned;
  final List<String> recents;
  final String libraryRoot;

  @override
  State<_MovePalette> createState() => _MovePaletteState();
}

class _MovePaletteState extends State<_MovePalette> {
  final _controller = TextEditingController();
  String _query = '';
  int _highlight = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<FolderCandidate> get _filtered => rankFolders(
        _query,
        widget.folders,
        pinned: widget.pinned,
        recents: widget.recents,
      );

  /// The optional create-new row's destination, or null when the query can't
  /// name a new folder or already matches an existing folder exactly.
  String? get _createPath {
    if (_query.trim().isEmpty) return null;
    final resolved = resolveNewFolderPath(_query, widget.libraryRoot);
    if (resolved == null) return null;
    if (widget.folders.any((f) => f.path == resolved)) return null;
    return resolved;
  }

  int get _rowCount => _filtered.length + (_createPath != null ? 1 : 0);

  void _move(int delta) {
    final n = _rowCount;
    if (n == 0) return;
    setState(() => _highlight = (_highlight + delta) % n);
    if (_highlight < 0) _highlight += n;
  }

  void _commit() {
    final createPath = _createPath;
    final filtered = _filtered;
    if (_highlight < filtered.length) {
      Navigator.of(context).pop(MoveDestination(filtered[_highlight].path,
          isNew: false));
    } else if (createPath != null) {
      Navigator.of(context).pop(MoveDestination(createPath, isNew: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final createPath = _createPath;
    final n = widget.photoCount;
    return Dialog(
      backgroundColor: PabloColors.backgroundSurface,
      shape: RoundedRectangleBorder(borderRadius: PabloRadius.panelAll),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _commit,
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Focus(
          autofocus: true,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(PabloSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Move $n photo${n == 1 ? '' : 's'} to…',
                        style: PabloTypography.sans(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: PabloSpacing.base),
                      PabloTextField(
                        controller: _controller,
                        autoFocus: true,
                        placeholder: 'Search folders or type a new name…',
                        onChanged: (v) => setState(() {
                          _query = v;
                          _highlight = 0;
                        }),
                        onSubmitted: (_) => _commit(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _rowCount,
                      itemBuilder: (context, i) {
                        final highlighted = i == _highlight;
                        if (i < filtered.length) {
                          final f = filtered[i];
                          return _Row(
                            icon: '📁',
                            title: f.name,
                            subtitle: f.path,
                            highlighted: highlighted,
                            onTap: () => Navigator.of(context)
                                .pop(MoveDestination(f.path, isNew: false)),
                          );
                        }
                        return _Row(
                          icon: '✨',
                          title: 'Create folder “${_query.trim()}”',
                          subtitle: createPath ?? '',
                          highlighted: highlighted,
                          onTap: () => Navigator.of(context).pop(
                              MoveDestination(createPath!, isNew: true)),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: PabloSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.highlighted,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color:
            highlighted ? PabloColors.selectionBackground : Colors.transparent,
        padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xl, vertical: PabloSpacing.base),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: PabloSpacing.base),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PabloTypography.sans(fontSize: 12.5)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PabloTypography.sans(
                            fontSize: 10.5, color: PabloColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
