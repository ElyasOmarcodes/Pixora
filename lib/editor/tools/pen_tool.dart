import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/layer.dart';
import '../../document/model/layer_transform.dart';
import '../../document/render/vector_paths.dart';
import 'editor_tool.dart';

/// What the pen edits: bezier contours in some layer-local space.
abstract class PenTarget {
  LayerTransform get transform;
  List<PathContour> get contours;

  /// [live] = mid-gesture preview; otherwise a finished (undoable) edit.
  void setContours(List<PathContour> contours, {bool live = false});

  /// Ends a live gesture.
  void commit();
}

enum PenMode {
  /// Add / move nodes and handles.
  edit,

  /// Move, scale and rotate the whole active shape.
  transform,
}

/// Pen editing state shared by the canvas tool and the pen panel.
class PenState extends ChangeNotifier {
  PenTarget? target;
  PenMode _mode = PenMode.edit;
  int _active = 0;
  int? _node;

  PenMode get mode => _mode;
  set mode(PenMode m) {
    _mode = m;
    notifyListeners();
  }

  /// Index of the shape (contour) being edited.
  int get active => _active;
  set active(int v) {
    _active = v;
    _node = null;
    notifyListeners();
  }

  /// Selected node in the active contour.
  int? get node => _node;
  set node(int? v) {
    _node = v;
    notifyListeners();
  }

  void reset() {
    target = null;
    _mode = PenMode.edit;
    _active = 0;
    _node = null;
    notifyListeners();
  }

  void touch() => notifyListeners();

  // ------------------------------------------------------------ helpers

  List<PathContour> get _contours => target?.contours ?? const [];

  PathContour? get activeContour =>
      _active < _contours.length ? _contours[_active] : null;

  void _set(List<PathContour> c, {bool live = false}) {
    target?.setContours(c, live: live);
    notifyListeners();
  }

  List<PathContour> _replace(PathContour c) => [
    for (var i = 0; i < _contours.length; i++) i == _active ? c : _contours[i],
  ];

  // ---------------------------------------------------------- contours

  void addContour() {
    _set([..._contours, PathContour()]);
    _active = _contours.length - 1;
    _node = null;
    notifyListeners();
  }

  void deleteContour() {
    if (_contours.isEmpty) return;
    final list = [..._contours]..removeAt(_active);
    _active = math.max(0, math.min(_active, list.length - 1));
    _node = null;
    _set(list);
  }

  void duplicateContour() {
    final c = activeContour;
    if (c == null) return;
    final copy = c.copyWith(
      nodes: [for (final n in c.nodes) n.shifted(const Offset(24, 24))],
    );
    _set([..._contours, copy]);
    _active = _contours.length - 1;
    notifyListeners();
  }

  void previousContour() {
    if (_contours.isEmpty) return;
    active = (_active - 1 + _contours.length) % _contours.length;
  }

  void nextContour() {
    if (_contours.isEmpty) return;
    active = (_active + 1) % _contours.length;
  }

  // -------------------------------------------------------------- nodes

  void deleteNode() {
    final c = activeContour, i = _node;
    if (c == null || i == null || i >= c.nodes.length) return;
    final nodes = [...c.nodes]..removeAt(i);
    _node = nodes.isEmpty ? null : math.min(i, nodes.length - 1);
    _set(
      _replace(c.copyWith(nodes: nodes, closed: nodes.length > 2 && c.closed)),
    );
  }

