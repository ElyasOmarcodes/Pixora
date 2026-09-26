import 'dart:ui';

import '../../document/model/layer.dart';
import '../../document/render/document_renderer.dart';
import 'editor_tool.dart';

/// Lines (document pixels) that moving things snap to, per [SnapOptions]:
/// canvas edges and centre, guides and grid lines, and other layers'
/// edges and centres (smart guides).
class SnapTargets {
  SnapTargets(this.xs, this.ys);
  final List<double> xs;
  final List<double> ys;

  /// Screen pixels within which a snap engages.
  static const double snapPx = 7;

  factory SnapTargets.of(ToolContext ctx, {bool Function(Layer)? skip}) {
    final doc = ctx.editor.document;
    final opts = ctx.snap;
    final xs = <double>[], ys = <double>[];
    if (!opts.positions) return SnapTargets(xs, ys);
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
      for (final l in doc.allLayers) {
        if (l is GroupLayer || !doc.isEffectivelyVisible(l.id)) continue;
        if (skip != null && skip(l)) continue;
        final o = layerDocumentBounds(l);
        xs.addAll([o.left, o.center.dx, o.right]);
        ys.addAll([o.top, o.center.dy, o.bottom]);
      }
    }
    return SnapTargets(xs, ys);
  }

  /// Adds a box's edges and centre as targets.
  void addBox(Rect r) {
    xs.addAll([r.left, r.center.dx, r.right]);
    ys.addAll([r.top, r.center.dy, r.bottom]);
  }

  void addPoint(Offset p) {
    xs.add(p.dx);
    ys.add(p.dy);
  }

  /// The smallest shift (within [threshold]) that lands one of [edges] on
  /// a target, and that target; (0, null) when nothing is near.
  static (double, double?) nearest(
    List<double> targets,
    List<double> edges,
    double threshold,
  ) {
    double? best, line;
    for (final t in targets) {
      for (final e in edges) {
        final d = t - e;
        if (d.abs() <= threshold && (best == null || d.abs() < best.abs())) {
          best = d;
          line = t;
        }
      }
    }
    return (best ?? 0, line);
  }

  /// Snaps a box moved to [box]: the shift to apply and the guide lines hit.
  (Offset, double?, double?) snapBox(Rect box, double threshold) {
    final (dx, gx) = nearest(xs, [
      box.left,
      box.center.dx,
      box.right,
    ], threshold);
    final (dy, gy) = nearest(ys, [
      box.top,
      box.center.dy,
      box.bottom,
    ], threshold);
    return (Offset(dx, dy), gx, gy);
  }

  /// Snaps a point: the snapped point and the guide lines hit.
  (Offset, double?, double?) snapPoint(Offset p, double threshold) {
    final (dx, gx) = nearest(xs, [p.dx], threshold);
    final (dy, gy) = nearest(ys, [p.dy], threshold);
    return (p + Offset(dx, dy), gx, gy);
  }
}

/// Draws snap guide lines across the canvas.
void paintSnapGuides(
  Canvas canvas,
  ToolContext ctx,
  Iterable<double> xs,
  Iterable<double> ys,
) {
  final vp = ctx.viewport;
  final doc = ctx.editor.document;
  final guide = Paint()
    ..color = ctx.style.guide
    ..strokeWidth = 1.2;
  final top = vp.toScreen(Offset.zero).dy,
      bottom = vp.toScreen(Offset(0, doc.height)).dy;
  final left = vp.toScreen(Offset.zero).dx,
      right = vp.toScreen(Offset(doc.width, 0)).dx;
  for (final x in xs) {
    final sx = vp.toScreen(Offset(x, 0)).dx;
    canvas.drawLine(Offset(sx, top), Offset(sx, bottom), guide);
  }
  for (final y in ys) {
    final sy = vp.toScreen(Offset(0, y)).dy;
    canvas.drawLine(Offset(left, sy), Offset(right, sy), guide);
  }
}
