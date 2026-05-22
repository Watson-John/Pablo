// PhotoInfoPanel — 240 px right-side panel with People / Tags / Info tabs.

import 'package:flutter/material.dart';

import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'info_tab.dart';
import 'people_tab.dart';
import 'tags_tab.dart';

class PhotoInfoPanel extends StatelessWidget {
  const PhotoInfoPanel({
    required this.photo,
    required this.activeTab,
    required this.onClose,
    super.key,
  });

  final Photo? photo;
  final String activeTab; // 'people' | 'tags' | 'info'
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(left: BorderSide(color: PabloColors.borderSubtle)),
        boxShadow: PabloShadows.infoPanel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl,
              vertical: PabloSpacing.base,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    activeTab == 'people'
                        ? 'People'
                        : activeTab == 'tags'
                            ? 'Tags'
                            : 'Info',
                    style: PabloTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PabloColors.textSecondary,
                    ),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onClose,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      child: const PabloIcon(
                        PabloIconName.close,
                        size: 14,
                        color: PabloColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PabloSpacing.xl,
                PabloSpacing.xl,
                PabloSpacing.xl,
                18,
              ),
              child: photo == null
                  ? _empty(noun: _nounFor(activeTab))
                  : switch (activeTab) {
                      'people' => PeopleTab(photoId: photo!.id),
                      'tags' => TagsTab(photoId: photo!.id),
                      'info' => InfoTab(photo: photo!),
                      _ => const SizedBox.shrink(),
                    },
            ),
          ),
        ],
      ),
    );
  }

  static String _nounFor(String tab) {
    switch (tab) {
      case 'people':
        return 'people';
      case 'tags':
        return 'tags';
      case 'info':
        return 'EXIF info';
      default:
        return 'details';
    }
  }

  Widget _empty({required String noun}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Column(
            children: [
              const PabloIcon(
                PabloIconName.camera,
                size: 32,
                color: PabloColors.textMuted,
              ),
              const SizedBox(height: PabloSpacing.xl),
              Text(
                'Click a photo\nto see its $noun',
                textAlign: TextAlign.center,
                style: PabloTypography.sans(
                  fontSize: 12,
                  color: PabloColors.textMuted,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      );
}
