import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../document/effects/effect_registry.dart';
import '../../document/model/effect.dart';
import '../../document/model/layer.dart';
import '../../document/model/warp.dart';
import '../../document/render/document_renderer.dart';
import 'editor_tool.dart';

/// Which warp handles the canvas shows (shared with the warp panel).
class WarpState extends ChangeNotifier {
  WarpMode _mode = WarpMode.warp;
  WarpMode get mode => _mode;
  set mode(WarpMode m) {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }
}

/// The selected layer's warp effect, if it has one.
LayerEffect? warpOf(Layer layer) {
  for (final e in layer.props.effects) {
    if (e.type == 'warp') return e;
  }
  return null;
}

/// [layer] with its warp set to [g] (a warp effect is added if needed).
Layer withWarp(Layer layer, WarpGeometry g, WarpMode mode) {
  final params = <String, Object>{'mode': mode.index, ...g.toParams()};
  final current = warpOf(layer);
  final effects = current == null
      ? [
          EffectRegistry.instance['warp']!.create(params),
          ...layer.props.effects,
        ]
      : [
          for (final e in layer.props.effects)
            identical(e, current)
                ? e.copyWith(params: {...e.params, ...params})
                : e,
        ];
  return layer.withProps(layer.props.copyWith(effects: effects));
}

/// Photoshop's Distort / Perspective / Warp on the canvas: drag the
/// corners (Distort, Perspective in mirrored pairs) or the 16 points of
/// the Bézier mesh (Warp). Every drag is one undo step.
class WarpTool extends EditorTool {
  WarpTool(this.state);
  final WarpState state;

  static const double _hit = 22;

  int _grab = -1; // corner 0-3, or 100 + mesh index
  WarpGeometry? _start;
  Offset _startUnit = Offset.zero;
  WarpMode _axisLock = WarpMode.distort;
  int _lockedAxis = -1; // perspective: 0 = x, 1 = y

  @override
  String get id => 'warp';

  @override
  Listenable get repaint => state;

  Layer? _layer(ToolContext ctx) => ctx.editor.selectedLayer;

  WarpGeometry _geometry(Layer l) {
    final e = warpOf(l);
    return e == null
        ? WarpGeometry(
            [...WarpGeometry.baseCorners],
            [
              for (var i = 0; i < 4; i++)
                for (var j = 0; j < 4; j++) Offset(j / 3, i / 3),
            ],
          )
        : WarpGeometry.of(e);
  }

  /// Unit point of the layer's box → screen.
  Offset _screen(ToolContext ctx, Layer l, Offset unit) {
    final b = layerLocalRect(l);
    final local = b.topLeft + Offset(unit.dx * b.width, unit.dy * b.height);
    return ctx.viewport.toScreen(l.props.transform.toDocument(local));
  }

  /// Screen → unit point of the layer's box.
  Offset _unit(ToolContext ctx, Layer l, Offset screen) {
    final b = layerLocalRect(l);
    final local = l.props.transform.toLocal(ctx.viewport.toDoc(screen));
    return Offset(
      (local.dx - b.left) / math.max(1e-6, b.width),
      (local.dy - b.top) / math.max(1e-6, b.height),
    );
  }

