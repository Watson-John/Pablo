// undo_stack.dart — session-scoped undo for FILE operations only (moves,
// splits, renames). Each entry is one reversible MoveService batch; catalog
// organize state (stars/tags/albums) is out of scope. No redo — undoing an
// undo is just a fresh operation.
//
// Two consumers share the same entries:
//   * Cmd/Ctrl+Z and Edit→Undo take the newest op via [pop].
//   * A result snackbar's Undo action targets ITS op via [remove] first, so a
//     later Cmd+Z can never double-reverse a batch the snackbar already undid.

import 'package:flutter/foundation.dart';

import 'library_mover.dart';

/// One reversible file-operation batch.
class UndoableFileOp {
  const UndoableFileOp({
    required this.label,
    required this.applied,
    this.createdDirs = const [],
  });

  /// Human-readable, e.g. 'Move 3 photos' — shown as 'Undo Move 3 photos'.
  final String label;

  /// The successfully-applied moves (from → to). Failed rows are never
  /// recorded here, so undo only touches files this op actually moved.
  final List<MoveResult> applied;

  /// Directories the op created (deepest last); undo removes them again if
  /// they are empty.
  final List<String> createdDirs;
}

class UndoStack extends ChangeNotifier {
  /// Session cap — the oldest op falls off past this.
  static const int cap = 50;

  final List<UndoableFileOp> _ops = [];

  UndoableFileOp? get top => _ops.isEmpty ? null : _ops.last;
  bool get isEmpty => _ops.isEmpty;
  int get length => _ops.length;

  void push(UndoableFileOp op) {
    _ops.add(op);
    if (_ops.length > cap) _ops.removeRange(0, _ops.length - cap);
    notifyListeners();
  }

  /// Take the newest op off the stack (the Cmd+Z path). Null when empty.
  UndoableFileOp? pop() {
    if (_ops.isEmpty) return null;
    final op = _ops.removeLast();
    notifyListeners();
    return op;
  }

  /// Remove a specific op (the snackbar-undo path). False when it was already
  /// consumed — the caller must then skip the reversal.
  bool remove(UndoableFileOp op) {
    final removed = _ops.remove(op);
    if (removed) notifyListeners();
    return removed;
  }

  void clear() {
    if (_ops.isEmpty) return;
    _ops.clear();
    notifyListeners();
  }
}
