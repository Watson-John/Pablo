// Status bar at the bottom: photo count · section title · thumb size readout.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    required this.photoCount,
    required this.sectionTitle,
    required this.thumbSize,
    this.filtered = false,
    this.totalCount = 0,
    super.key,
  });

  final int photoCount;
  final String sectionTitle;
  final double thumbSize;
  final bool filtered;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.xl),
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurfaceAlt,
        border: Border(top: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Row(
        children: [
          if (filtered)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$photoCount',
                    style: PabloTypography.sans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: PabloColors.accentPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' of $totalCount photos',
                    style: PabloTypography.sans(
                      fontSize: 11,
                      color: PabloColors.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            Text('$photoCount photos',
                style: PabloTypography.sans(
                  fontSize: 11,
                  color: PabloColors.textMuted,
                )),
          const SizedBox(width: PabloSpacing.xl),
          const _Sep(),
          const SizedBox(width: PabloSpacing.xl),
          Text(
            sectionTitle,
            style: PabloTypography.sans(
              fontSize: 11,
              color: PabloColors.textMuted,
            ),
          ),
          if (filtered) ...[
            const SizedBox(width: PabloSpacing.xl),
            Text(
              '· Filtered',
              style: PabloTypography.sans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: PabloColors.accentPrimary,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${thumbSize.toInt()}px',
            style: PabloTypography.mono(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Container(
        width: 2,
        height: 12,
        alignment: Alignment.center,
        child: Text(
          '·',
          style: PabloTypography.sans(
            fontSize: 11,
            color: PabloColors.borderSubtle,
          ),
        ),
      );
}
