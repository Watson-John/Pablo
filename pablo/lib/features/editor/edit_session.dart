// EditSession — the shared, mutable edit state for the photo currently open in
// the lightbox. The edit panel (sidebar replacement) mutates it; the lightbox
// image renders a live preview from it. Created per-asset by [EditSessionScope]
// and exposed to both siblings via an [InheritedNotifier].

import 'package:flutter/widgets.dart';
import 'package:photo_native/photo_native.dart';

import '../../data/app_config.dart';
import '../../utils/sidecar_paths.dart';
import 'edit_spec.dart';
import 'edits_store.dart';

class EditSession extends ChangeNotifier {
  EditSession({
    required this.engine,
    required this.assetId,
    required this.path,
    required EditSpec saved,
    required this.contentRev,
  })  : _saved = saved,
        spec = saved.clone(),
        _savedEncoded = saved.encode();

  final Engine? engine;
  final int assetId;
  final String path;

  /// The working copy the panel mutates and the preview renders.
  EditSpec spec;

  EditSpec _saved; // last persisted/loaded spec (the revert/dirty baseline)
  String _savedEncoded;
  int contentRev; // current saved content_rev (0 = unedited)

  /// Bumped on every working-spec change so the preview surface can debounce.
  int specRevision = 0;

  /// The active geometry tool ('crop' / 'straighten'), or a deferred tool
  /// ('heal' / 'redeye'), or null. Shared so the panel sets it and the lightbox
  /// shows the matching overlay. Rotate/flip are instant actions, not modes.
  String? activeTool;

  void setTool(String? t) {
    if (activeTool == t) return;
    activeTool = t;
    notifyListeners();
  }

  // ── Geometry actions ────────────────────────────────────────────────────
  void rotate(int quarterTurnsClockwise) => mutate(
      (s) => s.rot90 = ((s.rot90 + quarterTurnsClockwise) % 4 + 4) % 4);
  void toggleFlipH() => mutate((s) => s.flipH = !s.flipH);
  void toggleFlipV() => mutate((s) => s.flipV = !s.flipV);
  void setStraighten(double deg) => mutate((s) => s.straighten = deg);
  void setCrop(double l, double t, double w, double h) => mutate((s) {
        s.cropL = l;
        s.cropT = t;
        s.cropW = w;
        s.cropH = h;
      });
  void clearCrop() => mutate((s) {
        s.cropL = 0;
        s.cropT = 0;
        s.cropW = 1;
        s.cropH = 1;
      });

  // ── Curves ──────────────────────────────────────────────────────────────
  void setCurve(List<Offset> points) => mutate((s) => s.curve = points);
  void resetCurve() => mutate((s) => s.curve = <Offset>[]);

  // ── Retouch (red-eye / heal) ────────────────────────────────────────────
  void addRedeye(EditRegion r) => mutate((s) => s.redeye.add(r));
  void addHeal(EditRegion r) => mutate((s) => s.heal.add(r));

  /// Auto-detect red-eye from the asset's stored face landmarks and add a dab for
  /// each red eye (same non-destructive redeye list as manual dabs). The working
  /// spec is passed along so the regions come back mapped through any active
  /// geometry (crop/rotate/flip/straighten) — landmarks live in original-image
  /// space. Dabs that duplicate an existing dab are skipped, so pressing Auto
  /// twice doesn't stack corrections. Returns the number added — 0 when none are
  /// red or the face models are unavailable (Linux/Windows), in which case the
  /// caller should nudge the user to the brush.
  int autoRedeye() {
    final eng = engine;
    if (eng == null) return 0;
    final found = eng.detectRedeye(assetId, path, spec: spec.encode());
    if (found.isEmpty) return 0;
    var added = 0;
    mutate((s) {
      for (final f in found) {
        final dup = s.redeye.any((e) {
          final dx = e.x - f.x, dy = e.y - f.y;
          final tol = 0.75 * (e.r > f.r ? e.r : f.r);
          return dx * dx + dy * dy < tol * tol;
        });
        if (!dup) {
          s.redeye.add(EditRegion(x: f.x, y: f.y, r: f.r));
          added++;
        }
      }
    });
    return added;
  }

  /// Undo the most recent dab of the given tool ('redeye' / 'heal'); no-op when
  /// that list is empty. Drives the panel's per-tool Undo affordance.
  void undoRetouch(String tool) => mutate((s) {
        final list = tool == 'redeye' ? s.redeye : s.heal;
        if (list.isNotEmpty) list.removeLast();
      });

  /// Remove one specific dab (per-eye veto, à la Picasa's per-correction X).
  void removeRetouchAt(String tool, int index) => mutate((s) {
        final list = tool == 'redeye' ? s.redeye : s.heal;
        if (index >= 0 && index < list.length) list.removeAt(index);
      });
  void clearRetouch(String tool) => mutate((s) {
        final list = tool == 'redeye' ? s.redeye : s.heal;
        list.clear();
      });

