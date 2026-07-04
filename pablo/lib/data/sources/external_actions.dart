// external_actions.dart — the Dart half of the extension-point story
// (docs/EXTENDING.md): user-visible actions that hand photos to something
// OUTSIDE Pablo (the file manager, another editor, a future "Open in
// Photoshop" add-on). The photo context menu renders whatever is registered
// here, so adding an action is one registry entry — no menu surgery.
//
// Registration is compile-time (boot) only for now; a future add-on SDK
// populates this from plugin manifests. NOT yet a stable third-party API.

import 'dart:io';

import '../../utils/reveal_in_file_manager.dart';

/// One external action. [run] receives the selection-aware target paths the
/// context menu computed (see menuTargets); [singleTarget] actions receive
/// only the clicked photo (e.g. reveal — file managers select ONE item).
class ExternalAction {
  const ExternalAction({
    required this.id,
    required this.label,
    required this.iconCharacter,
    required this.run,
    this.singleTarget = false,
    this.canRun = _always,
  });

  /// Stable identity, e.g. "pablo.reveal" / "com.example.open-photoshop".
  final String id;

  /// Menu label. Single-target actions show it as-is; multi-target actions
  /// get the selection count appended by the menu ("Open 3 Photos in …").
  final String label;
  final String iconCharacter;
  final bool singleTarget;
  final bool Function(List<String> paths) canRun;
  final Future<void> Function(List<String> paths) run;

  static bool _always(List<String> _) => true;
}

/// Process runner seam for [openInDefaultApp] tests (mirrors revealRunner).
Future<ProcessResult> Function(String exe, List<String> args) openRunner =
    (exe, args) => Process.run(exe, args);

/// Open each path in the OS default application (Preview/Photos viewer…).
Future<void> openInDefaultApp(List<String> paths) async {
  for (final p in paths) {
    if (Platform.isMacOS) {
      await openRunner('open', [p]);
    } else if (Platform.isWindows) {
      await openRunner('cmd', ['/c', 'start', '', p]);
    } else {
      await openRunner('xdg-open', [p]);
    }
  }
}

/// The registry the photo context menu renders. Order = menu order.
class ExternalActionRegistry {
  ExternalActionRegistry._();

  static final List<ExternalAction> actions = [
    ExternalAction(
      id: 'pablo.reveal',
      label: revealActionLabel(),
      iconCharacter: '📂',
      singleTarget: true,
      run: (paths) async {
        if (paths.isNotEmpty) await revealInFileManager(paths.first);
      },
    ),
    const ExternalAction(
      id: 'pablo.open-default',
      label: 'Open in Default App',
      iconCharacter: '↗️',
      run: openInDefaultApp,
    ),
  ];

  /// Add-on seam: idempotent by id so a re-registered action replaces itself.
  static void register(ExternalAction action) {
    actions.removeWhere((a) => a.id == action.id);
    actions.add(action);
  }
}
