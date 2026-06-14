// Inspector "Info" tab (Pablo v4): a photo preview row, icon-led property rows,
// a Manage-details card, and People / Tags preview sections.

import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';
import 'shared.dart';

class InfoTab extends StatelessWidget {
  const InfoTab({
    required this.photo,
    required this.onManage,
    required this.onGoToTab,
    super.key,
  });

  final Photo photo;
  final VoidCallback onManage;
  final void Function(String tab) onGoToTab;

  @override
  Widget build(BuildContext context) {
    final exif = getPhotoExif(photo.id);
    final tags = getPhotoTags(photo.id);
    final people = getPhotoPeople(photo.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preview + filename
        Padding(
          padding: const EdgeInsets.only(top: PabloSpacing.xl, bottom: PabloSpacing.base),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  gradient: photo.gradient,
                  borderRadius: PabloRadius.smAll,
                  border: Border.all(color: PabloColors.borderSubtle),
                ),
              ),
              const SizedBox(width: PabloSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      photo.label,
                      style: PabloTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InspectorLink('Open folder location',
                        fontSize: 11.5, onTap: () {}),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Properties
        MetaRow(
          icon: PabloIconName.calendar,
          label: 'Date taken',
          child: Text('${exif.date.replaceAll('-', '/')} · ${exif.time.substring(0, 5)}'),
        ),
        MetaRow(
          icon: PabloIconName.library,
          label: 'Size',
          child: Text('${exif.fileSize} · ${exif.width} × ${exif.height} · ${exif.format}'),
        ),
        MetaRow(
          icon: PabloIconName.camera,
          label: 'Camera',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exif.camera),
              const SizedBox(height: 2),
              Text(
                '${exif.aperture} · ${exif.shutter}s · ISO ${exif.iso} · ${exif.focalLength}',
                style: PabloTypography.mono(fontSize: 11.5, color: PabloColors.textSecondary),
              ),
            ],
          ),
        ),
        if (exif.location != null)
          MetaRow(
            icon: PabloIconName.map,
            label: 'Location',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exif.location!),
                const SizedBox(height: PabloSpacing.base),
                Container(
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE8E2D4), Color(0xFFC8BCA0)],
                    ),
                    border: Border.all(color: PabloColors.borderSubtle),
                    borderRadius: PabloRadius.mdAll,
                  ),
                  alignment: Alignment.center,
                  child: const PabloIcon(PabloIconName.map,
                      size: 22, color: PabloColors.accentPrimary),
                ),
              ],
            ),
          ),

        // Manage details card
        Padding(
          padding: const EdgeInsets.only(top: PabloSpacing.xxl),
          child: _ManageCard(onTap: onManage),
        ),

        // People preview
        SectionLabel('People',
            right: InspectorLink('Manage →', onTap: () => onGoToTab('people'))),
        if (people.isEmpty)
          _emptyHint('No people tagged')
        else
          Wrap(
            spacing: PabloSpacing.md,
            runSpacing: PabloSpacing.md,
            children: [
              for (final p in people.take(6)) _PersonPill(person: p),
              _AddPill(onTap: () => onGoToTab('people')),
            ],
          ),

        // Tags preview
        SectionLabel('Tags',
            right: InspectorLink('Manage →', onTap: () => onGoToTab('tags'))),
        if (tags.isEmpty)
          _emptyHint('No tags yet')
        else
          Wrap(
            spacing: PabloSpacing.sm,
            runSpacing: PabloSpacing.sm,
            children: [for (final t in tags.take(8)) _TagChip(label: t)],
          ),
      ],
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: PabloSpacing.sm),
        child: Text(
          text,
          style: PabloTypography.sans(
            fontSize: 11.5,
            color: PabloColors.textMuted,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
      );
}

class _ManageCard extends StatefulWidget {
  const _ManageCard({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_ManageCard> createState() => _ManageCardState();
}

class _ManageCardState extends State<_ManageCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: PabloDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.xl, vertical: PabloSpacing.lg),
          decoration: BoxDecoration(
            color: _hover
                ? PabloColors.backgroundHover
                : PabloColors.backgroundSurfaceAlt,
            border: Border.all(color: PabloColors.borderSubtle),
            borderRadius: PabloRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manage details',
                        style: PabloTypography.sans(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text('Edit camera, file & metadata fields',
                        style: PabloTypography.sans(
                            fontSize: 11, color: PabloColors.textMuted)),
                  ],
                ),
              ),
              const Text('→',
                  style: TextStyle(color: PabloColors.accentPrimary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonPill extends StatelessWidget {
  const _PersonPill({required this.person});
  final TaggedPerson person;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, PabloSpacing.lg, 3),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PabloAvatar(name: person.name, hue: person.hue, size: 22),
          const SizedBox(width: PabloSpacing.md),
          Text(person.name.split(' ').first,
              style: PabloTypography.sans(fontSize: 12)),
        ],
      ),
    );
  }
}

class _AddPill extends StatelessWidget {
  const _AddPill({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: PabloSpacing.lg, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(
                color: PabloColors.borderStrong, style: BorderStyle.solid),
            borderRadius: PabloRadius.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('+',
                  style: PabloTypography.sans(
                      fontSize: 14, color: PabloColors.textSecondary, height: 1)),
              const SizedBox(width: PabloSpacing.sm),
              Text('Add',
                  style: PabloTypography.sans(
                      fontSize: 12, color: PabloColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border.all(color: PabloColors.borderSubtle),
        borderRadius: PabloRadius.smAll,
      ),
      child: Text(label, style: PabloTypography.sans(fontSize: 11.5)),
    );
  }
}
