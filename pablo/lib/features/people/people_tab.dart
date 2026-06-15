import 'package:flutter/material.dart';

import '../../components/avatar.dart';
import '../../components/pablo_icon.dart';
import '../../data/mock/photo_factory.dart';
import '../../theme/tokens.dart';

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
    return Padding(
      padding: const EdgeInsets.only(top: PabloSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (confirmed.isNotEmpty) ...[
            _groupLabel('Confirmed', PabloColors.textMuted),
            for (final p in confirmed) _confirmedRow(p),
          ],
          if (unconfirmed.isNotEmpty) ...[
            if (confirmed.isNotEmpty) const SizedBox(height: PabloSpacing.lg),
            _groupLabel('Unconfirmed Suggestions', PabloColors.warningText),
            for (final p in unconfirmed) _unconfirmedRow(p),
          ],
        ],
      ),
    );
  }

  Widget _groupLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: PabloSpacing.base),
        child: Text(
          text.toUpperCase(),
          style: PabloTypography.sans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.05 * 10,
          ),
        ),
      );

  Widget _emptyState(String text, PabloIconName icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Opacity(
                opacity: 0.3,
                child: PabloIcon(icon, size: 28, color: PabloColors.textMuted),
              ),
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
          horizontal: PabloSpacing.lg,
          vertical: PabloSpacing.md,
        ),
        decoration: BoxDecoration(
          color: PabloColors.successBackground,
          border: Border.all(color: PabloColors.successBorder),
          borderRadius: PabloRadius.mdAll,
        ),
        child: Row(
          children: [
            PabloAvatar(name: p.name, hue: p.hue, size: 26),
            const SizedBox(width: PabloSpacing.lg),
            Expanded(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: PabloTypography.sans(
                  fontSize: 12.5,
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

  Widget _unconfirmedRow(TaggedPerson p) {
    final isUnknown = p.name.contains('Unknown');
    return Container(
      margin: const EdgeInsets.only(bottom: PabloSpacing.base),
      padding: const EdgeInsets.all(PabloSpacing.md),
      decoration: BoxDecoration(
        color: PabloColors.warningBackground,
        border: Border.all(color: PabloColors.warningBorder),
        borderRadius: PabloRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PabloAvatar(name: p.name, hue: p.hue, size: 26),
              const SizedBox(width: PabloSpacing.base),
              Expanded(
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    color: PabloColors.textSecondary,
                  ).copyWith(
                    fontStyle:
                        isUnknown ? FontStyle.italic : FontStyle.normal,
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
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: PabloColors.assignGreen,
                      borderRadius: PabloRadius.pillAll,
                    ),
                    child: Text(
                      '✓ Confirm ${p.name.split(' ').first}',
                      style: PabloTypography.sans(
                        fontSize: 11.5,
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
                  width: 34,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: PabloColors.ignoreRed,
                    borderRadius: PabloRadius.pillAll,
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
