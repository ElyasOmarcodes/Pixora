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
}

/// Editor UI state that is not part of the document (and therefore not
/// undoable): open panel, overlays, layer list visibility.
class EditorUiState extends ChangeNotifier {
  ToolPanel? _panel;
  bool _showLayers = false;
  bool _showGrid = false;

  ToolPanel? get panel => _panel;
  bool get showLayers => _showLayers;
  bool get showGrid => _showGrid;

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

  void toggleGrid() {
    _showGrid = !_showGrid;
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
