// Face Groups tab of the Unnamed Faces page — similarity-cluster grid with
// inline naming cards; extracted from unnamed_faces_page.dart.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../../app/app_scope.dart';
import '../../../components/autocomplete_input.dart';
import '../../../components/pablo_icon.dart';
import '../../../data/library.dart';
import '../../../data/models.dart';
import '../../../theme/tokens.dart';
import '../face_palette.dart';
import '../face_thumb.dart';
import '../people_scope.dart';

class GroupsTab extends StatelessWidget {
  const GroupsTab({
    super.key,
    required this.active,
    required this.done,
    required this.names,
    required this.coverOf,
    required this.onAssign,
    required this.onIgnore,
  });
  final List<UnnamedFace> active;
  final List<UnnamedFace> done;
  final Map<String, String> names;
  final FaceRow? Function(UnnamedFace) coverOf;
  final void Function(String, String) onAssign;
  final ValueChanged<String> onIgnore;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(PabloSpacing.xxl, PabloSpacing.xxl,
              PabloSpacing.xxl, PabloSpacing.xl),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Grouped by similarity. Type a name below each face — suggestions appear as you type. Click ✕ to ignore.',
              style: PabloTypography.sans(
                fontSize: 12,
                color: PabloColors.textSecondary,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              PabloSpacing.xxl, 0, PabloSpacing.xxl, PabloSpacing.xxl),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 126,
              mainAxisExtent: 152,
              crossAxisSpacing: PabloSpacing.base,
              mainAxisSpacing: PabloSpacing.base,
            ),
            itemCount: active.length + done.length,
            itemBuilder: (context, i) {
              final inActive = i < active.length;
              final f = inActive ? active[i] : done[i - active.length];
              return Align(
                alignment: Alignment.topLeft,
                child: GroupCard(
                  key: ValueKey(f.id),
                  face: f,
                  done: !inActive,
                  name: names[f.id],
                  cover: coverOf(f),
                  onAssign: inActive ? (n) => onAssign(f.id, n) : (_) {},
                  onIgnore: inActive ? () => onIgnore(f.id) : () {},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class GroupCard extends StatefulWidget {
  const GroupCard({
    super.key,
    required this.face,
    required this.done,
    required this.name,
    required this.cover,
    required this.onAssign,
    required this.onIgnore,
  });
  final UnnamedFace face;
  final bool done;
  final String? name;
  final FaceRow? cover;
  final ValueChanged<String> onAssign;
  final VoidCallback onIgnore;

  @override
  State<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<GroupCard> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.name ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Open the source photo this face was cropped from in the lightbox. The
  /// ingestion run registered each scanned asset's path, so we resolve the
  /// cover face's assetId → path → Photo and hand it to the lightbox.
  void _openFullImage() {
    final cover = widget.cover;
    if (cover == null) return;
    final path = PeopleScope.read(context).assetPath(cover.assetId);
    if (path == null || photoById(path) == null) return;
    AppScope.of(context).openLightbox(path);
  }

  @override
  Widget build(BuildContext context) {
    final tile = faceTileGradient(widget.face.hue);
    return SizedBox(
      width: 110,
      child: Container(
        decoration: BoxDecoration(
          color: widget.done
              ? PabloColors.successBackground
              : PabloColors.backgroundSurface,
          border: Border.all(
            color: widget.done
                ? PabloColors.successBorder
                : PabloColors.borderSubtle,
          ),
          borderRadius: PabloRadius.lgAll,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          // Hug the content (image + name field) instead of stretching to the
          // fixed grid-cell height, which left a gap under the name field.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  if (widget.cover != null)
                    Positioned.fill(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _openFullImage,
                          child: FaceThumb(
                            face: widget.cover!,
                            size: 110,
                            borderRadius: BorderRadius.zero,
                            hue: widget.face.hue,
                            // The card already has an inline name field + click
                            // to open, so don't stack a hover "Name…" on top.
                            showHoverLabel: false,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Container(decoration: BoxDecoration(gradient: tile)),
                    const Center(
                      child: PabloIcon(
                        PabloIconName.person,
                        size: 28,
                        color: PabloColors.tileGlyph,
                      ),
                    ),
                  ],
                  if (widget.done)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PabloSpacing.md,
                          vertical: 3,
                        ),
                        color: PabloColors.success,
                        child: Text(
                          widget.name ?? '',
                          textAlign: TextAlign.center,
                          style: PabloTypography.sans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: PabloColors.textOnAccent,
                          ),
                        ),
                      ),
                    )
                  else
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: widget.onIgnore,
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: PabloColors.ignoreRed.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '✕',
                            style: TextStyle(
                              color: PabloColors.textOnAccent,
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.done)
              // Borderless field connected to the image with a single divider,
              // so the card has one outer outline instead of nested boxes.
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: PabloColors.borderSubtle),
                  ),
                ),
                child: AutocompleteInput(
                  controller: _ctl,
                  placeholder: 'Name…',
                  bordered: false,
                  suggestions: [
                    for (final p in PeopleScope.read(context).people()) p.name
                  ],
                  onSubmit: (v) => widget.onAssign(v),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
