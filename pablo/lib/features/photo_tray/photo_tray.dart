// Photo tray — horizontal strip of selected/in-tray photos with lock + clear.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';

class PhotoTray extends StatelessWidget {
  const PhotoTray({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final trayHeight = st.trayHeight;
    final thumbH = trayHeight - 40;
    final thumbW = (thumbH * 1.35).round();

    // Resolve photo ids → Photo objects (look across all known photo sets).
    final ids = st.trayPhotos;

    return Container(
      height: trayHeight,
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: const Border(top: BorderSide(color: PabloColors.borderSubtle)),
        boxShadow: PabloShadows.trayTop,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Text.rich(
                  st.selectedPhotos.isNotEmpty
                      ? TextSpan(
                          children: [
                            TextSpan(
                              text: '${st.selectedPhotos.length}',
                              style: PabloTypography.sans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: PabloColors.accentPrimary,
                              ),
                            ),
                            TextSpan(
                              text: ' selected',
                              style: PabloTypography.sans(
                                fontSize: 12,
                                color: PabloColors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      : ids.isNotEmpty
                          ? TextSpan(
                              text: '${ids.length} photo${ids.length == 1 ? '' : 's'} in tray',
                              style: PabloTypography.sans(
                                fontSize: 12,
                                color: PabloColors.textSecondary,
                              ),
                            )
                          : TextSpan(
                              text: 'Photo Tray',
                              style: PabloTypography.sans(
                                fontSize: 12,
                                color: PabloColors.textSecondary,
                              ),
                            ),
                ),
                const SizedBox(width: PabloSpacing.base),
                _LockToggle(
                  locked: st.trayLocked,
                  onToggle: st.toggleTrayLock,
                ),
                const SizedBox(width: PabloSpacing.base),
                if (ids.isNotEmpty)
                  PabloButton(
                    label: 'Clear',
                    variant: PabloButtonVariant.danger,
                    size: PabloButtonSize.xs,
                    onPressed: st.clearTray,
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: PabloColors.backgroundSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: PabloSpacing.xl,
                vertical: 7,
              ),
              child: ids.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Double-click photos to add to tray',
                        style: PabloTypography.sans(
                          fontSize: 12,
                          color: PabloColors.textMuted,
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: ids.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: PabloSpacing.md),
                      itemBuilder: (_, i) {
                        final id = ids[i];
                        final photo = _findPhoto(id);
                        if (photo == null) return const SizedBox.shrink();
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: thumbW.toDouble(),
                              height: thumbH,
                              decoration: BoxDecoration(
                                gradient: photo.gradient,
                                borderRadius: PabloRadius.mdAll,
                                border: Border.all(
                                  color: PabloColors.borderSubtle,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => st.removeFromTray(id),
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  alignment: Alignment.center,
                                  decoration: const BoxDecoration(
                                    color: PabloColors.ignoreRed,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Text(
                                    '✕',
                                    style: TextStyle(
                                      color: PabloColors.textOnAccent,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Find a Photo by id by scanning the cached photo sets.
  static _Photo? _findPhoto(String id) {
    // Photo ids are like "<setId>-<index>", split → setId.
    final dash = id.lastIndexOf('-');
    if (dash < 0) return null;
    final setId = id.substring(0, dash);
    for (final photo in photosFor(setId)) {
      if (photo.id == id) {
        return _Photo(photo.gradient);
      }
    }
    return null;
  }
}

class _Photo {
  _Photo(this.gradient);
  final LinearGradient gradient;
}

class _LockToggle extends StatelessWidget {
  const _LockToggle({required this.locked, required this.onToggle});
  final bool locked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Tooltip(
          message:
              locked ? 'Unlock selection (clicks will deselect)' : 'Lock selection (clicks won\'t deselect)',
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: locked
                  ? PabloColors.accentPrimary
                  : PabloColors.backgroundSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: locked
                    ? PabloColors.accentPrimary
                    : PabloColors.borderStrong,
              ),
              boxShadow: PabloShadows.sm,
            ),
            child: PabloIcon(
              locked ? PabloIconName.lock : PabloIconName.unlock,
              size: 16,
              color: locked
                  ? PabloColors.textOnAccent
                  : PabloColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
