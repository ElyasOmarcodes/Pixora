import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import '../../document/model/mask.dart';
import '../../document/render/document_renderer.dart';
import '../editor_controller.dart';
import 'editor_tool.dart';

/// How the mask tool draws.
enum MaskToolKind {
  /// Freehand brush in the current grey.
  brush,

  /// Freehand brush in the opposite grey (Photoshop's eraser on a mask).
  eraser,

  /// Drag a linear / radial gradient.
  gradient,

  /// Freehand closed area.
  lasso,

  /// Bezier outline, then fill it.
  pen,
}

/// Mask brush settings shared by the mask panel and the canvas tool.
class MaskBrush extends ChangeNotifier {
  MaskToolKind _kind = MaskToolKind.brush;
  double _size = 24;
  double _softness = 0.2;
  double _level = 0;
  double _opacity = 1;
  MaskShape _gradient = MaskShape.linear;
  bool _overlay = false;

  /// Pending pen points in document space.
  final List<Offset> penPoints = [];

  MaskToolKind get kind => _kind;

  /// Brush diameter in screen pixels.
  double get size => _size;
  double get softness => _softness;

  /// Paint grey: 0 = black (hide) … 1 = white (reveal).
  double get level => _level;

  /// Brush opacity (flow) 0..1.
  double get opacity => _opacity;

  /// [MaskShape.linear] or [MaskShape.radial].
  MaskShape get gradient => _gradient;

  /// Show hidden areas as a red overlay while editing.
  bool get overlay => _overlay;

  /// Black/white shorthand used by older code and the overlay colour.
  MaskMode get mode => _level < 0.5 ? MaskMode.hide : MaskMode.show;
  set mode(MaskMode v) => level = v == MaskMode.hide ? 0 : 1;

  /// The grey the current tool paints (the eraser paints the opposite).
  double get paintLevel => _kind == MaskToolKind.eraser ? 1 - _level : _level;

  set kind(MaskToolKind v) => _set(() {
    _kind = v;
    penPoints.clear();
  });
  set size(double v) => _set(() => _size = v);
  set softness(double v) => _set(() => _softness = v);
  set level(double v) => _set(() => _level = v.clamp(0.0, 1.0));
  set opacity(double v) => _set(() => _opacity = v.clamp(0.01, 1.0));
  set gradient(MaskShape v) => _set(() => _gradient = v);
  set overlay(bool v) => _set(() => _overlay = v);

  /// Photoshop's X: swap black and white.
  void swap() => level = 1 - _level;

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  /// A stroke in the current settings.
  MaskStroke stroke(
    MaskShape shape,
    List<Offset> points, {
    double width = 40,
    double? level,
  }) {
    final v = level ?? paintLevel;
    return MaskStroke(
      mode: v < 0.5 ? MaskMode.hide : MaskMode.show,
      shape: shape,
      points: points,
      width: width,
      softness: shape == MaskShape.linear || shape == MaskShape.radial
          ? 0
          : _softness,
      level: v == 0 || v == 1 ? null : v,
      opacity: _opacity,
    );
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

  bool get _freehand =>
      brush.kind == MaskToolKind.brush || brush.kind == MaskToolKind.eraser;

  MaskShape get _shape => switch (brush.kind) {
    MaskToolKind.lasso => MaskShape.area,
    MaskToolKind.gradient => brush.gradient,
    _ => MaskShape.brush,
  };

  MaskStroke _stroke(MaskShape shape) =>
      brush.stroke(shape, _points, width: _width);

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
    if (_freehand) {
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
    final shape = _shape;
    if ((shape == MaskShape.area && _points.length < 3) ||
        (shape != MaskShape.area &&
            shape != MaskShape.brush &&
            _points.length < 2)) {
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
    if (brush.kind == MaskToolKind.gradient) {
      // Start and end only.
      _points = [_points.first, p];
      _preview(ctx);
      return;
    }
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
      brush.stroke(MaskShape.area, [
        for (final p in brush.penPoints) l.props.transform.toLocal(p),
      ]),
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
    final color = brush.paintLevel < 0.5
        ? const Color(0xFFFF4D6D)
        : const Color(0xFF22C55E);
    final vp = ctx.viewport;
    final target = _target(ctx);
    if (brush.overlay && target != null && target.props.hasMask) {
      _paintRubylith(canvas, ctx, target);
    }
    if (brush.kind == MaskToolKind.gradient && _points.length == 2) {
      final l = _layerId == null
          ? null
          : ctx.editor.document.layerById(_layerId);
      if (l != null) {
        final a = vp.toScreen(l.props.transform.toDocument(_points[0]));
        final b = vp.toScreen(l.props.transform.toDocument(_points[1]));
        final line = Paint()
          ..strokeWidth = 2
          ..color = Colors.white;
        canvas
          ..drawLine(a, b, line..strokeWidth = 4)
          ..drawLine(
            a,
            b,
            Paint()
              ..strokeWidth = 2
              ..color = const Color(0xFF3D7BFF),
          );
        for (final (p, fill) in [
          (a, const Color(0xFF000000)),
          (b, const Color(0xFFFFFFFF)),
        ]) {
          canvas
            ..drawCircle(p, 8, Paint()..color = const Color(0xFF3D7BFF))
            ..drawCircle(
              p,
              6,
              Paint()
                ..color = brush.level < 0.5
                    ? fill
                    : (fill == const Color(0xFFFFFFFF)
                          ? Colors.black
                          : Colors.white),
            );
        }
      }
    }
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
    if (c != null && _freehand) {
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

  /// Photoshop's quick-mask look: hidden parts of the layer tinted red.
  void _paintRubylith(Canvas canvas, ToolContext ctx, Layer l) {
    final h = l.props.transform.homography;
    final vs = ctx.viewport.scale, o = ctx.viewport.offset;
    final m = [
      h[0] * vs + h[6] * o.dx,
      h[1] * vs + h[7] * o.dx,
      h[2] * vs + h[8] * o.dx,
      h[3] * vs + h[6] * o.dy,
      h[4] * vs + h[7] * o.dy,
      h[5] * vs + h[8] * o.dy,
      h[6],
      h[7],
      h[8],
    ];
    final area = layerLocalRect(l);
    canvas
      ..save()
      ..transform(
        Float64List.fromList([
          m[0], m[3], 0, m[6], //
          m[1], m[4], 0, m[7], //
          0, 0, 1, 0, //
          m[2], m[5], 0, m[8], //
        ]),
      )
      ..saveLayer(area, Paint())
      ..drawRect(area, Paint()..color = const Color(0x88FF2D55))
      ..saveLayer(area, Paint()..blendMode = BlendMode.dstOut);
    DocumentRenderer.paintMask(
      canvas,
      l.props.mask,
      area,
      images: ctx.editor.assets.imageOf,
    );
    canvas
      ..restore()
      ..restore()
      ..restore();
  }
}
