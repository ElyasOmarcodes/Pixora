import '../document/model/document.dart';

/// A point in the editing history: the document plus what was selected.
class HistoryEntry {
  const HistoryEntry(this.document, this.selection, this.label);
  final PixDocument document;

  /// Selected layer ids, primary (most recently selected) last.
  final List<String> selection;

  /// Human-readable description of the edit that led *away* from this state
  /// (shown as "Undo <label>").
  final String label;
}

/// Snapshot-based undo/redo.
///
/// Because documents are immutable and share unchanged layers and assets,
/// storing whole snapshots is cheap and makes undo impossible to get wrong:
/// there is no inverse operation to write for each command.
class History {
  History({this.limit = 150});

  final int limit;
  final List<HistoryEntry> _undo = [];
  final List<HistoryEntry> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;
  int get length => _undo.length;

  void push(HistoryEntry before) {
    _undo.add(before);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Returns the state to restore, recording [current] for redo.
  HistoryEntry? undo(HistoryEntry current) {
    if (_undo.isEmpty) return null;
    final prev = _undo.removeLast();
    _redo.add(HistoryEntry(current.document, current.selection, prev.label));
    return prev;
  }

  HistoryEntry? redo(HistoryEntry current) {
    if (_redo.isEmpty) return null;
    final next = _redo.removeLast();
    _undo.add(HistoryEntry(current.document, current.selection, next.label));
    return next;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
