// Three slider variants:
//   PabloSlider     — generic min/max slider used for tweaks.
//   ThumbSlider     — snaps to a default value (controls-bar thumb size).
//   EditSlider      — bipolar [-100,100] with zero-snap (photo editor).

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Generic horizontal slider with copper-filled track.
class PabloSlider extends StatelessWidget {
  const PabloSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.width,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return _SliderBase(
      width: width,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }
}

/// ThumbSlider — snaps to a default value when dragged close (within 8 px).
/// Used for the controls-bar thumb-size slider.
class ThumbSlider extends StatelessWidget {
  const ThumbSlider({
    required this.value,
    required this.onChanged,
    required this.defaultValue,
    this.min = 60,
    this.max = 260,
    this.width = 100,
    super.key,
  });

  final double value;
  final double defaultValue;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return _SliderBase(
      width: width,
      value: value,
      min: min,
      max: max,
      defaultValue: defaultValue,
      snapDefault: true,
      onChanged: onChanged,
    );
  }
}

/// EditSlider — bipolar [-100,100] with a zero-snap and value readout.
class EditSlider extends StatelessWidget {
  const EditSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = -100,
    this.max = 100,
    this.step = 1,
    this.unit = '',
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final active = value != 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: PabloSpacing.xl - 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: PabloSpacing.sm + 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: PabloTypography.sans(
                      fontSize: 11.5,
                      color: PabloColors.textSecondary,
                    ),
                  ),
                ),
                GestureDetector(
                  onDoubleTap: () => onChanged(0),
                  child: SizedBox(
                    width: 34,
                    child: Text(
                      '${value > 0 ? '+' : ''}${value.toStringAsFixed(value == value.toInt() ? 0 : 1)}$unit',
                      textAlign: TextAlign.right,
                      style: PabloTypography.mono(
                        fontSize: 10.5,
                        color: active
                            ? PabloColors.accentPrimary
                            : PabloColors.textMuted,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _SliderBase(
            value: value,
            min: min,
            max: max,
            zeroSnap: min < 0 && max > 0,
            step: step,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SliderBase extends StatefulWidget {
  const _SliderBase({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.width,
    this.defaultValue,
    this.snapDefault = false,
    this.zeroSnap = false,
    this.step = 1,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final double? width;
  final double? defaultValue;
  final bool snapDefault;
  final bool zeroSnap;
  final double step;

  @override
  State<_SliderBase> createState() => _SliderBaseState();
}

class _SliderBaseState extends State<_SliderBase> {
  final GlobalKey _key = GlobalKey();

  double _pct(double v) =>
      ((v - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _update(double globalX) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(Offset(globalX, 0));
    final ratio = (local.dx / box.size.width).clamp(0.0, 1.0);
    double v = widget.min + ratio * (widget.max - widget.min);
    v = (v / widget.step).round() * widget.step;
    if (widget.snapDefault && widget.defaultValue != null) {
      final defPx = _pct(widget.defaultValue!) * box.size.width;
      if ((local.dx - defPx).abs() < 8) v = widget.defaultValue!;
    }
    if (widget.zeroSnap) {
      final zeroPx = _pct(0) * box.size.width;
      if ((local.dx - zeroPx).abs() < 8) v = 0;
    }
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _pct(widget.value);
    final zeroPct = widget.zeroSnap ? _pct(0) : 0.0;
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _update(d.globalPosition.dx),
      onTapDown: (d) => _update(d.globalPosition.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: widget.width,
          height: 16,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final thumbLeft = pct * w - 6;
            return Stack(
              key: _key,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 6,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: PabloColors.borderSubtle,
                      borderRadius: PabloRadius.smAll,
                    ),
                  ),
                ),
                if (widget.zeroSnap)
                  Positioned(
                    left: zeroPct * w,
                    top: 4,
                    child: Container(
                      width: 1,
                      height: 8,
                      color: PabloColors.borderStrong.withValues(alpha: 0.5),
                    ),
                  )
                else if (widget.value > widget.min)
                  Positioned(
                    left: 0,
                    top: 6,
                    child: Container(
                      width: pct * w,
                      height: 4,
                      decoration: BoxDecoration(
                        color: PabloColors.accentPrimary,
                        borderRadius: PabloRadius.smAll,
                      ),
                    ),
                  ),
                if (widget.zeroSnap && widget.value > 0)
                  Positioned(
                    left: zeroPct * w,
                    top: 6,
                    child: Container(
                      width: (pct - zeroPct) * w,
                      height: 4,
                      color: PabloColors.accentPrimary,
                    ),
                  ),
                if (widget.zeroSnap && widget.value < 0)
                  Positioned(
                    left: pct * w,
                    top: 6,
                    child: Container(
                      width: (zeroPct - pct) * w,
                      height: 4,
                      color: PabloColors.accentPrimary,
                    ),
                  ),
                if (widget.snapDefault && widget.defaultValue != null)
                  Positioned(
                    left: _pct(widget.defaultValue!) * w,
                    top: 3,
                    child: Container(
                      width: 1,
                      height: 10,
                      color: widget.value == widget.defaultValue
                          ? PabloColors.accentPrimary
                          : PabloColors.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                Positioned(
                  left: thumbLeft,
                  top: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: PabloColors.backgroundSurface,
                      border: Border.all(
                        color: widget.value == 0 && widget.zeroSnap
                            ? PabloColors.borderStrong
                            : PabloColors.accentPrimary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: PabloShadows.sm,
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