  /// Inserts a node halfway along the segment after the selected node
  /// (splitting a curve keeps its shape).
  void insertNode() {
    final c = activeContour;
    if (c == null || c.nodes.length < 2) return;
    final i = _node ?? c.nodes.length - 2;
    final j = (i + 1) % c.nodes.length;
    if (!c.closed && j == 0) return;
    final a = c.nodes[i], b = c.nodes[j];
    final nodes = [...c.nodes];
    if (a.outHandle == null && b.inHandle == null) {
      nodes.insert(i + 1, PathNode(Offset.lerp(a.point, b.point, 0.5)!));
    } else {
      // de Casteljau split at t = 0.5.
      final p0 = a.point, p1 = a.outHandle ?? a.point;
      final p2 = b.inHandle ?? b.point, p3 = b.point;
      final q0 = Offset.lerp(p0, p1, 0.5)!, q1 = Offset.lerp(p1, p2, 0.5)!;
      final q2 = Offset.lerp(p2, p3, 0.5)!;
      final r0 = Offset.lerp(q0, q1, 0.5)!, r1 = Offset.lerp(q1, q2, 0.5)!;
      final m = Offset.lerp(r0, r1, 0.5)!;
      nodes[i] = a.copyWith(outHandle: q0);
      nodes[j] = b.copyWith(inHandle: q2);
      nodes.insert(
        i + 1,
        PathNode(m, inHandle: r0, outHandle: r1, type: PathNodeType.smooth),
      );
    }
    _node = i + 1;
    _set(_replace(c.copyWith(nodes: nodes)));
  }

  /// Corner → smooth (adds handles) → symmetric → corner.
  void cycleNodeType() {
    final c = activeContour, i = _node;
    if (c == null || i == null) return;
    final n = c.nodes[i];
    final next = PathNodeType.values[(n.type.index + 1) % 3];
    _set(
      _replace(
        c.copyWith(
          nodes: [
            for (var k = 0; k < c.nodes.length; k++)
              k == i ? _withType(c, k, next) : c.nodes[k],
          ],
        ),
      ),
    );
  }

  void setNodeType(PathNodeType t) {
    final c = activeContour, i = _node;
    if (c == null || i == null) return;
    _set(
      _replace(
        c.copyWith(
          nodes: [
            for (var k = 0; k < c.nodes.length; k++)
              k == i ? _withType(c, k, t) : c.nodes[k],
          ],
        ),
      ),
    );
  }

  PathNode _withType(PathContour c, int i, PathNodeType t) {
    final n = c.nodes[i];
    if (t == PathNodeType.corner) return n.copyWith(type: t);
    // Give the node handles along the direction of its neighbours.
    final len = c.nodes.length;
    final prev = c.nodes[(i - 1 + len) % len].point;
    final next = c.nodes[(i + 1) % len].point;
    var dir = next - prev;
    if (dir.distance == 0) dir = const Offset(1, 0);
    final u = dir / dir.distance;
    final lin = n.inHandle == null
        ? (n.point - prev).distance / 3
        : (n.inHandle! - n.point).distance;
    final lout = n.outHandle == null
        ? (next - n.point).distance / 3
        : (n.outHandle! - n.point).distance;
    final a = t == PathNodeType.symmetric ? (lin + lout) / 2 : lin;
    final b = t == PathNodeType.symmetric ? (lin + lout) / 2 : lout;
    return n.copyWith(
      type: t,
      inHandle: n.point - u * a,
      outHandle: n.point + u * b,
    );
  }

  /// Removes the selected node's handles (sharp corner, straight sides).
  void straightenNode() {
    final c = activeContour, i = _node;
    if (c == null || i == null) return;
    _set(
      _replace(
        c.copyWith(
          nodes: [
            for (var k = 0; k < c.nodes.length; k++)
              k == i
                  ? c.nodes[k].copyWith(
                      type: PathNodeType.corner,
                      clearIn: true,
                      clearOut: true,
                    )
                  : c.nodes[k],
          ],
        ),
      ),
    );
  }

  void toggleClosed() {
    final c = activeContour;
    if (c == null || c.nodes.length < 2) return;
    _set(_replace(c.copyWith(closed: !c.closed)));
  }

  void reverse() {
    final c = activeContour;
    if (c == null) return;
    _set(
      _replace(
        c.copyWith(
          nodes: [
            for (final n in c.nodes.reversed)
              PathNode(
                n.point,
                inHandle: n.outHandle,
                outHandle: n.inHandle,
                type: n.type,
              ),
          ],
        ),
      ),
    );
    if (_node != null) _node = c.nodes.length - 1 - _node!;
  }

