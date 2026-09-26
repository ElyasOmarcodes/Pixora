import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../document/model/layer.dart';
import '../../document/model/layer_geometry.dart';
import '../../document/render/document_renderer.dart';
import '../../document/render/text_layout.dart';
import 'editor_tool.dart';

enum _Mode { none, move, pinch, handle }

/// What a handle does when dragged.
enum HandleKind {
  /// Rotate around the centre (snaps to 45° with angle snapping on).
  rotate,

  /// Scale proportionally, the opposite corner stays put.
  corner,

  /// Stretch one side, the opposite side stays put.
  left,
  right,
  top,
  bottom,

  /// Text: change the text-box width (text re-wraps, height follows).
  textWidth,

  /// Text: resize the type itself (font size), not the pixels.
  fontSize,
}

/// A handle's place on screen plus, for local handles, which corner/edge
/// of the layer box it sits on (unit coordinates, −1..1).
class _Handle {
  const _Handle(this.kind, this.screen, [this.unit = Offset.zero]);
  final HandleKind kind;
  final Offset screen;
  final Offset unit;
}

/// Select, move, scale, stretch and rotate layers — with handles tailored
/// to each layer type:
///
/// | Layer        | Handles                                                    |
/// |--------------|------------------------------------------------------------|
/// | Text         | rotate (below), text-box width (right edge), font size (bottom-left) |
/// | Shape        | 4 corners (proportional), 4 edges (stretch), rotate        |
/// | Image        | 4 corners (proportional), 4 edges (stretch), rotate        |
/// | Group / many | 4 corners (proportional), rotate                           |
///
/// Tap selects, Shift/Ctrl-click adds to the selection, double-tap asks the
/// host to edit. Drag anywhere inside the selection to move; pinch/rotate
/// with two fingers. Snapping (canvas, guides, grid, other layers, 45°) is
/// configurable and shown with pink guides.
class TransformTool extends EditorTool {
  TransformTool({this.onEditRequest});

  final void Function(Layer layer)? onEditRequest;

  static const double handleRadius = 8;
  static const double handleHitRadius = 22;
  static const double rotateHandleGap = 30;
  static const double snapPx = 7;

  @override
  String get id => 'transform';

  _Mode _mode = _Mode.none;
  _Handle? _handle;
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

  // ------------------------------------------------------------ selection

  /// The selection plus the layers linked to it (they move together).
  List<String> _targets(ToolContext ctx) =>
      ctx.editor.withLinked(ctx.editor.topLevelSelection);

  List<String> _movable(ToolContext ctx) {
    final e = ctx.editor;
    return [
      for (final id in _targets(ctx))
        if (!e.document.isEffectivelyLocked(id)) id,
    ];
  }

  /// The single leaf layer being edited, if the selection is exactly one
  /// non-group layer (type-specific handles apply).
  Layer? _singleLeaf(ToolContext ctx) {
    final ids = _targets(ctx);
    if (ids.length != 1) return null;
    final l = ctx.editor.document.layerById(ids.single);
    return l is GroupLayer ? null : l;
  }

