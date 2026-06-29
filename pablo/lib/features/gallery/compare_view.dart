// CompareView — 2-up side-by-side photo comparison with synced (or unlinked)
// pan/zoom.
//
// Each pane contains the photo at its true aspect inside an [InteractiveViewer]
// (a built-in, no new dependency). When linked, both panes share ONE
// TransformationController so panning/zooming one moves the other in lockstep;
// the link toggle swaps to per-pane controllers for independent inspection.
// Opened from the tray with 2+ photos selected; mounted full-region like the
// lightbox. Esc closes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/pablo_icon.dart';
import '../../data/library.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'photo_surface.dart';

class CompareView extends StatefulWidget {
  const CompareView({required this.ids, required this.onClose, super.key});

  /// The photos to compare; the first two are shown side by side.
  final List<String> ids;
  final VoidCallback onClose;

  @override
  State<CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<CompareView> {
  // Shared transform drives both panes when [_linked]; per-pane controllers
  // take over when unlinked.
  final TransformationController _shared = TransformationController();
  final TransformationController _a = TransformationController();
  final TransformationController _b = TransformationController();
  final FocusNode _focus = FocusNode();
  bool _linked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _shared.dispose();
    _a.dispose();
    _b.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleLink() {
    setState(() {
      if (_linked) {
        // Unlinking: seed both panes from the shared transform so they don't
        // jump.
        _a.value = _shared.value.clone();
        _b.value = _shared.value.clone();
      } else {
        // Relinking: adopt the left pane's transform as the shared one.
        _shared.value = _a.value.clone();
      }
      _linked = !_linked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final photos = <Photo>[
      for (final id in widget.ids.take(2))
        if (photoById(id) case final p?) p,
    ];

    // Escape closes. Routed through CallbackShortcuts (the Actions layer)
    // because Focus.onKeyEvent doesn't reliably receive Escape on desktop;
    // autofocus makes the freshly-mounted view own the keyboard immediately.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Container(
          color: PabloColors.lightboxBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(),
              Expanded(
                child: photos.length < 2
                    ? Center(
                        child: Text(
                          'Select two photos to compare.',
                          style: PabloTypography.sans(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _ComparePane(
                              photo: photos[0],
                              controller: _linked ? _shared : _a,
                            ),
                          ),
                          Container(
                            width: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          Expanded(
                            child: _ComparePane(
                              photo: photos[1],
                              controller: _linked ? _shared : _b,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PabloSpacing.xxl,
        PabloSpacing.lg,
        PabloSpacing.xxl,
        PabloSpacing.md,
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onClose,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: PabloSpacing.xxl),
                height: 32,
                decoration: BoxDecoration(
                  color: PabloColors.selectionPrimary,
                  borderRadius: PabloRadius.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PabloIcon(
                      PabloIconName.arrowLeft,
                      size: 14,
                      color: PabloColors.textOnAccent,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Back',
                      style: PabloTypography.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PabloColors.textOnAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: PabloSpacing.xl),
          Text(
            'Compare',
            style: PabloTypography.sans(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const Spacer(),
          _LinkToggle(linked: _linked, onTap: _toggleLink),
        ],
      ),
    );
  }
}

/// One comparison pane: the photo contained at its true aspect inside an
/// [InteractiveViewer] for pan/zoom.
class _ComparePane extends StatelessWidget {
  const _ComparePane({required this.photo, required this.controller});
  final Photo photo;
  final TransformationController controller;

  @override
  Widget build(BuildContext context) {
    final exif = getPhotoExif(photo.id);
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : 600.0;
        final maxH = c.maxHeight.isFinite ? c.maxHeight : 600.0;
        final known = exif.width > 0 && exif.height > 0;
        final aspect = known ? exif.width / exif.height : 4 / 3;
        // Contain the image at its true aspect within the pane.
        var dW = maxW - 24;
        var dH = dW / aspect;
        if (dH > maxH - 24) {
          dH = maxH - 24;
          dW = dH * aspect;
        }
        return InteractiveViewer(
          transformationController: controller,
          minScale: 1.0,
          maxScale: 8.0,
          clipBehavior: Clip.hardEdge,
          child: Center(
            child: SizedBox(
              width: dW.clamp(1.0, maxW),
              height: dH.clamp(1.0, maxH),
              child: ClipRRect(
                borderRadius: PabloRadius.mdAll,
                child: PhotoSurface(
                  key: ValueKey(photo.id),
                  photo: photo,
                  targetW: 1280,
                  targetH: 1280,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Link/unlink toggle for synced pan/zoom — a small pill that reads "Synced"
/// (blue, active) or "Independent" (muted).
class _LinkToggle extends StatefulWidget {
  const _LinkToggle({required this.linked, required this.onTap});
  final bool linked;
  final VoidCallback onTap;

  @override
  State<_LinkToggle> createState() => _LinkToggleState();
}

class _LinkToggleState extends State<_LinkToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.linked;
    final bg = active
        ? (_hover
            ? PabloColors.selectionPrimaryHover
            : PabloColors.selectionPrimary)
        : Colors.white.withValues(alpha: _hover ? 0.14 : 0.08);
    final fg =
        active ? PabloColors.textOnAccent : Colors.white.withValues(alpha: 0.7);
    return Tooltip(
      message: active ? 'Pan & zoom synced' : 'Pan & zoom independent',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: PabloDurations.hover,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.lg),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: PabloRadius.pillAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PabloIcon(
                  active ? PabloIconName.lock : PabloIconName.unlock,
                  size: 14,
                  color: fg,
                ),
                const SizedBox(width: PabloSpacing.sm),
                Text(
                  active ? 'Synced' : 'Independent',
                  style: PabloTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
