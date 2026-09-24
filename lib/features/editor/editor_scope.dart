import 'package:flutter/widgets.dart';

import '../../editor/editor_controller.dart';

/// Which contextual tool panel is open.
enum ToolPanel {
  addShape,
  background,
  font,
  fill,
  stroke,
  shadow,
  adjust,
  filters,
  opacity,
  arrange,
  shapeStyle,
  grid,
  snap,
}

/// What pointer input on the canvas does.
enum ToolMode {
  /// Select, move, resize and rotate layers.
  move,

  /// Pan and zoom only (layers can't be picked).
  hand,

  /// Edit grid lines and guides (layers can't be picked).
  grid,
}

/// Editor UI state that is not part of the document (and therefore not
/// undoable): open panel, active tool mode, layer list visibility.
class EditorUiState extends ChangeNotifier {
  ToolPanel? _panel;
  bool _showLayers = false;
  ToolMode _mode = ToolMode.move;

  ToolPanel? get panel => _panel;
  bool get showLayers => _showLayers;
  ToolMode get mode => _mode;

  set mode(ToolMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }

  set panel(ToolPanel? p) {
    if (_panel == p) return;
    _panel = p;
    notifyListeners();
  }

  void togglePanel(ToolPanel p) => panel = _panel == p ? null : p;

  set showLayers(bool v) {
    if (_showLayers == v) return;
    _showLayers = v;
    notifyListeners();
  }
}

class EditorScope extends InheritedWidget {
  const EditorScope({
    super.key,
    required this.controller,
    required this.ui,
    required super.child,
  });

  final EditorController controller;
  final EditorUiState ui;

  static EditorScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorScope>()!;

  @override
  bool updateShouldNotify(EditorScope old) =>
      controller != old.controller || ui != old.ui;
}
