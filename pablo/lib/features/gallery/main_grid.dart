// MainGrid — dispatches by activeSection.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../map/map_page.dart';
import '../people/people_scroll_view.dart';
import 'section_scroll_view.dart';
import '../people/unnamed_faces_page.dart';

class MainGrid extends StatelessWidget {
  const MainGrid({this.onPhotoSecondary, super.key});

  final void Function(Offset, String photoId)? onPhotoSecondary;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final section = st.activeSection;
    final lib = Library.instance;
    if (section == NavSection.folders) {
      if (lib.folderSections.isEmpty) {
        return _EmptyView(
          icon: PabloIconName.folder,
          message: libraryScanning
              ? 'Scanning your library…'
              : 'No photos found in the imported library.\nPoint Pablo at a folder with --dart-define=PABLO_LIBRARY_DIR=…',
        );
      }
      return SectionScrollView(
        sections: [
          for (final f in lib.folderSections)
            GallerySectionData(
              id: f.id,
              title: f.name,
              subtitle: f.path,
            ),
        ],
        onPhotoSecondary: onPhotoSecondary,
      );
    }
    if (section == NavSection.albums) {
      // Albums aren't a feature yet — nothing in the imported library is an
      // album, so this is an honest empty state rather than fabricated data.
      return const _EmptyView(
        icon: PabloIconName.albums,
        message: 'No albums yet.\nAlbums let you group photos by hand — coming soon.',
      );
    }
    if (section == NavSection.timeline) {
      if (lib.timelineMonths.isEmpty) {
        return const _EmptyView(
          icon: PabloIconName.calendar,
          message: 'No dated photos in the library.',
        );
      }
      return SectionScrollView(
        sections: [
          for (final t in lib.timelineMonths)
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

    // Fallback: the currently selected section as a single scroll view.
    return SectionScrollView(
      sections: [
        GallerySectionData(id: st.selectedItem, title: 'Photos'),
      ],
      onPhotoSecondary: onPhotoSecondary,
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.icon, required this.message});
  final PabloIconName icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PabloColors.backgroundSurface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(PabloSpacing.xxxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.35,
            child: PabloIcon(icon, size: 40, color: PabloColors.textMuted),
          ),
          const SizedBox(height: PabloSpacing.xl),
          Text(
            message,
            textAlign: TextAlign.center,
            style: PabloTypography.sans(
              fontSize: 13,
              color: PabloColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
