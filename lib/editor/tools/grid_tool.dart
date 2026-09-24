import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../document/model/document.dart';
import '../../document/model/guides.dart';
import 'editor_tool.dart';

enum GuideLineKind {
  gridVertical,
  gridHorizontal,
  guideVertical,
  guideHorizontal,
}

/// Identifies one grid line or ruler guide.
@immutable
class GuideLineRef {
  const GuideLineRef(this.kind, this.index);
  final GuideLineKind kind;
  final int index;

  bool get isGrid =>
      kind == GuideLineKind.gridVertical ||
      kind == GuideLineKind.gridHorizontal;
  bool get isVertical =>
      kind == GuideLineKind.gridVertical || kind == GuideLineKind.guideVertical;

  @override
  bool operator ==(Object other) =>
      other is GuideLineRef && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

/// Geometry of grid lines and guides in document space.
abstract final class GuideGeometry {
  /// End points of a line (document space). Grid lines are rotated with
  /// the grid and extended across the whole canvas.
  static (Offset, Offset) segment(PixDocument doc, GuideLineRef ref) {
    final g = doc.guides;
    final w = doc.width, h = doc.height;
    switch (ref.kind) {
      case GuideLineKind.guideVertical:
        final x = g.vertical[ref.index];
        return (Offset(x, 0), Offset(x, h));
      case GuideLineKind.guideHorizontal:
        final y = g.horizontal[ref.index];
        return (Offset(0, y), Offset(w, y));
      case GuideLineKind.gridVertical || GuideLineKind.gridHorizontal:
        final diag = math.sqrt(w * w + h * h);
        final vertical = ref.kind == GuideLineKind.gridVertical;
        final f = vertical
            ? g.grid.verticalLines[ref.index]
            : g.grid.horizontalLines[ref.index];
        final a = vertical
            ? Offset(f * w - w / 2, -diag)
            : Offset(-diag, f * h - h / 2);
        final b = vertical
            ? Offset(f * w - w / 2, diag)
            : Offset(diag, f * h - h / 2);
        final c = doc.center;
        return (
          c + _rot(a, g.grid.rotationRadians),
          c + _rot(b, g.grid.rotationRadians),
        );
    }
  }