  List<Offset>? _selectionCorners(ToolContext ctx) {
    final e = ctx.editor;
    final ids = _targets(ctx);
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

  List<Offset> _toScreen(List<Offset> pts, CanvasViewport vp) => [
    for (final p in pts) vp.toScreen(p),
  ];

  /// Handles for the current selection, in hit-test priority order.
  List<_Handle> _handles(ToolContext ctx) {
    final corners = _selectionCorners(ctx);
    if (corners == null || _movable(ctx).isEmpty) return const [];
    final vp = ctx.viewport;
    final c = _toScreen(corners, vp); // TL, TR, BR, BL
    Offset mid(Offset a, Offset b) => (a + b) / 2;
    final bottomMid = mid(c[3], c[2]);
    final topMid = mid(c[0], c[1]);
    final down = bottomMid - topMid;
    final dirDown = down.distance < 0.001
        ? const Offset(0, 1)
        : down / down.distance;
    final rotate = _Handle(
      HandleKind.rotate,
      bottomMid + dirDown * rotateHandleGap,
    );

    final leaf = _singleLeaf(ctx);
    if (leaf is TextLayer) {
      return [
        rotate,
        _Handle(HandleKind.textWidth, mid(c[1], c[2]), const Offset(1, 0)),
        _Handle(HandleKind.fontSize, c[3], const Offset(-1, 1)),
      ];
    }
    final cornerHandles = [
      _Handle(HandleKind.corner, c[0], const Offset(-1, -1)),
      _Handle(HandleKind.corner, c[1], const Offset(1, -1)),
      _Handle(HandleKind.corner, c[2], const Offset(1, 1)),
      _Handle(HandleKind.corner, c[3], const Offset(-1, 1)),
    ];
    if (leaf == null) return [rotate, ...cornerHandles];
    return [
      rotate,
      ...cornerHandles,
      _Handle(HandleKind.left, mid(c[0], c[3]), const Offset(-1, 0)),
      _Handle(HandleKind.right, mid(c[1], c[2]), const Offset(1, 0)),
      _Handle(HandleKind.top, topMid, const Offset(0, -1)),
      _Handle(HandleKind.bottom, bottomMid, const Offset(0, 1)),
    ];
  }

  _Handle? _handleAt(ToolContext ctx, Offset screen) {
    for (final h in _handles(ctx)) {
      if ((screen - h.screen).distance <= handleHitRadius) return h;
    }
    return null;
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
    // Double-tap the text-width handle: back to automatic width.
    final h = _handleAt(ctx, screen);
    final leaf = _singleLeaf(ctx);
    if (h?.kind == HandleKind.textWidth && leaf is TextLayer) {
      e.updateLayer(
        leaf.id,
        (l) => (l as TextLayer).copyWith(autoWidth: true),
        label: 'text',
      );
      return;
    }
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
    final docPt = vp.toDoc(d.localFocalPoint);

    bool insideSelection(double tolerance) =>
        corners != null &&
        _polygonContains(corners, docPt, tolerance / vp.scale);

    if (d.pointerCount >= 2) {
      if (movable.isEmpty || !(recentlyTransforming || insideSelection(40))) {
        return false;
      }
      _begin(_Mode.pinch, movable, ctx, d.localFocalPoint);
      return true;
    }

    final h = _handleAt(ctx, d.localFocalPoint);
    if (h != null) {
      _handle = h;
      _begin(_Mode.handle, movable, ctx, d.localFocalPoint);
      return true;
    }
    if (movable.isNotEmpty && insideSelection(6)) {
      _begin(_Mode.move, movable, ctx, d.localFocalPoint);
      return true;
    }
    final target = e.layerAt(docPt, tolerance: 6 / vp.scale);
    if (target == null) return false;
    e.select(target.id);
    _begin(_Mode.move, [target.id], ctx, d.localFocalPoint);
    return true;
  }

  void _begin(
    _Mode mode,
    List<String> layerIds,
    ToolContext ctx,
    Offset focal,
  ) {
    final doc = ctx.editor.document;
    final ids = ctx.editor.withLinked(layerIds);
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
    final start = _start;

    void applyToAll(Similarity s) => ctx.editor.preview((doc) {
      var next = doc;
      for (final e in start.entries) {
        next = next.replaceLayer(applySimilarity(e.value, s));
      }
      return next;
    });

    switch (_mode) {
      case _Mode.move:
        var delta = vp.toDoc(d.localFocalPoint) - _startFocalDoc;
        if (ctx.snap.positions) delta = _snapDelta(ctx, delta);
        applyToAll(Similarity(translate: delta));
      case _Mode.pinch:
        final delta = vp.toDoc(d.localFocalPoint) - _startFocalDoc;
        var rot = d.rotation;
        if (ctx.snap.rotation) {
          rot = _snapAngle(_startRotation + rot) - _startRotation;
        }
        applyToAll(
          Similarity(
            pivot: pivot,
            translate: delta,
            rotation: rot,
            scale: d.scale.clamp(0.01, 100),
          ),
        );
      case _Mode.handle:
        _dragHandle(ctx, d.localFocalPoint, applyToAll);
      case _Mode.none:
        return;
    }
  }

  void _dragHandle(
    ToolContext ctx,
    Offset pointer,
    void Function(Similarity) applyToAll,
  ) {
    final h = _handle!;
    final vp = ctx.viewport;
    final pivot = _startBounds.center;

    if (h.kind == HandleKind.rotate) {
      final c = vp.toScreen(pivot);
      var rot = (pointer - c).direction - (_startPointerScreen - c).direction;
      if (ctx.snap.rotation) {
        rot = _snapAngle(_startRotation + rot) - _startRotation;
      }
      applyToAll(Similarity(pivot: pivot, rotation: rot));
      return;
    }

    final leaf = _start.length == 1 ? _start.values.single : null;
    if (leaf == null || leaf is GroupLayer) {
      // Group / multi-selection corner: proportional scale about the
      // opposite corner of the combined bounds.
      final b = _startBounds;
      final anchor = Offset(
        h.unit.dx < 0 ? b.right : b.left,
        h.unit.dy < 0 ? b.bottom : b.top,
      );
      applyToAll(Similarity(pivot: anchor, scale: _ratio(anchor, pointer, vp)));
      return;
    }

    final t = leaf.props.transform;
    final r = layerLocalRect(leaf);
    Offset localPoint(Offset u) => Offset(
      r.center.dx + u.dx * r.width / 2,
      r.center.dy + u.dy * r.height / 2,
    );
    final opposite = Offset(-h.unit.dx, -h.unit.dy);
    final anchorDoc = t.toDocument(localPoint(opposite));
    final local = t.toLocal(vp.toDoc(pointer));
    const minSize = 4.0;

    Layer next;
    switch (h.kind) {
      case HandleKind.corner:
        final f = _ratio(anchorDoc, pointer, vp);
        next = switch (leaf) {
          ShapeLayer s => s.copyWith(
            width: math.max(minSize, s.width * f),
            height: math.max(minSize, s.height * f),
            cornerRadius: s.cornerRadius * f,
          ),
          _ => applySimilarity(leaf, Similarity(scale: f)),
        };
      case HandleKind.left || HandleKind.right:
        final w = math.max(minSize, (local.dx - localPoint(opposite).dx).abs());
        next = switch (leaf) {
          ShapeLayer s => s.copyWith(width: w),
          _ => leaf.update(
            (p) => p.copyWith(
              transform: t.copyWith(scaleX: t.scaleX * w / r.width),
            ),
          ),
        };
      case HandleKind.top || HandleKind.bottom:
        final hgt = math.max(
          minSize,
          (local.dy - localPoint(opposite).dy).abs(),
        );
        next = switch (leaf) {
          ShapeLayer s => s.copyWith(height: hgt),
          _ => leaf.update(
            (p) => p.copyWith(
              transform: t.copyWith(scaleY: t.scaleY * hgt / r.height),
            ),
          ),
        };
      case HandleKind.textWidth:
        final text = leaf as TextLayer;
        final pad = TextLayoutCache.paddingFor(text) * 2;
        final w = math.max(text.fontSize, (local.dx - r.left).abs() - pad);
        next = text.copyWith(boxWidth: w);
      case HandleKind.fontSize:
        final text = leaf as TextLayer;
        final f = _ratio(anchorDoc, pointer, vp).clamp(0.05, 50.0);
        final st = text.props.stroke;
        next = text
            .copyWith(
              fontSize: math.max(4, text.fontSize * f),
              strokeWidth: text.strokeWidth * f,
              letterSpacing: text.letterSpacing * f,
              boxWidth: text.boxWidth == null ? null : text.boxWidth! * f,
            )
            .update(
              (p) => st == null
                  ? p
                  : p.copyWith(stroke: st.copyWith(size: st.size * f)),
            );
      case HandleKind.rotate:
        return;
    }

    // Keep the anchor (opposite corner/edge; top-left for the text box) in
    // place after the size change.
    final anchorUnit = h.kind == HandleKind.textWidth
        ? const Offset(-1, -1)
        : opposite;
    final anchorBefore = h.kind == HandleKind.textWidth
        ? t.toDocument(localPoint(anchorUnit))
        : anchorDoc;
    final nt = next.props.transform;
    final nr = layerLocalRect(next);
    final nLocal = Offset(
      nr.center.dx + anchorUnit.dx * nr.width / 2,
      nr.center.dy + anchorUnit.dy * nr.height / 2,
    );
    final shift = anchorBefore - nt.toDocument(nLocal);
    final placed = next.update(
      (p) => p.copyWith(
        transform: nt.copyWith(x: nt.x + shift.dx, y: nt.y + shift.dy),
      ),
    );
    ctx.editor.preview((doc) => doc.replaceLayer(placed));
  }

  double _ratio(Offset anchorDoc, Offset pointer, CanvasViewport vp) {
    final a = vp.toScreen(anchorDoc);
    final d0 = (_startPointerScreen - a).distance;
    final d1 = (pointer - a).distance;
    return (d0 < 1 ? 1.0 : d1 / d0).clamp(0.01, 100.0);
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_mode != _Mode.none) {
      ctx.editor.commit('transform');
      _lastEnd = DateTime.now();
    }
    _lastMode = _mode;
    _mode = _Mode.none;
    _handle = null;
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

  /// Adjusts a move so the moved bounds' edges or centre land on nearby
  /// targets: canvas edges/centre, guides and grid lines, and other layers'
  /// edges/centres (smart guides).
  Offset _snapDelta(ToolContext ctx, Offset delta) {
    _guidesX.clear();
    _guidesY.clear();
    final doc = ctx.editor.document;
    final opts = ctx.snap;
    final threshold = snapPx / ctx.viewport.scale;
    final b = _startBounds.shift(delta);

    final xs = <double>[];
    final ys = <double>[];
    if (opts.canvas) {
      xs.addAll([0, doc.width / 2, doc.width]);
      ys.addAll([0, doc.height / 2, doc.height]);
    }
    if (opts.guides) {
      final (gx, gy) = doc.guides.gridLinesPx(doc.size);
      xs
        ..addAll(doc.guides.vertical)
        ..addAll(gx);
      ys
        ..addAll(doc.guides.horizontal)
        ..addAll(gy);
    }
    if (opts.layers) {
      final moving = _start.keys.toSet();
      bool isMoving(Layer l) =>
          moving.contains(l.id) ||
          doc.ancestorsOf(l.id).any((g) => moving.contains(g.id));
      for (final l in doc.allLayers) {
        if (l is GroupLayer || isMoving(l) || !doc.isEffectivelyVisible(l.id)) {
          continue;
        }
        final o = layerDocumentBounds(l);
        xs.addAll([o.left, o.center.dx, o.right]);
        ys.addAll([o.top, o.center.dy, o.bottom]);
      }
    }

    double? bestDx, bestDy, guideX, guideY;
    for (final target in xs) {
      for (final edge in [b.left, b.center.dx, b.right]) {
        final diff = target - edge;
        if (diff.abs() <= threshold &&
            (bestDx == null || diff.abs() < bestDx.abs())) {
          bestDx = diff;
          guideX = target;
        }
      }
    }
    for (final target in ys) {
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

  static bool _polygonContains(List<Offset> poly, Offset p, double tol) {
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
    final h = _handleAt(ctx, screen);
    if (h != null) {
      return switch (h.kind) {
        HandleKind.rotate => SystemMouseCursors.grab,
        HandleKind.left ||
        HandleKind.right ||
        HandleKind.textWidth => SystemMouseCursors.resizeLeftRight,
        HandleKind.top || HandleKind.bottom => SystemMouseCursors.resizeUpDown,
        _ =>
          h.unit.dx * h.unit.dy > 0
              ? SystemMouseCursors.resizeUpLeftDownRight
              : SystemMouseCursors.resizeUpRightDownLeft,
      };
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
    final top = vp.toScreen(Offset.zero).dy,
        bottom = vp.toScreen(Offset(0, doc.height)).dy;
    final left = vp.toScreen(Offset.zero).dx,
        right = vp.toScreen(Offset(doc.width, 0)).dx;
    for (final x in _guidesX) {
      final sx = vp.toScreen(Offset(x, 0)).dx;
      canvas.drawLine(Offset(sx, top), Offset(sx, bottom), guide);
    }
    for (final y in _guidesY) {
      final sy = vp.toScreen(Offset(0, y)).dy;
      canvas.drawLine(Offset(left, sy), Offset(right, sy), guide);
    }

    final corners = _selectionCorners(ctx);
    if (corners == null) return;

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
    canvas
      ..drawPath(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black.withValues(alpha: 0.18),
      )
      ..drawPath(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = style.selection,
      );

    if (_movable(ctx).isEmpty) {
      _paintBadge(canvas, (c[0] + c[2]) / 2, Icons.lock_rounded, style);
      return;
    }
    if (_mode == _Mode.move || _mode == _Mode.pinch) return;

    // Edge direction for pill-shaped handles.
    final edgeAngle = (c[1] - c[0]).direction;
    final handles = _handles(ctx);
    final rot = handles.firstWhere((h) => h.kind == HandleKind.rotate);
    canvas.drawLine(
      (c[3] + c[2]) / 2,
      rot.screen,
      Paint()
        ..color = style.selection
        ..strokeWidth = 1.4,
    );
    for (final h in handles.reversed) {
      final active = _handle?.kind == h.kind && _handle?.unit == h.unit;
      switch (h.kind) {
        case HandleKind.rotate:
          _paintCircle(
            canvas,
            h.screen,
            style,
            radius: 13,
            icon: Icons.rotate_right_rounded,
          );
        case HandleKind.corner:
          _paintCircle(canvas, h.screen, style, active: active);
        case HandleKind.left || HandleKind.right:
          _paintPill(
            canvas,
            h.screen,
            edgeAngle + math.pi / 2,
            style,
            active: active,
          );
        case HandleKind.top || HandleKind.bottom:
          _paintPill(canvas, h.screen, edgeAngle, style, active: active);
        case HandleKind.textWidth:
          _paintPill(
            canvas,
            h.screen,
            edgeAngle + math.pi / 2,
            style,
            long: 30,
            thick: 16,
            icon: Icons.width_normal_rounded,
            active: active,
          );
        case HandleKind.fontSize:
          _paintCircle(
            canvas,
            h.screen,
            style,
            radius: 13,
            icon: Icons.format_size_rounded,
            active: active,
          );
      }
    }
  }

  void _paintCircle(
    Canvas canvas,
    Offset p,
    ToolStyle style, {
    double radius = handleRadius,
    IconData? icon,
    bool active = false,
  }) {
    canvas
      ..drawCircle(
        p + const Offset(0, 1.5),
        radius + 1,
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      )
      ..drawCircle(
        p,
        radius,
        Paint()..color = active ? style.selection : style.handleFill,
      )
      ..drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = style.selection,
      );
    if (icon != null) {
      _paintGlyph(
        canvas,
        p,
        icon,
        active ? Colors.white : style.selection,
        radius * 1.15,
      );
    }
  }

  void _paintPill(
    Canvas canvas,
    Offset p,
    double angle,
    ToolStyle style, {
    double long = 22,
    double thick = 8,
    IconData? icon,
    bool active = false,
  }) {
    canvas
      ..save()
      ..translate(p.dx, p.dy)
      ..rotate(angle);
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: thick, height: long),
      Radius.circular(thick / 2),
    );
    canvas
      ..drawRRect(
        r.shift(const Offset(0, 1.5)),
        Paint()..color = Colors.black.withValues(alpha: 0.18),
      )
      ..drawRRect(
        r,
        Paint()..color = active ? style.selection : style.handleFill,
      )
      ..drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = style.selection,
      )
      ..restore();
    if (icon != null) {
      _paintGlyph(
        canvas,
        p,
        icon,
        active ? Colors.white : style.selection,
        thick * 0.8,
      );
    }
  }

  void _paintBadge(Canvas canvas, Offset p, IconData icon, ToolStyle style) {
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

/// Pans and zooms only; layers can't be picked (Photoshop's Hand tool).
class HandTool extends EditorTool {
  @override
  String get id => 'hand';

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) =>
      SystemMouseCursors.grab;
}
