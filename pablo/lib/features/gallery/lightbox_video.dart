// lightbox_video.dart — in-app video playback for the lightbox (§11).
//
// video_player has an AVFoundation backend on macOS but no desktop Linux/Windows
// implementation, so playback is gated on Platform.isMacOS; elsewhere we show
// the poster frame (via PhotoSurface) with an "unavailable here" hint. The
// player surface sits on the same dark canvas as _LightboxImage, with a
// play/pause + scrubber + mute bar that shares the lightbox's auto-hide chrome.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart' show Engine;
import 'package:video_player/video_player.dart';

import '../../backend/native_backend.dart';
import '../../components/pablo_button.dart';
import '../../components/pablo_icon.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';
import '../video/trim_controller.dart';
import 'photo_surface.dart';

class LightboxVideo extends StatefulWidget {
  const LightboxVideo({required this.photo, super.key});
  final Photo photo;

  @override
  State<LightboxVideo> createState() => _LightboxVideoState();
}

class _LightboxVideoState extends State<LightboxVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  TrimController? _trim;

  bool get _supported => Platform.isMacOS;

  Engine? get _engine => NativeBackendScope.maybeOf(context)?.engine;

  @override
  void initState() {
    super.initState();
    if (_supported) _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.file(File(widget.photo.filePath));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      final durMs = c.value.duration.inMilliseconds;
      // Load any saved trim (catalog) and start playback inside the window.
      final saved = _engine?.videoGetTrim(assetIdFor(widget.photo.id));
      _trim = TrimController(
        durationMs: durMs,
        range: saved == null
            ? const TrimRange()
            : TrimRange(startMs: saved.startMs, endMs: saved.endMs),
      );
      await c.setLooping(!_trim!.range.isSet); // we loop manually when trimmed
      if (_trim!.range.isSet) {
        await c.seekTo(Duration(milliseconds: _trim!.startMs));
      }
      setState(() => _ready = true);
      await c.play();
      c.addListener(_tick);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _tick() {
    final c = _controller;
    final t = _trim;
    // Enforce the trim window: loop back to start when we pass the end.
    if (c != null && t != null && t.range.isSet && c.value.isInitialized) {
      final pos = c.value.position.inMilliseconds;
      final r = t.onTick(pos, loop: true);
      if (r.posMs != pos) c.seekTo(Duration(milliseconds: r.posMs));
    }
    if (mounted) setState(() {}); // repaint the scrubber
  }

  void _setTrimStart() {
    final c = _controller, t = _trim;
    if (c == null || t == null) return;
    t.setStart(c.value.position.inMilliseconds);
    _saveTrim();
    setState(() {});
  }

  void _setTrimEnd() {
    final c = _controller, t = _trim;
    if (c == null || t == null) return;
    t.setEnd(c.value.position.inMilliseconds);
    _saveTrim();
    setState(() {});
  }

  void _clearTrim() {
    final t = _trim;
    if (t == null) return;
    t.range = const TrimRange();
    _saveTrim();
    _controller?.setLooping(true);
    setState(() {});
  }

  void _saveTrim() {
    final t = _trim;
    if (t == null) return;
    _engine?.videoSetTrim(assetIdFor(widget.photo.id), t.range.startMs,
        t.range.endMs);
    _controller?.setLooping(!t.range.isSet);
  }

  Future<void> _exportClip() async {
    final t = _trim;
    final eng = _engine;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (t == null || eng == null || !t.range.isSet) return;
    final sep = Platform.pathSeparator;
    final src = widget.photo.filePath;
    final dot = src.lastIndexOf('.');
    final ext = dot >= 0 ? src.substring(dot) : '.mp4';
    final stem = dot >= 0 ? src.substring(0, dot) : src;
    final dst = '$stem-clip$ext';
    final req = eng.videoExportTrimmed(
      srcPath: src,
      dstPath: dst,
      startMs: t.startMs,
      endMs: t.range.endMs,
    );
    messenger?.showSnackBar(SnackBar(
      content: Text(req == 0
          ? 'Trimmed export is unavailable on this build.'
          : 'Exporting clip to ${dst.split(sep).last}…'),
    ));
  }

  @override
  void didUpdateWidget(covariant LightboxVideo old) {
    super.didUpdateWidget(old);
    // Filmstrip navigation swaps the photo without remounting; reload the file.
    if (old.photo.filePath != widget.photo.filePath) {
      _controller?.removeListener(_tick);
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _failed = false;
      _trim = null;
      if (_supported) _init();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_tick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_ready) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    // No playback backend, or init failed → poster + hint.
    if (!_supported || _failed) {
      return _PosterFallback(
        photo: widget.photo,
        message: _supported
            ? 'This video could not be played.'
            : 'Video playback is available on macOS.',
      );
    }
    final c = _controller;
    if (!_ready || c == null) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GestureDetector(
              onTap: _togglePlay,
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                child: ClipRRect(
                  borderRadius: PabloRadius.lgAll,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          ),
          const SizedBox(height: PabloSpacing.lg),
          _Controls(controller: c, onToggle: _togglePlay),
          if (_trim != null) ...[
            const SizedBox(height: PabloSpacing.base),
            _TrimBar(
              trim: _trim!,
              onSetStart: _setTrimStart,
              onSetEnd: _setTrimEnd,
              onClear: _clearTrim,
              onExport: _exportClip,
            ),
          ],
        ],
      ),
    );
  }
}

