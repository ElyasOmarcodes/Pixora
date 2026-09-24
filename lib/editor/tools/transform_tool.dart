import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import '../../document/model/layer_transform.dart';
import '../../document/render/document_renderer.dart';
import 'editor_tool.dart';

enum _Mode { none, move, pinch, scaleHandle, rotateHandle }

enum _Handle { tl, tr, br, bl, rotate }

/// Select, move, scale and rotate layers.
///
/// * Tap selects the topmost layer under the finger (tap empty space to
///   deselect). Double-tap asks the host to edit (e.g. text).
/// * Drag a layer to move it; pinch/rotate with two fingers.
/// * Corner handles scale uniformly around the centre; the round handle
///   above the box rotates.
/// * With snapping on, the layer snaps to the canvas centre and edges and to
///   45° angles, and pink guides show what it snapped to.
class TransformTool extends EditorTool {
  TransformTool({this.onEditRequest});

  /// Called on double-tap of a layer.
  final void Function(Layer layer)? onEditRequest;

  static const double handleRadius = 9;
  static const double handleHitRadius = 24;
  static const double rotateHandleGap = 34;
  static const double snapPx = 7;

  @override
  String get id => 'transform';

  _Mode _mode = _Mode.none;
  String? _layerId;
  LayerTransform? _start;
  Offset _startFocalDoc = Offset.zero;
  Offset _startPointerScreen = Offset.zero;
  DateTime _lastEnd = DateTime(0);
  _Mode _lastMode = _Mode.none;
  final List<double> _guidesX = [];
  final List<double> _guidesY = [];

