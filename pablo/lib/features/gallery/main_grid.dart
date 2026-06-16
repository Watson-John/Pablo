// MainGrid — dispatches by activeSection.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../data/mock/mock_data.dart';
import '../../data/models.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';
import '../map/map_page.dart';
import '../people/people_scroll_view.dart';
import 'photo_thumb.dart';
import 'section_scroll_view.dart';
import '../people/unnamed_faces_page.dart';

class MainGrid extends StatelessWidget {
  const MainGrid({this.onPhotoSecondary, super.key});

  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final section = st.activeSection;
    if (section == NavSection.folders) {
      final all = <FolderNode>[];
      void collect(List<FolderNode> list) {
        for (final f in list) {
          if (f.children.isNotEmpty) {
            collect(f.children);
          } else {
            all.add(f);
          }
        }
      }
      collect(kFolders);
      return SectionScrollView(
        sections: [
          for (final f in all)
            GallerySectionData(
              id: f.id,
              title: f.name,
              subtitle: f.path.isNotEmpty ? f.path : f.date,
            ),
        ],
        onPhotoSecondary: onPhotoSecondary,
      );
    }
    if (section == NavSection.albums) {
      return SectionScrollView(
        sections: [
          for (final a in kAlbums)
            GallerySectionData(
              id: a.id,
              title: a.name,
              subtitle: 'Created ${a.created}',
            ),
        ],
        onPhotoSecondary: onPhotoSecondary,
      );
    }
    if (section == NavSection.timeline) {
      return SectionScrollView(
        sections: [
          for (final t in kTimelineMonths)
            GallerySectionData(
              id: t.id,
              title: t.label,
              subtitle: '${t.count} photos',
            ),
        ],
        onPhotoSecondary: onPhotoSecondary,
      );
    }
    if (section == NavSection.unnamed) {
      return const UnnamedFacesPage();
    }
    if (section == NavSection.people) {
      return PeopleScrollView(onPhotoSecondary: onPhotoSecondary);
    }
    if (section == NavSection.map) {
      return const MapPage();
    }

    // Fallback: single-section grid.
    final photos = photosFor(st.selectedItem);
    return Container(
      color: PabloColors.backgroundSurface,
      child: ListView(
        padding: const EdgeInsets.all(PabloSpacing.xl),
        children: [
          Wrap(
            spacing: PabloSpacing.base,
            runSpacing: PabloSpacing.base,
            children: photos.map((p) {
              return PhotoThumb(
                photo: p,
                size: st.thumbSize,
                selected: st.selectedPhotos.contains(p.id),
                inTray: st.trayPhotos.contains(p.id),
                onTap: (e) {
                  st.selectPhoto(
                    p.id,
                    ctrl: HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed,
                    shift: HardwareKeyboard.instance.isShiftPressed,
                    contextPhotoIds: photos.map((x) => x.id).toList(),
                  );
                },
                onDoubleTap: () => st.openLightbox(p.id),
                onAddToTray: () => st.addToTray(p.id),
                onSecondaryTap: (pos) => onPhotoSecondary?.call(pos, p.id),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