/// Trim controls: mark the current position as start/end (Picasa
/// moviestart/movieend), clear, and export the clip. Start snaps to a keyframe
/// on export (noted in the copy).
class _TrimBar extends StatelessWidget {
  const _TrimBar({
    required this.trim,
    required this.onSetStart,
    required this.onSetEnd,
    required this.onClear,
    required this.onExport,
  });
  final TrimController trim;
  final VoidCallback onSetStart;
  final VoidCallback onSetEnd;
  final VoidCallback onClear;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final set = trim.range.isSet;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Row(
        children: [
          PabloButton(
            label: 'Set start',
            variant: PabloButtonVariant.secondary,
            onPressed: onSetStart,
          ),
          const SizedBox(width: PabloSpacing.base),
          PabloButton(
            label: 'Set end',
            variant: PabloButtonVariant.secondary,
            onPressed: onSetEnd,
          ),
          const SizedBox(width: PabloSpacing.base),
          if (set)
            Text(
              'Trim ${_fmt(trim.startMs)}–${_fmt(trim.endMs)}',
              style: PabloTypography.mono(
                  fontSize: 10.5, color: PabloColors.selectionPrimary),
            )
          else
            Text('No trim',
                style: PabloTypography.sans(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
          const Spacer(),
          if (set) ...[
            PabloButton(
              label: 'Clear',
              variant: PabloButtonVariant.ghost,
              onPressed: onClear,
            ),
            const SizedBox(width: PabloSpacing.base),
            PabloButton(label: 'Export clip…', onPressed: onExport),
          ],
        ],
      ),
    );
  }

  static String _fmt(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.onToggle});
  final VideoPlayerController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final v = controller.value;
    final pos = v.position;
    final dur = v.duration;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Row(
        children: [
          _IconBtn(
            icon: v.isPlaying ? PabloIconName.pause : PabloIconName.playFill,
            onTap: onToggle,
          ),
          const SizedBox(width: PabloSpacing.base),
          Text(
            _fmt(pos),
            style: PabloTypography.mono(
                fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: PabloSpacing.base),
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: PabloColors.selectionPrimary,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ),
          Text(
            _fmt(dur),
            style: PabloTypography.mono(
                fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: PabloSpacing.base),
          _IconBtn(
            icon: v.volume == 0 ? PabloIconName.unlock : PabloIconName.lock,
            onTap: () => controller.setVolume(v.volume == 0 ? 1 : 0),
            tooltip: v.volume == 0 ? 'Unmute' : 'Mute',
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
  final PabloIconName icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: PabloIcon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.photo, required this.message});
  final Photo photo;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ClipRRect(
              borderRadius: PabloRadius.lgAll,
              child: PhotoSurface(photo: photo, targetW: 1280, targetH: 1280),
            ),
          ),
          const SizedBox(height: PabloSpacing.lg),
          Text(
            message,
            style: PabloTypography.sans(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
