// external_actions_test.dart — the ExternalAction registry (the Dart half of
// the extension-point seam) + the openInDefaultApp command shapes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/data/sources/external_actions.dart';

void main() {
  test('built-ins are registered: reveal + open-default', () {
    final ids = ExternalActionRegistry.actions.map((a) => a.id).toList();
    expect(ids, contains('pablo.reveal'));
    expect(ids, contains('pablo.open-default'));
    // Reveal anchors to the clicked photo (file managers select ONE item).
    expect(
        ExternalActionRegistry.actions
            .firstWhere((a) => a.id == 'pablo.reveal')
            .singleTarget,
        isTrue);
  });

  test('register replaces an existing action by id (add-on re-registration)',
      () {
    final before = ExternalActionRegistry.actions.length;
    ExternalActionRegistry.register(ExternalAction(
      id: 'test.action',
      label: 'Test',
      iconCharacter: '🧪',
      run: (_) async {},
    ));
    ExternalActionRegistry.register(ExternalAction(
      id: 'test.action',
      label: 'Test v2',
      iconCharacter: '🧪',
      run: (_) async {},
    ));
    addTearDown(() =>
        ExternalActionRegistry.actions.removeWhere((a) => a.id == 'test.action'));
    expect(ExternalActionRegistry.actions.length, before + 1);
    expect(
        ExternalActionRegistry.actions
            .firstWhere((a) => a.id == 'test.action')
            .label,
        'Test v2');
  });

  test('openInDefaultApp issues one platform open per path', () async {
    final calls = <List<String>>[];
    final saved = openRunner;
    openRunner = (exe, args) async {
      calls.add([exe, ...args]);
      return ProcessResult(0, 0, '', '');
    };
    addTearDown(() => openRunner = saved);

    await openInDefaultApp(['/a/one.jpg', '/a/two.jpg']);
    expect(calls, hasLength(2));
    if (Platform.isMacOS) {
      expect(calls[0], ['open', '/a/one.jpg']);
      expect(calls[1], ['open', '/a/two.jpg']);
    } else if (Platform.isWindows) {
      expect(calls[0], ['cmd', '/c', 'start', '', '/a/one.jpg']);
    } else {
      expect(calls[0], ['xdg-open', '/a/one.jpg']);
    }
  });
}
