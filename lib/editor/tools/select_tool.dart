import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import '../../document/model/layer_transform.dart';
import '../../document/render/vector_paths.dart';
import '../editor_controller.dart';
import '../selection/selection_controller.dart';
import 'editor_tool.dart';
import 'pen_tool.dart';

/// Canvas input for the Select menu: drag a rectangle / ellipse, draw a
/// lasso, tap polygon corners, or tap a colour for the Magic Wand and
/// Color Range. Draws the selection as a dimmed outside with marching
/// ants. Two fingers always pan and zoom.
class SelectTool extends EditorTool {
  SelectTool(this.sel);

  final SelectionController sel;

  Offset? _start, _end;
  List<Offset> _lasso = [];

  /// Polygon lasso corners (document space) until closed.
  final List<Offset> polygon = [];

  @override
  String get id => 'select';

  @override
  Listenable get repaint => Listenable.merge([sel, sel.ants]);

  bool get _drags =>
      sel.tool == SelectToolKind.rectangle ||
      sel.tool == SelectToolKind.ellipse ||
      sel.tool == SelectToolKind.lasso;

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final doc = ctx.viewport.toDoc(screen);
    switch (sel.tool) {
      case SelectToolKind.magicWand:
        sel.magicWand(ctx.editor, doc);
      case SelectToolKind.colorRange:
        sel.colorRangeAt(ctx.editor, doc);
      case SelectToolKind.polygon:
        // Tapping the first corner closes the shape.
        if (polygon.length >= 3 &&
            (ctx.viewport.toScreen(polygon.first) - screen).distance < 16) {
          closePolygon(ctx);
        } else {
          polygon.add(doc);
          ctx.requestRepaint();
        }
      case SelectToolKind.rectangle ||
          SelectToolKind.ellipse ||
          SelectToolKind.lasso:
        // A tap outside the selection deselects, like Photoshop.
        final c = sel.current;
        if (c != null && c.coverageAt(doc) < 0.5) sel.deselect();
      default:
        break;
    }
  }

  @override
  void onDoubleTap(ToolContext ctx, Offset screen) {
    if (sel.tool == SelectToolKind.polygon && polygon.length >= 3) {
      closePolygon(ctx);
    }
  }

  /// Fills the pending polygon into the selection.
  void closePolygon(ToolContext ctx) => applyPolygon(ctx.editor, sel);

  void applyPolygon(EditorController editor, SelectionController s) {
    if (polygon.length < 3) return;
    final path = ui.Path()..addPolygon(List.of(polygon), true);
    polygon.clear();
    s.addPath(editor, path);
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    if (d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad) {
      return false;
    }
    if (!_drags) return false;
    final p = ctx.viewport.toDoc(ctx.pointerDown ?? d.localFocalPoint);
    _start = p;
    _end = ctx.viewport.toDoc(d.localFocalPoint);
    _lasso = [p, _end!];
    return true;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    if (_start == null) return;
    final p = ctx.viewport.toDoc(d.localFocalPoint);
    _end = p;
    if (sel.tool == SelectToolKind.lasso) {
      final minStep = 2 / ctx.viewport.scale;
      if ((p - _lasso.last).distance >= minStep) _lasso = [..._lasso, p];
    }
    ctx.requestRepaint();
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    final path = _pendingPath();
    _start = null;
    _end = null;
    _lasso = [];
    if (path != null) sel.addPath(ctx.editor, path);
    ctx.requestRepaint();
  }

  ui.Path? _pendingPath() {
    final a = _start, b = _end;
    if (a == null || b == null) return null;
    switch (sel.tool) {
      case SelectToolKind.rectangle || SelectToolKind.ellipse:
        final r = Rect.fromPoints(a, b);
        if (r.width < 1 || r.height < 1) return null;
        return sel.tool == SelectToolKind.rectangle
            ? (ui.Path()..addRect(r))
            : (ui.Path()..addOval(r));
      case SelectToolKind.lasso:
        if (_lasso.length < 3) return null;
        return ui.Path()..addPolygon(_lasso, true);
      default:
        return null;
    }
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) =>
      SystemMouseCursors.precise;

  // ------------------------------------------------------------ overlay

  (double, Offset, ui.Path?)? _screenKey;
  ui.Path? _screenOutline;

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final vp = ctx.viewport;
    final doc = ctx.editor.document;
    final docRect = Rect.fromPoints(
      vp.toScreen(Offset.zero),
      vp.toScreen(Offset(doc.width, doc.height)),
    );
    final img = sel.maskImage;
    if (img != null && sel.hasSelection) {
      canvas
        ..saveLayer(docRect, Paint())
        ..drawRect(docRect, Paint()..color = const Color(0x66000000))
        ..drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          docRect,
          Paint()
            ..filterQuality = FilterQuality.low
            ..blendMode = BlendMode.dstOut,
        )
        ..restore();
    }
    final outline = sel.outline;
    if (outline != null && sel.hasSelection) {
      final key = (vp.scale, vp.offset, outline);
      if (_screenKey != key) {
        _screenKey = key;
        _screenOutline = outline.transform(_viewMatrix(vp));
      }
      _ants(canvas, _screenOutline!);
    }
    // Shape being dragged.
    final pending = _pendingPath();
    if (pending != null) {
      _ants(canvas, pending.transform(_viewMatrix(vp)), closed: true);
    } else if (_start != null && sel.tool == SelectToolKind.lasso) {
      final pts = [for (final p in _lasso) vp.toScreen(p)];
      _ants(canvas, ui.Path()..addPolygon(pts, false));
    }
    // Polygon corners.
    if (sel.tool == SelectToolKind.polygon && polygon.isNotEmpty) {
      final pts = [for (final p in polygon) vp.toScreen(p)];
      _ants(canvas, ui.Path()..addPolygon(pts, false));
      for (var i = 0; i < pts.length; i++) {
        canvas
          ..drawCircle(pts[i], i == 0 ? 8 : 5, Paint()..color = Colors.white)
          ..drawCircle(
            pts[i],
            i == 0 ? 8 : 5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = const Color(0xFF3D7BFF),
          );
      }
    }
  }

  static Float64List _viewMatrix(CanvasViewport vp) => Float64List.fromList([
    vp.scale, 0, 0, 0, //
    0, vp.scale, 0, 0, //
    0, 0, 1, 0, //
    vp.offset.dx, vp.offset.dy, 0, 1, //
  ]);

  /// Black-and-white dashes that crawl along [path] (screen space).
  void _ants(Canvas canvas, ui.Path path, {bool closed = false}) {
    final phase = (sel.ants.value % 8) * 1.0;
    canvas
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white,
      )
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..shader = ui.Gradient.linear(
            Offset(phase, 0),
            Offset(phase + 5.6, 5.6),
            const [Colors.black, Colors.black, Colors.transparent],
            const [0, 0.5, 0.5],
            TileMode.repeated,
          ),
      );
  }
}

/// Pen drawing a bezier outline (document space) that becomes a selection.
class SelectionPenTarget extends ChangeNotifier implements PenTarget {
  List<PathContour> _contours = const [];

  @override
  LayerTransform get transform => const LayerTransform();

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

  /// The closed outlines as one path.
  ui.Path toPath() {
    final path = ui.Path()..fillType = PathFillType.nonZero;
    for (final c in _contours) {
      if (c.nodes.length >= 3) contourPath(c.copyWith(closed: true), path);
    }
    return path;
  }
}