  /// Scales or rotates the active shape about its centre (panel buttons).
  void transformActive({double scale = 1, double rotation = 0}) {
    final c = activeContour;
    if (c == null || c.nodes.isEmpty) return;
    final center = contourPath(c).getBounds().center;
    final cs = math.cos(rotation), sn = math.sin(rotation);
    Offset f(Offset p) {
      final d = (p - center) * scale;
      return center + Offset(d.dx * cs - d.dy * sn, d.dx * sn + d.dy * cs);
    }

    _set(_replace(c.copyWith(nodes: [for (final n in c.nodes) n.mapped(f)])));
  }

  void flipActive({required bool horizontal}) {
    final c = activeContour;
    if (c == null || c.nodes.isEmpty) return;
    final center = contourPath(c).getBounds().center;
    Offset f(Offset p) => horizontal
        ? Offset(2 * center.dx - p.dx, p.dy)
        : Offset(p.dx, 2 * center.dy - p.dy);
    _set(_replace(c.copyWith(nodes: [for (final n in c.nodes) n.mapped(f)])));
  }
}

enum _Grab { none, node, inHandle, outHandle, newNode, contour }

/// Canvas pen: tap to add a corner node, drag to add a smooth node with
/// handles, drag nodes / handles to shape the curve, tap the first node to
/// close the shape, double-tap a node to change its type. In transform
/// mode, drag moves the whole shape and two fingers scale / rotate it.
class PenTool extends EditorTool {
  PenTool(this.state);
  final PenState state;

  _Grab _grab = _Grab.none;
  int _nodeIndex = -1;
  List<PathContour> _start = const [];
  Offset _startLocal = Offset.zero;
  Offset _startFocalLocal = Offset.zero;

  static const double _hit = 18;

  @override
  String get id => 'pen';

  @override
  Listenable get repaint => state;

  PenTarget? get _t => state.target;

  Offset _local(ToolContext ctx, Offset screen) =>
      _t!.transform.toLocal(ctx.viewport.toDoc(screen));

  Offset _screen(ToolContext ctx, Offset local) =>
      ctx.viewport.toScreen(_t!.transform.toDocument(local));

  (int, _Grab)? _hitTest(ToolContext ctx, Offset screen) {
    final c = state.activeContour;
    if (c == null) return null;
    // Handles of the selected node first (they sit on top).
    final sel = state.node;
    if (sel != null && sel < c.nodes.length) {
      final n = c.nodes[sel];
      if (n.inHandle != null &&
          (_screen(ctx, n.inHandle!) - screen).distance < _hit) {
        return (sel, _Grab.inHandle);
      }
      if (n.outHandle != null &&
          (_screen(ctx, n.outHandle!) - screen).distance < _hit) {
        return (sel, _Grab.outHandle);
      }
    }
    for (var i = c.nodes.length - 1; i >= 0; i--) {
      if ((_screen(ctx, c.nodes[i].point) - screen).distance < _hit) {
        return (i, _Grab.node);
      }
    }
    return null;
  }

  @override
  void onTap(ToolContext ctx, Offset screen) {
    if (_t == null) return;
    if (state.mode == PenMode.transform) return;
    final c = state.activeContour;
    final hit = _hitTest(ctx, screen);
    if (hit != null) {
      final (i, g) = hit;
      if (g == _Grab.node &&
          c != null &&
          i == 0 &&
          !c.closed &&
          c.nodes.length >= 3 &&
          state.node == c.nodes.length - 1) {
        state.toggleClosed(); // tap the first node to close
        return;
      }
      state.node = i;
      return;
    }
    _append(ctx, _local(ctx, screen), null);
  }

  @override
  void onDoubleTap(ToolContext ctx, Offset screen) {
    if (_t == null || state.mode == PenMode.transform) return;
    final hit = _hitTest(ctx, screen);
    if (hit != null && hit.$2 == _Grab.node) {
      state.node = hit.$1;
      state.cycleNodeType();
    }
  }

