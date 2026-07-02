// Unit tests for EditSession's dirty/baseline/reset logic (engine-free path).
// With a null engine, save()/revert() are no-ops on the catalog but the
// in-memory baseline + EditsStore bookkeeping still exercise here.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/features/editor/edit_session.dart';
import 'package:pablo/features/editor/edit_spec.dart';
import 'package:pablo/features/editor/edits_store.dart';

void main() {
  EditSession freshSession({EditSpec? saved}) => EditSession(
        engine: null,
        assetId: 1,
        path: '/lib/a.jpg',
        saved: saved ?? EditSpec(),
        contentRev: 0,
      );

  test('mutate marks dirty and bumps spec revision', () {
    final s = freshSession();
    expect(s.isDirty, isFalse);
    expect(s.isNeutral, isTrue);
    final before = s.specRevision;
    s.mutate((e) => e.exposure = 25);
    expect(s.isDirty, isTrue);
    expect(s.isNeutral, isFalse);
    expect(s.specRevision, greaterThan(before));
    expect(s.encoded, contains('exposure=25'));
  });

  test('resetAdjustments returns the working spec to neutral', () {
    final s = freshSession();
    s.mutate((e) => e.contrast = 40);
    s.setFilter('vivid');
    expect(s.isDirty, isTrue);
    s.resetAdjustments();
    expect(s.spec.isIdentity, isTrue);
    expect(s.encoded, isEmpty);
  });

  test('hasSavedEdits reflects the loaded baseline', () {
    final neutral = freshSession();
    expect(neutral.hasSavedEdits, isFalse);

    final edited = freshSession(saved: EditSpec(saturation: 30, filter: 'warm'));
    expect(edited.hasSavedEdits, isTrue);
    // The working copy starts equal to the baseline → not dirty.
    expect(edited.isDirty, isFalse);
    expect(edited.spec.saturation, closeTo(30, 1e-3));
  });

  test('retouch add / undo / clear mutate the working spec', () {
    final s = freshSession();
    s.addRedeye(EditRegion(x: 0.3, y: 0.4, r: 0.03));
    s.addRedeye(EditRegion(x: 0.6, y: 0.4, r: 0.03));
    s.addHeal(EditRegion(x: 0.5, y: 0.5, r: 0.05));
    expect(s.spec.redeye.length, 2);
    expect(s.spec.heal.length, 1);
    expect(s.isDirty, isTrue);
    expect(s.encoded, contains('redeye='));

    s.undoRetouch('redeye');
    expect(s.spec.redeye.length, 1);

    // Per-dab removal (the per-eye veto): out-of-range indices are safe no-ops.
    s.addRedeye(EditRegion(x: 0.7, y: 0.4, r: 0.03));
    s.removeRetouchAt('redeye', 0);
    expect(s.spec.redeye.length, 1);
    expect(s.spec.redeye.single.x, closeTo(0.7, 1e-6));
    s.removeRetouchAt('redeye', 5); // out of range → no-op
    s.removeRetouchAt('redeye', -1);
    expect(s.spec.redeye.length, 1);
    s.removeRetouchAt('redeye', 0);
    expect(s.spec.redeye, isEmpty);

    s.clearRetouch('heal');
    expect(s.spec.heal, isEmpty);

    s.clearRetouch('redeye');
    expect(s.spec.isIdentity, isTrue);
  });

  test('revertToOriginal clears working + baseline + store', () {
    EditsStore.instance.setRev(1, 3, edited: true);
    final s = freshSession(saved: EditSpec(exposure: 10));
    expect(s.hasSavedEdits, isTrue);
    s.revertToOriginal();
    expect(s.spec.isIdentity, isTrue);
    expect(s.hasSavedEdits, isFalse);
    expect(EditsStore.instance.isEdited(1), isFalse);
  });
}
