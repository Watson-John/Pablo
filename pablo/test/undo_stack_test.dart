// undo_stack_test.dart — UndoStack semantics (session file-op undo) plus the
// PabloAppState.remapPhotoIds bookkeeping every move flows through.

import 'package:flutter_test/flutter_test.dart';
import 'package:pablo/app/app_state.dart';
import 'package:pablo/data/library_mover.dart';
import 'package:pablo/data/undo_stack.dart';

UndoableFileOp op(String label) =>
    UndoableFileOp(label: label, applied: const <MoveResult>[]);

void main() {
  test('push/pop is LIFO and notifies', () {
    final stack = UndoStack();
    var notified = 0;
    stack.addListener(() => notified++);

    final a = op('a'), b = op('b');
    stack.push(a);
    stack.push(b);
    expect(stack.top, b);
    expect(stack.pop(), b);
    expect(stack.pop(), a);
    expect(stack.pop(), isNull);
    expect(notified, 4); // 2 pushes + 2 pops (empty pop doesn't notify)
  });

  test('remove targets a specific op; second consumer sees false', () {
    final stack = UndoStack();
    final a = op('a'), b = op('b');
    stack.push(a);
    stack.push(b);

    // Snackbar undoes ITS op (a) even though b is newer.
    expect(stack.remove(a), isTrue);
    expect(stack.top, b);
    // A Cmd+Z that already popped b means the snackbar's remove(b) is a no-op.
    expect(stack.pop(), b);
    expect(stack.remove(b), isFalse);
  });

  test('cap drops the oldest entries', () {
    final stack = UndoStack();
    for (var i = 0; i < UndoStack.cap + 10; i++) {
      stack.push(op('$i'));
    }
    expect(stack.length, UndoStack.cap);
    expect(stack.top!.label, '${UndoStack.cap + 9}');
  });

  test('remapPhotoIds follows selection, tray, anchor, and lightbox', () {
    final st = PabloAppState();
    st.selectedPhotos.addAll({'/lib/a.jpg', '/lib/b.jpg'});
    st.trayPhotos.addAll(['/lib/a.jpg', '/lib/c.jpg']);
    st.activePhotoId = '/lib/a.jpg';
    st.lightboxPhotoId = '/lib/b.jpg';

    st.remapPhotoIds({
      '/lib/a.jpg': '/sorted/a.jpg',
      '/lib/b.jpg': '/sorted/b.jpg',
    });

    expect(st.selectedPhotos, {'/sorted/a.jpg', '/sorted/b.jpg'});
    expect(st.trayPhotos, ['/sorted/a.jpg', '/lib/c.jpg']);
    expect(st.activePhotoId, '/sorted/a.jpg');
    expect(st.lightboxPhotoId, '/sorted/b.jpg');
  });
}
