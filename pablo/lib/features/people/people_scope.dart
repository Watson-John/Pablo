// InheritedNotifier exposing the PeopleController to the People-section
// widgets. Read only by sidebar People rows, the People scroll view, the
// Unnamed Faces page, and the info-panel People tab — keeping `of` confined
// to those widgets so a face `changes` event doesn't rebuild the gallery.

import 'package:flutter/material.dart';

import 'people_controller.dart';

class PeopleScope extends InheritedNotifier<PeopleController> {
  const PeopleScope({
    required PeopleController super.notifier,
    required super.child,
    super.key,
  });

  /// Subscribes to controller changes (rebuilds on `changes` events).
  static PeopleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<PeopleScope>();
    assert(scope?.notifier != null, 'PeopleScope missing in widget tree');
    return scope!.notifier!;
  }

  /// Read-only access — does not subscribe to rebuilds.
  static PeopleController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<PeopleScope>();
    assert(scope?.notifier != null, 'PeopleScope missing in widget tree');
    return scope!.notifier!;
  }
}
