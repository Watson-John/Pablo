// InheritedNotifier that exposes the global PabloAppState to descendants.

import 'package:flutter/material.dart';

import 'app_state.dart';

class AppScope extends InheritedNotifier<PabloAppState> {
  const AppScope({
    required PabloAppState super.notifier,
    required super.child,
    super.key,
  });

  static PabloAppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope missing in widget tree');
    return scope!.notifier!;
  }

  /// Read-only access — does not subscribe to rebuilds.
  static PabloAppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'AppScope missing in widget tree');
    return scope!.notifier!;
  }
}