  // ----------------------------------------------------------------- taps

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final e = ctx.editor;
    final doc = ctx.viewport.toDoc(screen);
    final tol = 6 / ctx.viewport.scale;
    final hit = e.layerAt(doc, tolerance: tol);
    e.select(hit?.id);
  }

  @override
  void onDoubleTap(ToolContext ctx, Offset screen) {
    final e = ctx.editor;
    final hit = e.layerAt(
      ctx.viewport.toDoc(screen),
      tolerance: 6 / ctx.viewport.scale,
    );
    if (hit != null) {
      e.select(hit.id);
      onEditRequest?.call(hit);
    }
  }

  // ------------------------------------------------------------ gestures

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    final e = ctx.editor;
    final vp = ctx.viewport;
    _guidesX.clear();
    _guidesY.clear();
    if (d.kind == PointerDeviceKind.trackpad) return false;

    final selected = e.selectedLayer;
    final recentlyTransforming =
        DateTime.now().difference(_lastEnd).inMilliseconds < 300 &&
        _lastMode != _Mode.none;

    if (d.pointerCount >= 2) {
      final target =
          selected != null &&
              !selected.props.locked &&
              (recentlyTransforming ||
                  hitTestLayer(
                    selected,
                    vp.toDoc(d.focalPoint),
                    tolerance: 40 / vp.scale,
                  ))
          ? selected
          : null;
      if (target == null) return false;
      _begin(_Mode.pinch, target, ctx, d.focalPoint);
      return true;
    }

    // Single pointer: handles first, then layers.
    if (selected != null && !selected.props.locked) {
      final h = _handleAt(selected, d.focalPoint, vp);
      if (h != null) {
        _begin(
          h == _Handle.rotate ? _Mode.rotateHandle : _Mode.scaleHandle,
          selected,
          ctx,
          d.focalPoint,
        );
        return true;
      }
    }
    final docPt = vp.toDoc(d.focalPoint);
    final tol = 6 / vp.scale;
    Layer? target;
    if (selected != null &&
        !selected.props.locked &&
        hitTestLayer(selected, docPt, tolerance: tol)) {
      target = selected; // Keep dragging the selection even if covered.
    } else {
      target = e.layerAt(docPt, tolerance: tol);
    }
    if (target == null) return false;
    e.select(target.id);
    _begin(_Mode.move, target, ctx, d.focalPoint);
    return true;
  }

  void _begin(_Mode mode, Layer layer, ToolContext ctx, Offset focal) {
    _mode = mode;
    _layerId = layer.id;
    _start = layer.props.transform;
    _startFocalDoc = ctx.viewport.toDoc(focal);
    _startPointerScreen = focal;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final id = _layerId, start = _start;
    if (id == null || start == null || _mode == _Mode.none) return;
    final e = ctx.editor;
    final layer = e.document.layerById(id);
    if (layer == null) return;
    final vp = ctx.viewport;

    LayerTransform next;
    switch (_mode) {
      case _Mode.move:
        final delta = vp.toDoc(d.focalPoint) - _startFocalDoc;
        next = start.copyWith(x: start.x + delta.dx, y: start.y + delta.dy);
        if (ctx.snapping) next = _snapPosition(ctx, layer, next);
      case _Mode.pinch:
        final delta = vp.toDoc(d.focalPoint) - _startFocalDoc;
        var rot = start.rotation + d.rotation;
        if (ctx.snapping) rot = _snapAngle(rot);
        next = start
            .copyWith(
              x: start.x + delta.dx,
              y: start.y + delta.dy,
              rotation: rot,
            )
            .scaledBy(d.scale.clamp(0.01, 100));
      case _Mode.scaleHandle:
        final c = vp.toScreen(start.position);
        final d0 = (_startPointerScreen - c).distance;
        final d1 = (d.focalPoint - c).distance;
        final f = d0 < 1 ? 1.0 : d1 / d0;
        next = start.scaledBy(f.clamp(0.01, 100));
      case _Mode.rotateHandle:
        final c = vp.toScreen(start.position);
        final a0 = (_startPointerScreen - c).direction;
        final a1 = (d.focalPoint - c).direction;
        var rot = start.rotation + (a1 - a0);
        if (ctx.snapping) rot = _snapAngle(rot);
        next = start.copyWith(rotation: rot);
      case _Mode.none:
        return;
    }
    e.previewLayer(id, (l) => l.update((p) => p.copyWith(transform: next)));
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_mode != _Mode.none) {
      ctx.editor.commit('transform');
      _lastEnd = DateTime.now();
    }
    _lastMode = _mode;
    _mode = _Mode.none;
    _layerId = null;
    _start = null;
    _guidesX.clear();
    _guidesY.clear();
    ctx.requestRepaint();
  }

  // ------------------------------------------------------------- snapping

  double _snapAngle(double r) {
    const step = math.pi / 4;
    final nearest = (r / step).roundToDouble() * step;
    return (r - nearest).abs() < 4 * math.pi / 180 ? nearest : r;
  }

  LayerTransform _snapPosition(ToolContext ctx, Layer layer, LayerTransform t) {
    _guidesX.clear();
    _guidesY.clear();
    final doc = ctx.editor.document;
    final threshold = snapPx / ctx.viewport.scale;
    final b = layerDocumentBounds(
      layer.withProps(layer.props.copyWith(transform: t)),
    );

    double? bestDx, bestDy;
    double? guideX, guideY;
    void tryX(double edge, double target) {
      final diff = target - edge;
      if (diff.abs() <= threshold &&
          (bestDx == null || diff.abs() < bestDx!.abs())) {
        bestDx = diff;
        guideX = target;
      }
    }

    void tryY(double edge, double target) {
      final diff = target - edge;
      if (diff.abs() <= threshold &&
          (bestDy == null || diff.abs() < bestDy!.abs())) {
        bestDy = diff;
        guideY = target;
      }
    }

    for (final target in [0.0, doc.width / 2, doc.width]) {
      tryX(b.left, target);
      tryX(b.center.dx, target);
      tryX(b.right, target);
    }
    for (final target in [0.0, doc.height / 2, doc.height]) {
      tryY(b.top, target);
      tryY(b.center.dy, target);
      tryY(b.bottom, target);
    }
    if (guideX != null) _guidesX.add(guideX!);
    if (guideY != null) _guidesY.add(guideY!);
    return t.copyWith(x: t.x + (bestDx ?? 0), y: t.y + (bestDy ?? 0));
  }

  // -------------------------------------------------------------- handles

  List<Offset> _screenCorners(Layer l, CanvasViewport vp) => [
    for (final c in layerCorners(l)) vp.toScreen(c),
  ];

  Offset _rotateHandlePos(List<Offset> corners) {
    final topMid = (corners[0] + corners[1]) / 2;
    final bottomMid = (corners[3] + corners[2]) / 2;
    final up = topMid - bottomMid;
    final len = up.distance;
    final dir = len < 0.001 ? const Offset(0, -1) : up / len;
    return topMid + dir * rotateHandleGap;
  }

  _Handle? _handleAt(Layer l, Offset screen, CanvasViewport vp) {
    final c = _screenCorners(l, vp);
    if ((screen - _rotateHandlePos(c)).distance <= handleHitRadius) {
      return _Handle.rotate;
    }
    const order = [_Handle.tl, _Handle.tr, _Handle.br, _Handle.bl];
    for (var i = 0; i < 4; i++) {
      if ((screen - c[i]).distance <= handleHitRadius) return order[i];
    }
    return null;
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    final e = ctx.editor;
    final sel = e.selectedLayer;
    if (sel != null && !sel.props.locked) {
      final h = _handleAt(sel, screen, ctx.viewport);
      if (h == _Handle.rotate) return SystemMouseCursors.grab;
      if (h == _Handle.tl || h == _Handle.br) {
        return SystemMouseCursors.resizeUpLeftDownRight;
      }
      if (h != null) return SystemMouseCursors.resizeUpRightDownLeft;
    }
    final hit = e.layerAt(
      ctx.viewport.toDoc(screen),
      tolerance: 4 / ctx.viewport.scale,
    );
    return hit != null ? SystemMouseCursors.move : MouseCursor.defer;
  }

  // -------------------------------------------------------------- overlay

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final vp = ctx.viewport;
    final style = ctx.style;
    final doc = ctx.editor.document;

    final guide = Paint()
      ..color = style.guide
      ..strokeWidth = 1.2;
    for (final x in _guidesX) {
      final sx = vp.toScreen(Offset(x, 0)).dx;
      canvas.drawLine(
        Offset(sx, vp.toScreen(Offset.zero).dy),
        Offset(sx, vp.toScreen(Offset(0, doc.height)).dy),
        guide,
      );
    }
    for (final y in _guidesY) {
      final sy = vp.toScreen(Offset(0, y)).dy;
      canvas.drawLine(
        Offset(vp.toScreen(Offset.zero).dx, sy),
        Offset(vp.toScreen(Offset(doc.width, 0)).dx, sy),
        guide,
      );
    }

    final sel = ctx.editor.selectedLayer;
    if (sel == null || !sel.props.visible) return;
    final c = _screenCorners(sel, vp);
    final box = Path()..addPolygon(c, true);
    canvas.drawPath(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = style.selection,
    );

    if (sel.props.locked) {
      final center = (c[0] + c[2]) / 2;
      _paintIcon(canvas, center, Icons.lock_rounded, style);
      return;
    }
    if (_mode == _Mode.move || _mode == _Mode.pinch) {
      return; // Keep the view clean.
    }

    final rot = _rotateHandlePos(c);
    final topMid = (c[0] + c[1]) / 2;
    canvas.drawLine(
      topMid,
      rot,
      Paint()
        ..color = style.selection
        ..strokeWidth = 1.4,
    );
    for (final p in c) {
      _paintHandle(canvas, p, style);
    }
    _paintHandle(canvas, rot, style, icon: Icons.rotate_right_rounded);
  }

  void _paintHandle(
    Canvas canvas,
    Offset p,
    ToolStyle style, {
    IconData? icon,
  }) {
    final r = icon == null ? handleRadius : handleRadius + 4;
    canvas.drawCircle(
      p + const Offset(0, 1.5),
      r + 1,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawCircle(p, r, Paint()..color = style.handleFill);
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = style.selection,
    );
    if (icon != null) _paintGlyph(canvas, p, icon, style.selection, 14);
  }

  void _paintIcon(Canvas canvas, Offset p, IconData icon, ToolStyle style) {
    canvas.drawCircle(p, 16, Paint()..color = style.selection);
    _paintGlyph(canvas, p, icon, Colors.white, 18);
  }

  void _paintGlyph(
    Canvas canvas,
    Offset p,
    IconData icon,
    Color color,
    double size,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}
