import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../document/model/document.dart';
import '../../document/model/layer.dart';
import '../../document/model/layer_geometry.dart';
import '../../document/render/document_renderer.dart';
import 'editor_tool.dart';

enum _Mode { none, move, pinch, scaleHandle, rotateHandle }

enum _Handle { tl, tr, br, bl, rotate }

/// Select, move, scale and rotate layers.
///
/// * Tap selects the topmost layer under the finger (tap empty space to
///   deselect). Shift/Ctrl-click adds to the selection. Double-tap asks the
///   host to edit (e.g. text).
/// * Drag to move; pinch/rotate with two fingers. A group or a
///   multi-selection transforms as one unit.
/// * Corner handles scale uniformly around the centre; the round handle
///   above the box rotates.
/// * With snapping on, layers snap to the canvas centre and edges and to
///   45° angles, and pink guides show what they snapped to.
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

  /// Layers being transformed and their state when the gesture began.
  Map<String, Layer> _start = const {};
  Rect _startBounds = Rect.zero;
  double _startRotation = 0;
  Offset _startFocalDoc = Offset.zero;
  Offset _startPointerScreen = Offset.zero;
  DateTime _lastEnd = DateTime(0);
  _Mode _lastMode = _Mode.none;
  final List<double> _guidesX = [];
  final List<double> _guidesY = [];

  bool get _additive {
    final k = HardwareKeyboard.instance;
    return k.isShiftPressed || k.isControlPressed || k.isMetaPressed;
  }

  // ------------------------------------------------------------ helpers

  /// What a gesture on the selection moves: the top-level selection minus
  /// anything locked.
  List<String> _movable(ToolContext ctx) {
    final e = ctx.editor;
    return [
      for (final id in e.topLevelSelection)
        if (!e.document.isEffectivelyLocked(id)) id,
    ];
  }

  /// A single leaf selection shows a rotated box; groups and
  /// multi-selections show their axis-aligned combined bounds.
  List<Offset>? _selectionCorners(ToolContext ctx) {
    final e = ctx.editor;
    final ids = e.topLevelSelection;
    if (ids.isEmpty) return null;
    if (ids.length == 1) {
      final l = e.document.layerById(ids.single);
      if (l == null || !e.document.isEffectivelyVisible(l.id)) return null;
      if (l is! GroupLayer) return layerCorners(l);
    }
    final r = e.boundsOf(ids);
    if (r.isEmpty) return null;
    return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  }

  // ----------------------------------------------------------------- taps

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final e = ctx.editor;
    final hit = e.layerAt(
      ctx.viewport.toDoc(screen),
      tolerance: 6 / ctx.viewport.scale,
    );
    if (_additive && hit != null) {
      e.toggleSelect(hit.id);
    } else {
      e.select(hit?.id);
    }
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

    final corners = _selectionCorners(ctx);
    final movable = _movable(ctx);
    final recentlyTransforming =
        DateTime.now().difference(_lastEnd).inMilliseconds < 300 &&
        _lastMode != _Mode.none;
    final docPt = vp.toDoc(d.focalPoint);
    final tol = 6 / vp.scale;

    bool insideSelection(double tolerance) =>
        corners != null &&
        _polygonContains(corners, docPt, tolerance / vp.scale);

    if (d.pointerCount >= 2) {
      if (movable.isEmpty || !(recentlyTransforming || insideSelection(40))) {
        return false;
      }
      _begin(_Mode.pinch, movable, ctx, d.focalPoint);
      return true;
    }

    // Single pointer: handles first, then the selection, then any layer.
    if (movable.isNotEmpty && corners != null) {
      final h = _handleAt(corners, d.focalPoint, vp);
      if (h != null) {
        _begin(
          h == _Handle.rotate ? _Mode.rotateHandle : _Mode.scaleHandle,
          movable,
          ctx,
          d.focalPoint,
        );
        return true;
      }
    }
    if (movable.isNotEmpty && insideSelection(6)) {
      // Keep dragging the selection even if other layers cover it.
      _begin(_Mode.move, movable, ctx, d.focalPoint);
      return true;
    }
    final target = e.layerAt(docPt, tolerance: tol);
    if (target == null) return false;
    e.select(target.id);
    _begin(_Mode.move, [target.id], ctx, d.focalPoint);
    return true;
  }

  void _begin(_Mode mode, List<String> ids, ToolContext ctx, Offset focal) {
    final doc = ctx.editor.document;
    _mode = mode;
    _start = {for (final id in ids) id: ?doc.layerById(id)};
    _startBounds = unionBounds(_start.values);
    final single = _start.length == 1 ? _start.values.single : null;
    _startRotation = single != null && single is! GroupLayer
        ? single.props.transform.rotation
        : 0;
    _startFocalDoc = ctx.viewport.toDoc(focal);
    _startPointerScreen = focal;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    if (_start.isEmpty || _mode == _Mode.none) return;
    final vp = ctx.viewport;
    final pivot = _startBounds.center;

    Similarity s;
    switch (_mode) {
      case _Mode.move:
        var delta = vp.toDoc(d.focalPoint) - _startFocalDoc;
        if (ctx.snapping) delta = _snapDelta(ctx, delta);
        s = Similarity(translate: delta);
      case _Mode.pinch:
        final delta = vp.toDoc(d.focalPoint) - _startFocalDoc;
        var rot = d.rotation;
        if (ctx.snapping) {
          rot = _snapAngle(_startRotation + rot) - _startRotation;
        }
        s = Similarity(
          pivot: pivot,
          translate: delta,
          rotation: rot,
          scale: d.scale.clamp(0.01, 100),
        );
      case _Mode.scaleHandle:
        final c = vp.toScreen(pivot);
        final d0 = (_startPointerScreen - c).distance;
        final d1 = (d.focalPoint - c).distance;
        s = Similarity(
          pivot: pivot,
          scale: (d0 < 1 ? 1.0 : d1 / d0).clamp(0.01, 100),
        );
      case _Mode.rotateHandle:
        final c = vp.toScreen(pivot);
        final a0 = (_startPointerScreen - c).direction;
        final a1 = (d.focalPoint - c).direction;
        var rot = a1 - a0;
        if (ctx.snapping) {
          rot = _snapAngle(_startRotation + rot) - _startRotation;
        }
        s = Similarity(pivot: pivot, rotation: rot);
      case _Mode.none:
        return;
    }
    final start = _start;
    ctx.editor.preview((doc) {
      var next = doc;
      for (final e in start.entries) {
        next = next.replaceLayer(applySimilarity(e.value, s));
      }
      return next;
    });
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_mode != _Mode.none) {
      ctx.editor.commit('transform');
      _lastEnd = DateTime.now();
    }
    _lastMode = _mode;
    _mode = _Mode.none;
    _start = const {};
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

  /// Adjusts a move so the moved bounds' edges or centre land on the
  /// canvas edges or centre when close enough.
  Offset _snapDelta(ToolContext ctx, Offset delta) {
    _guidesX.clear();
    _guidesY.clear();
    final PixDocument doc = ctx.editor.document;
    final threshold = snapPx / ctx.viewport.scale;
    final b = _startBounds.shift(delta);

    double? bestDx, bestDy, guideX, guideY;
    for (final target in [0.0, doc.width / 2, doc.width]) {
      for (final edge in [b.left, b.center.dx, b.right]) {
        final diff = target - edge;
        if (diff.abs() <= threshold &&
            (bestDx == null || diff.abs() < bestDx.abs())) {
          bestDx = diff;
          guideX = target;
        }
      }
    }
    for (final target in [0.0, doc.height / 2, doc.height]) {
      for (final edge in [b.top, b.center.dy, b.bottom]) {
        final diff = target - edge;
        if (diff.abs() <= threshold &&
            (bestDy == null || diff.abs() < bestDy.abs())) {
          bestDy = diff;
          guideY = target;
        }
      }
    }
    if (guideX != null) _guidesX.add(guideX);
    if (guideY != null) _guidesY.add(guideY);
    return delta + Offset(bestDx ?? 0, bestDy ?? 0);
  }

  // -------------------------------------------------------------- handles

  List<Offset> _toScreen(List<Offset> corners, CanvasViewport vp) => [
    for (final c in corners) vp.toScreen(c),
  ];

  Offset _rotateHandlePos(List<Offset> screenCorners) {
    final topMid = (screenCorners[0] + screenCorners[1]) / 2;
    final bottomMid = (screenCorners[3] + screenCorners[2]) / 2;
    final up = topMid - bottomMid;
    final len = up.distance;
    final dir = len < 0.001 ? const Offset(0, -1) : up / len;
    return topMid + dir * rotateHandleGap;
  }

  _Handle? _handleAt(List<Offset> corners, Offset screen, CanvasViewport vp) {
    final c = _toScreen(corners, vp);
    if ((screen - _rotateHandlePos(c)).distance <= handleHitRadius) {
      return _Handle.rotate;
    }
    const order = [_Handle.tl, _Handle.tr, _Handle.br, _Handle.bl];
    for (var i = 0; i < 4; i++) {
      if ((screen - c[i]).distance <= handleHitRadius) return order[i];
    }
    return null;
  }

  static bool _polygonContains(List<Offset> poly, Offset p, double tol) {
    // Point-in-convex-quad using edge cross products, with a tolerance
    // band so thin layers stay grabbable.
    var sign = 0;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final edge = b - a;
      final len = edge.distance;
      if (len < 1e-9) continue;
      final cross = (edge.dx * (p.dy - a.dy) - edge.dy * (p.dx - a.dx)) / len;
      if (cross.abs() <= tol) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    final corners = _selectionCorners(ctx);
    if (corners != null && _movable(ctx).isNotEmpty) {
      final h = _handleAt(corners, screen, ctx.viewport);
      if (h == _Handle.rotate) return SystemMouseCursors.grab;
      if (h == _Handle.tl || h == _Handle.br) {
        return SystemMouseCursors.resizeUpLeftDownRight;
      }
      if (h != null) return SystemMouseCursors.resizeUpRightDownLeft;
    }
    final hit = ctx.editor.layerAt(
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
    final e = ctx.editor;
    final doc = e.document;

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

    final corners = _selectionCorners(ctx);
    if (corners == null) return;

    // Thin outlines for each member of a multi-selection or group.
    final members = e.topLevelSelection.length > 1
        ? [for (final id in e.topLevelSelection) ?doc.layerById(id)]
        : (e.selectedLayer is GroupLayer
              ? (e.selectedLayer! as GroupLayer).children
              : const <Layer>[]);
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = style.selection.withValues(alpha: 0.55);
    for (final m in members) {
      if (!m.props.visible) continue;
      canvas.drawPath(
        Path()..addPolygon(_toScreen(layerCorners(m), vp), true),
        thin,
      );
    }

    final c = _toScreen(corners, vp);
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

    if (_movable(ctx).isEmpty) {
      _paintIcon(canvas, (c[0] + c[2]) / 2, Icons.lock_rounded, style);
      return;
    }
    if (_mode == _Mode.move || _mode == _Mode.pinch) return;

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
