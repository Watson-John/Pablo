import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../components/pablo_badge.dart';
import '../../components/pablo_icon.dart';
import '../../data/photo_factory.dart';
import '../../theme/tokens.dart';
import 'shared.dart';

class PeopleTab extends StatefulWidget {
  const PeopleTab({required this.photoId, super.key});
  final String photoId;
  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  late List<TaggedPerson> _people = getPhotoPeople(widget.photoId);

  @override
  void didUpdateWidget(covariant PeopleTab old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) {
      _people = getPhotoPeople(widget.photoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = _people.where((p) => p.confirmed).toList();
    final unconfirmed = _people.where((p) => !p.confirmed).toList();
    if (_people.isEmpty) {
      return _emptyState('No people tagged\nin this photo', PabloIconName.person);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (confirmed.isNotEmpty) ...[
          const InfoSectionHeader('Confirmed'),
          for (final p in confirmed) _confirmedRow(p),
          const SizedBox(height: PabloSpacing.lg),
        ],
        if (unconfirmed.isNotEmpty) ...[
          _unconfirmedHeader(),
          for (final p in unconfirmed) _unconfirmedRow(p),
        ],
      ],
    );
  }

  Widget _emptyState(String text, PabloIconName icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              PabloIcon(icon, size: 28, color: PabloColors.textMuted),
              const SizedBox(height: PabloSpacing.base),
              Text(
                text,
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

  Widget _confirmedRow(TaggedPerson p) => Container(
        margin: const EdgeInsets.only(bottom: PabloSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.base,
          vertical: PabloSpacing.sm + 1,
        ),
        decoration: BoxDecoration(
          color: PabloColors.successBackground,
          border: Border.all(color: PabloColors.successBorder),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            PabloAvatar(name: p.name, hue: p.hue, size: 24),
            const SizedBox(width: PabloSpacing.base),
            Expanded(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: PabloTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Text(
              '✓',
              style: TextStyle(color: PabloColors.success, fontSize: 13),
            ),
          ],
        ),
      );

  Widget _unconfirmedHeader() => Padding(
        padding: const EdgeInsets.only(bottom: PabloSpacing.base),
        child: Row(
          children: [
            Text(
              'UNCONFIRMED',
              style: PabloTypography.sans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: PabloColors.warningText,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: PabloSpacing.md),
            PabloBadge.warning(),
          ],
        ),
      );

  Widget _unconfirmedRow(TaggedPerson p) {
    return Container(
      margin: const EdgeInsets.only(bottom: PabloSpacing.base),
      padding: const EdgeInsets.all(PabloSpacing.base),
      decoration: BoxDecoration(
        color: PabloColors.warningBackground,
        border: Border.all(color: PabloColors.warningBorder),
        borderRadius: PabloRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PabloAvatar(name: p.name, hue: p.hue, size: 24),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12,
                    color: PabloColors.textSecondary,
                    fontWeight: p.name.contains('Unknown')
                        ? FontWeight.w400
                        : FontWeight.w400,
                  ).copyWith(
                    fontStyle: p.name.contains('Unknown')
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PabloSpacing.base),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => p.confirmed = true),
                  child: Container(
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: PabloColors.assignGreen,
                      borderRadius: PabloRadius.panelAll,
                    ),
                    child: Text(
                      '✓ ${p.name.split(' ').first}',
                      style: PabloTypography.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: PabloColors.textOnAccent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PabloSpacing.sm),
              GestureDetector(
                onTap: () => setState(() => _people.remove(p)),
                child: Container(
                  width: 30,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: PabloColors.ignoreRed,
                    borderRadius: PabloRadius.panelAll,
                  ),
                  child: Text(
                    '✕',
                    style: PabloTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PabloColors.textOnAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