  // ── Text overlays ───────────────────────────────────────────────────────
  void addText(TextOverlay t) => mutate((s) => s.texts.add(t));
  void updateText(int index, void Function(TextOverlay) f) => mutate((s) {
        if (index >= 0 && index < s.texts.length) f(s.texts[index]);
      });
  void removeText(int index) => mutate((s) {
        if (index >= 0 && index < s.texts.length) s.texts.removeAt(index);
      });

  /// Encoded working spec (what we send to preview / save).
  String get encoded => spec.encode();

  /// Unsaved changes pending vs. the last saved/loaded baseline.
  bool get isDirty => spec.encode() != _savedEncoded;

  /// The asset has a persisted edit on disk (drives "Revert to Original").
  bool get hasSavedEdits => !_saved.isIdentity;

  /// Nothing to save and nothing to reset (footer disabled state).
  bool get isNeutral => spec.isIdentity && !isDirty;

  void mutate(void Function(EditSpec) f) {
    f(spec);
    specRevision++;
    notifyListeners();
  }

  void setFilter(String id) => mutate((s) => s.filter = id);

  void toggleAutoFix() => mutate((s) => s.autoFix = !s.autoFix);

  /// Discard all working adjustments back to neutral (footer "Reset"). Does not
  /// touch the catalog — Save (→ identity, which reverts) or "Revert to
  /// Original" persist the change.
  void resetAdjustments() {
    spec.reset();
    specRevision++;
    notifyListeners();
  }

  /// Persist the working spec. Returns the new content_rev (0 if it cleared to
  /// identity). Updates the baseline + the shared [EditsStore] so the gallery
  /// repaints. No-op without an engine.
  int save() {
    final eng = engine;
    if (eng == null) return contentRev;
    final encoded = spec.encode();
    final rev = eng.setAssetEdits(assetId, encoded);
    _saved = spec.clone();
    _savedEncoded = _saved.encode();
    contentRev = rev;
    EditsStore.instance.setRev(assetId, rev, edited: !_saved.isIdentity);
    // layeredTiff save mode: also write the self-contained file beside the photo
    // (page 0 edited, page 1 untouched original, spec embedded).
    if (!_saved.isIdentity &&
        AppConfig.load().editSaveMode == EditSaveMode.layeredTiff) {
      eng.saveLayered(
          srcPath: path, dstPath: layeredDestFor(path), spec: encoded);
    }
    notifyListeners();
    return rev;
  }

  /// Export a flattened full-res copy to [dstPath] (Save as Copy). Returns the
  /// request id (0 if no engine); a PhotoEventKind.exportComplete event fires.
  int exportCopy(String dstPath, {int quality = 92}) {
    final eng = engine;
    if (eng == null) return 0;
    return eng.exportAsset(
        srcPath: path, dstPath: dstPath, spec: spec.encode(), quality: quality);
  }

  /// The `<name>.pablo.tif` path beside a source file, for the layered save.
  /// Delegates to the shared helper so the move service relocates the exact
  /// same sidecar path when the photo itself moves.
  static String layeredDestFor(String src) => layeredTiffPathFor(src);

  /// Revert to the original: clears the saved edit and the working spec.
  void revertToOriginal() {
    final eng = engine;
    if (eng != null) eng.revertAsset(assetId);
    spec.reset();
    _saved = EditSpec();
    _savedEncoded = '';
    contentRev = EditsStore.instance.revOf(assetId); // keep a fresh rev to repaint
    EditsStore.instance.clear(assetId);
    specRevision++;
    notifyListeners();
  }
}

/// Inherited access to the current [EditSession]. Null when no photo is open.
class EditSessionScope extends InheritedNotifier<EditSession> {
  const EditSessionScope({
    super.key,
    required EditSession session,
    required super.child,
  }) : super(notifier: session);

  static EditSession? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EditSessionScope>()?.notifier;

  static EditSession? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditSessionScope>()?.notifier;
}

/// Owns the per-asset [EditSession] lifecycle: loads the saved spec for the
/// current lightbox asset and rebuilds the session when the asset changes.
class EditSessionProvider extends StatefulWidget {
  const EditSessionProvider({
    required this.engine,
    required this.assetId,
    required this.path,
    required this.child,
    super.key,
  });

  final Engine? engine;
  final int assetId;
  final String path;
  final Widget child;

  @override
  State<EditSessionProvider> createState() => _EditSessionProviderState();
}

class _EditSessionProviderState extends State<EditSessionProvider> {
  late EditSession _session = _load();

  EditSession _load() {
    final eng = widget.engine;
    final saved = eng != null
        ? EditSpec.decode(eng.assetEdits(widget.assetId))
        : EditSpec();
    final rev = eng != null ? eng.assetContentRev(widget.assetId) : 0;
    return EditSession(
      engine: eng,
      assetId: widget.assetId,
      path: widget.path,
      saved: saved,
      contentRev: rev,
    );
  }

  @override
  void didUpdateWidget(covariant EditSessionProvider old) {
    super.didUpdateWidget(old);
    if (old.assetId != widget.assetId || old.path != widget.path) {
      _session.dispose();
      _session = _load();
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      EditSessionScope(session: _session, child: widget.child);
}
