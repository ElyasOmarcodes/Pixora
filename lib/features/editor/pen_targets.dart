import 'package:flutter/foundation.dart';

import '../../document/model/layer.dart';
import '../../document/model/layer_transform.dart';
import '../../editor/editor_controller.dart';
import '../../editor/tools/pen_tool.dart';

/// Pen editing a vector (path) layer. Live gestures are previews; each
/// finished gesture is one undo step.
class PathLayerPenTarget implements PenTarget {
  PathLayerPenTarget(this.editor, this.id);
  final EditorController editor;
  final String id;

  PathLayer? get _layer {
    final l = editor.document.layerById(id);
    return l is PathLayer ? l : null;
  }

  @override
  LayerTransform get transform =>
      _layer?.props.transform ?? const LayerTransform();

  @override
  List<PathContour> get contours => _layer?.contours ?? const [];

  @override
  void setContours(List<PathContour> contours, {bool live = false}) {
    PathLayer op(Layer l) => (l as PathLayer).copyWith(contours: contours);
    live
        ? editor.previewLayer(id, op)
        : editor.updateLayer(id, op, label: 'path');
  }

  @override
  void commit() {
    if (editor.isPreviewing) editor.commit('path');
  }
}

/// Pen drawing a bezier outline for a layer mask; the outline lives in the
/// mask brush until it is applied.
class MaskPenTarget extends ChangeNotifier implements PenTarget {
  MaskPenTarget(this.editor);
  final EditorController editor;

  List<PathContour> _contours = const [];

  @override
  LayerTransform get transform =>
      editor.selectedLayer?.props.transform ?? const LayerTransform();

  @override
  List<PathContour> get contours => _contours;

  @override
  void setContours(List<PathContour> contours, {bool live = false}) {
    _contours = contours;
    notifyListeners();
  }

  @override
  void commit() {}

  void clear() {
    _contours = const [];
    notifyListeners();
  }

  bool get hasShape => _contours.any((c) => c.nodes.length >= 3);
}