  int _hitTest(ToolContext ctx, Layer l, WarpGeometry g, Offset screen) {
    if (state.mode == WarpMode.warp) {
      var best = -1;
      var bestD = _hit;
      for (var i = 0; i < 16; i++) {
        final p = _screen(ctx, l, g.project(g.mesh[i]));
        final d = (p - screen).distance;
        if (d < bestD) {
          bestD = d;
          best = 100 + i;
        }
      }
      return best;
    }
    for (var k = 0; k < 4; k++) {
      if ((_screen(ctx, l, g.corners[k]) - screen).distance < _hit) return k;
    }
    return -1;
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    final l = _layer(ctx);
    if (l == null || d.pointerCount > 1) return false;
    final g = _geometry(l);
    _grab = _hitTest(ctx, l, g, d.localFocalPoint);
    if (_grab < 0) return false;
    _start = g;
    _startUnit = _unit(ctx, l, d.localFocalPoint);
    _lockedAxis = -1;
    _axisLock = state.mode;
    return true;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final l = _layer(ctx);
    final g0 = _start;
    if (l == null || g0 == null || _grab < 0) return;
    final unit = _unit(ctx, l, d.localFocalPoint);
    final delta = unit - _startUnit;
    final corners = [...g0.corners];
    final mesh = [...g0.mesh];
    if (_grab >= 100) {
      // Mesh points live before the corner projection.
      final i = _grab - 100;
      mesh[i] = g0.unproject(g0.project(g0.mesh[i]) + delta);
    } else if (_axisLock == WarpMode.perspective) {
      // Photoshop's Perspective: the corner and its partner across the
      // edge move in mirror image along the main drag direction.
      if (_lockedAxis < 0 && delta.distance > 0.01) {
        _lockedAxis = delta.dx.abs() >= delta.dy.abs() ? 0 : 1;
      }
      final k = _grab;
      if (_lockedAxis == 0) {
        final partner = const [1, 0, 3, 2][k]; // same top / bottom edge
        corners[k] = g0.corners[k] + Offset(delta.dx, 0);
        corners[partner] = g0.corners[partner] - Offset(delta.dx, 0);
      } else if (_lockedAxis == 1) {
        final partner = const [3, 2, 1, 0][k]; // same left / right edge
        corners[k] = g0.corners[k] + Offset(0, delta.dy);
        corners[partner] = g0.corners[partner] - Offset(0, delta.dy);
      }
    } else {
      corners[_grab] = g0.corners[_grab] + delta;
    }
    final next = WarpGeometry(corners, mesh);
    ctx.editor.previewLayer(l.id, (x) => withWarp(x, next, state.mode));
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_grab >= 0 && ctx.editor.isPreviewing) ctx.editor.commit('warp');
    _grab = -1;
    _start = null;
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    final l = _layer(ctx);
    if (l == null) return MouseCursor.defer;
    return _hitTest(ctx, l, _geometry(l), screen) >= 0
        ? SystemMouseCursors.move
        : MouseCursor.defer;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final l = _layer(ctx);
    if (l == null) return;
    final g = _geometry(l);
    const accent = Color(0xFF3D7BFF);
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.8);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent;
    // The bent grid: thirds of the box, as in Photoshop's warp.
    final grid = Path();
    for (var s = 0; s <= 3; s++) {
      final t = s / 3;
      for (final vertical in [false, true]) {
        for (var i = 0; i <= 24; i++) {
          final q = i / 24;
          final p = _screen(ctx, l, vertical ? g.map(t, q) : g.map(q, t));
          i == 0 ? grid.moveTo(p.dx, p.dy) : grid.lineTo(p.dx, p.dy);
        }
      }
    }
    canvas
      ..drawPath(grid, halo)
      ..drawPath(grid, line);

    void handle(Offset p, {bool square = false}) {
      if (square) {
        final r = Rect.fromCenter(center: p, width: 13, height: 13);
        canvas
          ..drawRect(r.inflate(2), Paint()..color = Colors.white)
          ..drawRect(r, Paint()..color = accent);
      } else {
        canvas
          ..drawCircle(p, 8, Paint()..color = Colors.white)
          ..drawCircle(p, 6, Paint()..color = accent);
      }
    }

    if (state.mode == WarpMode.warp) {
      // Handle bars from each corner point to its neighbours.
      final m = [for (final p in g.mesh) _screen(ctx, l, g.project(p))];
      final bars = Paint()
        ..strokeWidth = 1
        ..color = accent.withValues(alpha: 0.7);
      for (final (a, b) in const [
        (0, 1), (0, 4), (3, 2), (3, 7), //
        (12, 13), (12, 8), (15, 14), (15, 11),
      ]) {
        canvas.drawLine(m[a], m[b], bars);
      }
      for (var i = 0; i < 16; i++) {
        final corner = i == 0 || i == 3 || i == 12 || i == 15;
        handle(m[i], square: corner);
      }
    } else {
      for (final c in g.corners) {
        handle(_screen(ctx, l, c), square: true);
      }
    }
  }
}
