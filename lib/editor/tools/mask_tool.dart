import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import '../../document/model/mask.dart';
import '../editor_controller.dart';
import 'editor_tool.dart';

/// How the mask tool draws.
enum MaskToolKind {
  /// Freehand brush.
  brush,

  /// Freehand closed area.
  lasso,

  /// Tap points to build a polygon, then apply it.
  pen,
}

/// Mask brush settings shared by the mask panel and the canvas tool.
class MaskBrush extends ChangeNotifier {
  MaskMode _mode = MaskMode.hide;
  MaskToolKind _kind = MaskToolKind.brush;
  double _size = 24;
  double _softness = 0.2;

  /// Pending pen points in document space.
  final List<Offset> penPoints = [];

  MaskMode get mode => _mode;
  MaskToolKind get kind => _kind;

  /// Brush diameter in screen pixels.
  double get size => _size;
  double get softness => _softness;

  set mode(MaskMode v) => _set(() => _mode = v);
  set kind(MaskToolKind v) => _set(() {
    _kind = v;
    penPoints.clear();
  });
  set size(double v) => _set(() => _size = v);
  set softness(double v) => _set(() => _softness = v);

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  void addPenPoint(Offset doc) => _set(() => penPoints.add(doc));
  void undoPenPoint() => _set(() {
    if (penPoints.isNotEmpty) penPoints.removeLast();
  });
  void clearPen() => _set(penPoints.clear);
}

/// Paints the selected layer's mask: hide or reveal parts of it with a
/// brush, a lasso or pen polygons. Two fingers still pan and zoom.
class MaskTool extends EditorTool {
  MaskTool(this.brush);

  final MaskBrush brush;
  List<Offset> _points = [];
  Offset? _cursor;
  String? _layerId;
  double _width = 1;

  @override
  String get id => 'mask';

  @override
  Listenable get repaint => brush;

  Layer? _target(ToolContext ctx) {
    final l = ctx.editor.selectedLayer;
    if (l == null || ctx.editor.hasMultiSelection) return null;
    return l;
  }

  double _layerScale(Layer l) {
    final t = l.props.transform;
    return math.max(0.0001, (t.scaleX.abs() + t.scaleY.abs()) / 2);
  }

  MaskStroke _stroke(MaskShape shape) => MaskStroke(
    mode: brush.mode,
    shape: shape,
    points: _points,
    width: _width,
    softness: brush.softness,
  );

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final l = _target(ctx);
    if (l == null) return;
    final doc = ctx.viewport.toDoc(screen);
    if (brush.kind == MaskToolKind.pen) {
      brush.addPenPoint(doc);
      ctx.requestRepaint();
      return;
    }
    if (brush.kind == MaskToolKind.brush) {
      _points = [l.props.transform.toLocal(doc)];
      _width = brush.size / ctx.viewport.scale / _layerScale(l);
      ctx.editor.addMaskStroke(l.id, _stroke(MaskShape.brush));
    }
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    if (d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad) {
      return false;
    }
    if (brush.kind == MaskToolKind.pen) return false;
    final l = _target(ctx);
    if (l == null) return false;
    _layerId = l.id;
    _width = brush.size / ctx.viewport.scale / _layerScale(l);
    _points = [
      l.props.transform.toLocal(ctx.viewport.toDoc(d.localFocalPoint)),
    ];
    _cursor = d.localFocalPoint;
    _preview(ctx);
    return true;
  }

  void _preview(ToolContext ctx) {
    final id = _layerId;
    if (id == null) return;
    final shape = brush.kind == MaskToolKind.lasso
        ? MaskShape.area
        : MaskShape.brush;
    if (shape == MaskShape.area && _points.length < 3) {
      ctx.requestRepaint();
      return;
    }
    ctx.editor.addMaskStroke(id, _stroke(shape), live: true);
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final id = _layerId;
    if (id == null) return;
    final l = ctx.editor.document.layerById(id);
    if (l == null) return;
    _cursor = d.localFocalPoint;
    final p = l.props.transform.toLocal(ctx.viewport.toDoc(d.localFocalPoint));
    final minStep = 1.5 / ctx.viewport.scale / _layerScale(l);
    if ((p - _points.last).distance < minStep) return;
    _points = [..._points, p];
    _preview(ctx);
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_layerId == null) return;
    if (ctx.editor.isPreviewing) {
      ctx.editor.commit('mask');
    }
    _layerId = null;
    _cursor = null;
    _points = [];
    ctx.requestRepaint();
  }

  /// Turns the pending pen points into a filled mask area.
  static void applyPen(EditorController editor, MaskBrush brush) {
    final l = editor.selectedLayer;
    if (l == null || brush.penPoints.length < 3) return;
    editor.addMaskStroke(
      l.id,
      MaskStroke(
        mode: brush.mode,
        shape: MaskShape.area,
        points: [for (final p in brush.penPoints) l.props.transform.toLocal(p)],
        softness: brush.softness,
      ),
    );
    brush.clearPen();
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    _cursor = screen;
    ctx.requestRepaint();
    return SystemMouseCursors.precise;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final color = brush.mode == MaskMode.hide
        ? const Color(0xFFFF4D6D)
        : const Color(0xFF22C55E);
    final vp = ctx.viewport;
    if (brush.kind == MaskToolKind.pen && brush.penPoints.isNotEmpty) {
      final pts = [for (final p in brush.penPoints) vp.toScreen(p)];
      final path = Path()..addPolygon(pts, brush.penPoints.length >= 3);
      canvas
        ..drawPath(path, Paint()..color = color.withValues(alpha: 0.18))
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color,
        );
      for (final p in pts) {
        canvas
          ..drawCircle(p, 6, Paint()..color = Colors.white)
          ..drawCircle(
            p,
            6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = color,
          );
      }
    }
    if (brush.kind == MaskToolKind.lasso && _points.length > 1) {
      final l = _layerId == null
          ? null
          : ctx.editor.document.layerById(_layerId);
      if (l != null) {
        final pts = [
          for (final p in _points) vp.toScreen(l.props.transform.toDocument(p)),
        ];
        canvas.drawPath(
          Path()..addPolygon(pts, false),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color,
        );
      }
    }
    final c = _cursor;
    if (c != null && brush.kind == MaskToolKind.brush) {
      canvas
        ..drawCircle(
          c,
          brush.size / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = Colors.white,
        )
        ..drawCircle(
          c,
          brush.size / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color,
        );
    }
  }
}