  static Offset _rot(Offset p, double a) {
    final c = math.cos(a), s = math.sin(a);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  /// All lines currently shown.
  static List<GuideLineRef> all(PixDocument doc) {
    final g = doc.guides;
    return [
      if (g.grid.visible) ...[
        for (var i = 0; i < g.grid.verticalLines.length; i++)
          GuideLineRef(GuideLineKind.gridVertical, i),
        for (var i = 0; i < g.grid.horizontalLines.length; i++)
          GuideLineRef(GuideLineKind.gridHorizontal, i),
      ],
      for (var i = 0; i < g.vertical.length; i++)
        GuideLineRef(GuideLineKind.guideVertical, i),
      for (var i = 0; i < g.horizontal.length; i++)
        GuideLineRef(GuideLineKind.guideHorizontal, i),
    ];
  }

  static double distanceTo(Offset p, (Offset, Offset) seg) {
    final (a, b) = seg;
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// Moves [ref] to pass through [docPoint]; returns null when the point is
  /// outside the canvas (dragging a line off the canvas deletes it).
  static CanvasGuides? moveTo(
    PixDocument doc,
    GuideLineRef ref,
    Offset docPoint,
  ) {
    final g = doc.guides;
    switch (ref.kind) {
      case GuideLineKind.guideVertical:
        if (docPoint.dx < 0 || docPoint.dx > doc.width) return null;
        return g.copyWith(vertical: [...g.vertical]..[ref.index] = docPoint.dx);
      case GuideLineKind.guideHorizontal:
        if (docPoint.dy < 0 || docPoint.dy > doc.height) return null;
        return g.copyWith(
          horizontal: [...g.horizontal]..[ref.index] = docPoint.dy,
        );
      case GuideLineKind.gridVertical || GuideLineKind.gridHorizontal:
        final q = _rot(docPoint - doc.center, -g.grid.rotationRadians);
        final vertical = ref.kind == GuideLineKind.gridVertical;
        final f = vertical ? q.dx / doc.width + 0.5 : q.dy / doc.height + 0.5;
        if (f <= 0 || f >= 1) return null;
        final lines = [
          ...(vertical ? g.grid.verticalLines : g.grid.horizontalLines),
        ];
        lines[ref.index] = f;
        return g.copyWith(
          grid: vertical
              ? g.grid.copyWith(xLines: lines)
              : g.grid.copyWith(yLines: lines),
        );
    }
  }

  static CanvasGuides remove(PixDocument doc, GuideLineRef ref) {
    final g = doc.guides;
    switch (ref.kind) {
      case GuideLineKind.guideVertical:
        return g.copyWith(vertical: [...g.vertical]..removeAt(ref.index));
      case GuideLineKind.guideHorizontal:
        return g.copyWith(horizontal: [...g.horizontal]..removeAt(ref.index));
      case GuideLineKind.gridVertical:
        return g.copyWith(
          grid: g.grid.copyWith(
            xLines: [...g.grid.verticalLines]..removeAt(ref.index),
          ),
        );
      case GuideLineKind.gridHorizontal:
        return g.copyWith(
          grid: g.grid.copyWith(
            yLines: [...g.grid.horizontalLines]..removeAt(ref.index),
          ),
        );
    }
  }
}

/// Edits the grid and ruler guides directly on the canvas. While active,
/// layers can't be picked: tap a line to select it, drag it to move it,
/// drag it off the canvas (or tap its ✕ / press Delete) to remove it.
/// Dragging empty space pans the canvas.
class GridTool extends EditorTool {
  GuideLineRef? selected;
  GuideLineRef? _dragging;
  bool _removeOnRelease = false;

  static const double hitPx = 14;
  static const double deleteRadius = 13;

  @override
  String get id => 'grid';

  GuideLineRef? _hit(ToolContext ctx, Offset screen) {
    final doc = ctx.editor.document;
    final p = ctx.viewport.toDoc(screen);
    final tol = hitPx / ctx.viewport.scale;
    GuideLineRef? best;
    var bestD = double.infinity;
    for (final ref in GuideGeometry.all(doc)) {
      final d = GuideGeometry.distanceTo(p, GuideGeometry.segment(doc, ref));
      if (d < tol && d < bestD) {
        best = ref;
        bestD = d;
      }
    }
    return best;
  }

  /// Screen position of the ✕ button of the selected line (just inside
  /// the canvas at the line's start).
  Offset? _deleteButton(ToolContext ctx) {
    final ref = selected;
    final doc = ctx.editor.document;
    if (ref == null || !GuideGeometry.all(doc).contains(ref)) return null;
    final (a, b) = GuideGeometry.segment(doc, ref);
    // Point where the line enters the canvas, nudged inward.
    final r = doc.bounds.deflate(1);
    for (var t = 0.0; t <= 1; t += 0.005) {
      final p = Offset.lerp(a, b, t)!;
      if (r.contains(p)) {
        final dir = (b - a) / (b - a).distance;
        return ctx.viewport.toScreen(p) + dir * 22;
      }
    }
    return null;
  }

  void deleteSelected(ToolContext ctx) {
    final ref = selected;
    if (ref == null) return;
    selected = null;
    ctx.editor.updateGuides(
      (_) => GuideGeometry.remove(ctx.editor.document, ref),
      label: 'guides',
    );
  }

  @override
  void onTap(ToolContext ctx, Offset screen) {
    final del = _deleteButton(ctx);
    if (del != null && (screen - del).distance <= deleteRadius + 6) {
      deleteSelected(ctx);
      return;
    }
    selected = _hit(ctx, screen);
    ctx.requestRepaint();
  }

  @override
  bool onScaleStart(ToolContext ctx, ScaleStartDetails d) {
    if (d.pointerCount > 1 || d.kind == PointerDeviceKind.trackpad) {
      return false;
    }
    final ref = _hit(ctx, d.localFocalPoint);
    if (ref == null) return false;
    selected = ref;
    _dragging = ref;
    _removeOnRelease = false;
    return true;
  }

  @override
  void onScaleUpdate(ToolContext ctx, ScaleUpdateDetails d) {
    final ref = _dragging;
    if (ref == null) return;
    final e = ctx.editor;
    final next = GuideGeometry.moveTo(
      e.document,
      ref,
      ctx.viewport.toDoc(d.localFocalPoint),
    );
    _removeOnRelease = next == null;
    if (next != null) e.updateGuides((_) => next, live: true);
    ctx.requestRepaint();
  }

  @override
  void onScaleEnd(ToolContext ctx, ScaleEndDetails d) {
    final ref = _dragging;
    _dragging = null;
    if (ref == null) return;
    if (_removeOnRelease) {
      final doc = ctx.editor.document;
      ctx.editor.updateGuides(
        (_) => GuideGeometry.remove(doc, ref),
        label: 'guides',
      );
      selected = null;
    } else {
      ctx.editor.commit('guides');
    }
    ctx.requestRepaint();
  }

  @override
  MouseCursor cursorAt(ToolContext ctx, Offset screen) {
    final ref = _hit(ctx, screen);
    if (ref == null) return SystemMouseCursors.grab;
    return ref.isVertical && ref.kind != GuideLineKind.gridVertical ||
            (ref.kind == GuideLineKind.gridVertical &&
                ctx.editor.document.guides.grid.rotation == 0)
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
  }

  @override
  void paintOverlay(Canvas canvas, Size size, ToolContext ctx) {
    final doc = ctx.editor.document;
    final vp = ctx.viewport;
    // Draggable dots at the middle of every line.
    final dot = Paint()..color = ctx.style.selection;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    for (final ref in GuideGeometry.all(doc)) {
      final (a, b) = GuideGeometry.segment(doc, ref);
      final m = vp.toScreen(_midInside(doc, a, b));
      canvas
        ..drawCircle(m, 6, dot)
        ..drawCircle(m, 6, ring);
    }
    final ref = selected;
    if (ref == null || !GuideGeometry.all(doc).contains(ref)) return;
    final (a, b) = GuideGeometry.segment(doc, ref);
    canvas
      ..save()
      ..clipRect(
        Rect.fromPoints(
          vp.toScreen(Offset.zero),
          vp.toScreen(Offset(doc.width, doc.height)),
        ),
      )
      ..drawLine(
        vp.toScreen(a),
        vp.toScreen(b),
        Paint()
          ..color = ctx.style.selection
          ..strokeWidth = 3,
      )
      ..restore();
    final del = _deleteButton(ctx);
    if (del != null) {
      canvas.drawCircle(
        del,
        deleteRadius,
        Paint()..color = const Color(0xFFE5484D),
      );
      final x = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      const k = 5.0;
      canvas
        ..drawLine(del + const Offset(-k, -k), del + const Offset(k, k), x)
        ..drawLine(del + const Offset(k, -k), del + const Offset(-k, k), x);
    }
  }

  static Offset _midInside(PixDocument doc, Offset a, Offset b) {
    final r = doc.bounds;
    Offset? first, last;
    for (var t = 0.0; t <= 1; t += 0.01) {
      final p = Offset.lerp(a, b, t)!;
      if (r.contains(p)) {
        first ??= p;
        last = p;
      }
    }
    if (first == null || last == null) return doc.center;
    return (first + last) / 2;
  }
}

/// Paints the grid and ruler guides (all tools).
void paintGuides(
  Canvas canvas,
  PixDocument doc,
  CanvasViewport vp, {
  Color guideColor = const Color(0xFF00C2FF),
}) {
  final g = doc.guides;
  final clip = Rect.fromPoints(
    vp.toScreen(Offset.zero),
    vp.toScreen(Offset(doc.width, doc.height)),
  );
  canvas
    ..save()
    ..clipRect(clip);
  final shadow = Paint()
    ..color = Colors.black.withValues(alpha: 0.22)
    ..strokeWidth = 2.5;
  if (g.grid.visible) {
    final p = Paint()
      ..color = g.grid.color.withValues(alpha: g.grid.opacity)
      ..strokeWidth = 1;
    for (final ref in GuideGeometry.all(doc).where((r) => r.isGrid)) {
      final (a, b) = GuideGeometry.segment(doc, ref);
      canvas
        ..drawLine(vp.toScreen(a), vp.toScreen(b), shadow)
        ..drawLine(vp.toScreen(a), vp.toScreen(b), p);
    }
  }
  final guide = Paint()
    ..color = guideColor
    ..strokeWidth = 1.2;
  for (final ref in GuideGeometry.all(doc).where((r) => !r.isGrid)) {
    final (a, b) = GuideGeometry.segment(doc, ref);
    canvas.drawLine(vp.toScreen(a), vp.toScreen(b), guide);
  }
  canvas.restore();
}