  /// Adds a node after the selected one (or at the end).
  void _append(ToolContext ctx, Offset p, Offset? handle, {bool live = false}) {
    var contours = [..._t!.contours];
    if (contours.isEmpty) {
      contours = [PathContour()];
      state.active = 0;
    }
    var c = contours[state.active];
    if (c.closed) {
      // A closed shape: start a new one.
      contours.add(PathContour());
      state.active = contours.length - 1;
      c = contours.last;
    }
    final node = handle == null
        ? PathNode(p)
        : PathNode(
            p,
            outHandle: handle,
            inHandle: p * 2 - handle,
            type: PathNodeType.symmetric,
          );
    final at = state.node == null || state.node! >= c.nodes.length - 1
        ? c.nodes.length
        : state.node! + 1;
    final nodes = [...c.nodes]..insert(at, node);
    contours[state.active] = c.copyWith(nodes: nodes);
    _t!.setContours(contours, live: live);
    state.node = at;
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    if (_t == null || d.kind == PointerDeviceKind.trackpad) return false;
    _start = _t!.contours;
    if (state.mode == PenMode.transform) {
      final c = state.activeContour;
      if (c == null || c.nodes.isEmpty) return false;
      final b = contourPath(c).getBounds().inflate(24 / ctx.viewport.scale);
      final local = _local(ctx, d.localFocalPoint);
      if (d.pointerCount < 2 && !b.contains(local)) return false;
      _grab = _Grab.contour;
      _startLocal = local;
      _startFocalLocal = local;
      return true;
    }
    if (d.pointerCount > 1) return false;
    final hit = _hitTest(ctx, d.localFocalPoint);
    _startLocal = _local(ctx, d.localFocalPoint);
    if (hit != null) {
      _nodeIndex = hit.$1;
      _grab = hit.$2;
      state.node = hit.$1;
      return true;
    }
    // Drag on empty canvas: a new smooth node pulled out into handles.
    _grab = _Grab.newNode;
    _append(ctx, _startLocal, null, live: true);
    _start = _t!.contours;
    _nodeIndex = state.node!;
    return true;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final t = _t;
    if (t == null || _grab == _Grab.none) return;
    final p = _local(ctx, d.localFocalPoint);
    final contours = [..._start];
    final ci = state.active;
    if (ci >= contours.length) return;
    final c = contours[ci];

    if (_grab == _Grab.contour) {
      final center = contourPath(c).getBounds().center;
      final delta = p - _startFocalLocal;
      final s = d.scale, r = d.rotation;
      final cs = math.cos(r), sn = math.sin(r);
      Offset f(Offset q) {
        final v = (q - center) * s;
        return center +
            Offset(v.dx * cs - v.dy * sn, v.dx * sn + v.dy * cs) +
            delta;
      }

      contours[ci] = c.copyWith(nodes: [for (final n in c.nodes) n.mapped(f)]);
      t.setContours(contours, live: true);
      return;
    }

    final i = _nodeIndex;
    if (i < 0 || i >= c.nodes.length) return;
    final n = c.nodes[i];
    PathNode updated;
    switch (_grab) {
      case _Grab.node:
        updated = n.shifted(p - _startLocal);
      case _Grab.newNode:
        // Pull symmetric handles out of the new node.
        updated = (p - n.point).distance < 4 / ctx.viewport.scale
            ? n
            : PathNode(
                n.point,
                outHandle: p,
                inHandle: n.point * 2 - p,
                type: PathNodeType.symmetric,
              );
      case _Grab.inHandle || _Grab.outHandle:
        final isIn = _grab == _Grab.inHandle;
        final other = isIn ? n.outHandle : n.inHandle;
        Offset? opp = other;
        if (other != null && n.type != PathNodeType.corner) {
          final v = n.point - p;
          if (v.distance > 0) {
            final len = n.type == PathNodeType.symmetric
                ? v.distance
                : (other - n.point).distance;
            opp = n.point + v / v.distance * len;
          }
        }
        updated = isIn
            ? n.copyWith(inHandle: p, outHandle: opp)
            : n.copyWith(outHandle: p, inHandle: opp);
      case _Grab.none || _Grab.contour:
        return;
    }
    final nodes = [...c.nodes]..[i] = updated;
    contours[ci] = c.copyWith(nodes: nodes);
    t.setContours(contours, live: true);
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    if (_grab != _Grab.none) _t?.commit();
    _grab = _Grab.none;
    state.touch();
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    if (_t == null) return MouseCursor.defer;
    if (state.mode == PenMode.transform) return SystemMouseCursors.move;
    return _hitTest(ctx, screen) != null
        ? SystemMouseCursors.move
        : SystemMouseCursors.precise;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final t = _t;
    if (t == null) return;
    const accent = Color(0xFF3D7BFF);
    final contours = t.contours;
    // All shapes: thin outline; active one: stronger.
    for (var ci = 0; ci < contours.length; ci++) {
      final c = contours[ci];
      if (c.nodes.isEmpty) continue;
      final path = contourPath(c).transform(_matrix(ctx));
      // White halo keeps the outline readable on any color.
      canvas
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ci == state.active ? 5 : 3
            ..color = Colors.white.withValues(alpha: 0.85),
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = ci == state.active ? 2 : 1
            ..color = ci == state.active
                ? accent
                : accent.withValues(alpha: 0.4),
        );
    }
    final c = state.activeContour;
    if (c == null) return;
    if (state.mode == PenMode.transform && c.nodes.isNotEmpty) {
      final b = contourPath(c).getBounds();
      final corners = [
        b.topLeft,
        b.topRight,
        b.bottomRight,
        b.bottomLeft,
      ].map((p) => _screen(ctx, p)).toList();
      canvas.drawPath(
        Path()..addPolygon(corners, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = accent,
      );
      for (final p in corners) {
        canvas
          ..drawCircle(p, 6, Paint()..color = Colors.white)
          ..drawCircle(
            p,
            6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = accent,
          );
      }
      return;
    }
    final sel = state.node;
    for (var i = 0; i < c.nodes.length; i++) {
      final n = c.nodes[i];
      final p = _screen(ctx, n.point);
      final selected = i == sel;
      if (selected || (sel != null && (i - sel).abs() == 1)) {
        for (final h in [n.inHandle, n.outHandle]) {
          if (h == null) continue;
          final hp = _screen(ctx, h);
          canvas
            ..drawLine(
              p,
              hp,
              Paint()
                ..strokeWidth = 3.5
                ..color = Colors.white.withValues(alpha: 0.8),
            )
            ..drawCircle(hp, 7.5, Paint()..color = Colors.white)
            ..drawLine(
              p,
              hp,
              Paint()
                ..strokeWidth = 1.2
                ..color = accent.withValues(alpha: 0.8),
            )
            ..drawCircle(hp, 5.5, Paint()..color = accent)
            ..drawCircle(hp, 3, Paint()..color = Colors.white);
        }
      }
      final r = selected ? 8.0 : 6.5;
      final first = i == 0 && !c.closed;
      if (n.type == PathNodeType.corner) {
        final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
        canvas
          ..drawRect(rect.inflate(2.5), Paint()..color = Colors.white)
          ..drawRect(rect, Paint()..color = selected ? accent : Colors.white)
          ..drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = accent,
          );
      } else {
        canvas
          ..drawCircle(p, r + 2.5, Paint()..color = Colors.white)
          ..drawCircle(p, r, Paint()..color = selected ? accent : Colors.white)
          ..drawCircle(
            p,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = accent,
          );
      }
      if (first && c.nodes.length >= 3) {
        // Hint: tap the first node to close.
        canvas.drawCircle(
          p,
          r + 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFF22C55E),
        );
      }
    }
  }

  Float64List _matrix(ToolContext ctx) {
    final h = _t!.transform.homography;
    final s = ctx.viewport.scale, o = ctx.viewport.offset;
    // screen = s * H(p) + o (projective, so fold into the 3x3 first).
    final m = [
      h[0] * s + h[6] * o.dx,
      h[1] * s + h[7] * o.dx,
      h[2] * s + h[8] * o.dx,
      h[3] * s + h[6] * o.dy,
      h[4] * s + h[7] * o.dy,
      h[5] * s + h[8] * o.dy,
      h[6],
      h[7],
      h[8],
    ];
    return Float64List.fromList([
      m[0], m[3], 0, m[6], //
      m[1], m[4], 0, m[7], //
      0, 0, 1, 0, //
      m[2], m[5], 0, m[8], //
    ]);
  }
}
