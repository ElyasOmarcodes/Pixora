import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/layer.dart';
import 'svg_path.dart';

final LinkedHashMap<(String, Rect, double, double), Path> _iconCache =
    LinkedHashMap();

/// The icon's path scaled (keeping its aspect ratio) into the layer box,
/// centred on the origin.
Path iconPath(IconLayer l) {
  final key = (l.pathData, l.viewBox, l.width, l.height);
  final hit = _iconCache.remove(key);
  if (hit != null) {
    _iconCache[key] = hit;
    return hit;
  }
  final vb = l.viewBox;
  final s = math.min(l.width / vb.width, l.height / vb.height);
  final m = Float64List(16)
    ..[0] = s
    ..[5] = s
    ..[10] = 1
    ..[15] = 1
    ..[12] = -(vb.left + vb.width / 2) * s
    ..[13] = -(vb.top + vb.height / 2) * s;
  final p = SvgPathCache.get(l.pathData).transform(m)
    ..fillType = PathFillType.nonZero;
  _iconCache[key] = p;
  if (_iconCache.length > 128) _iconCache.remove(_iconCache.keys.first);
  return p;
}

/// Path of one contour (bezier segments where handles exist).
Path contourPath(PathContour c, [Path? into]) {
  final p = into ?? Path();
  final n = c.nodes;
  if (n.isEmpty) return p;
  p.moveTo(n.first.point.dx, n.first.point.dy);
  void seg(PathNode a, PathNode b) {
    if (a.outHandle == null && b.inHandle == null) {
      p.lineTo(b.point.dx, b.point.dy);
    } else {
      final c1 = a.outHandle ?? a.point, c2 = b.inHandle ?? b.point;
      p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.point.dx, b.point.dy);
    }
  }

  for (var i = 1; i < n.length; i++) {
    seg(n[i - 1], n[i]);
  }
  if (c.closed && n.length > 1) {
    seg(n.last, n.first);
    p.close();
  }
  return p;
}

Path pathLayerPath(PathLayer l) {
  final p = Path()
    ..fillType = l.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
  for (final c in l.contours) {
    contourPath(c, p);
  }
  return p;
}

/// Local bounds of a path layer including stroke and arrowheads.
Rect pathLayerRect(PathLayer l) {
  final b = pathLayerPath(l).getBounds();
  if (b.isEmpty && b.width == 0 && b.height == 0) {
    return Rect.fromCenter(center: b.center, width: 20, height: 20);
  }
  final heads = l.startHead != ArrowHead.none || l.endHead != ArrowHead.none;
  final reach = l.align == StrokeAlign.outside
      ? l.strokeWidth
      : l.strokeWidth / 2 * (l.join == StrokeJoin.miter ? l.miterLimit : 1);
  final grow =
      reach +
      (heads ? l.strokeWidth * 2.5 * math.max(l.headSize, l.endSize) : 0);
  return b.inflate(math.max(2, grow));
}

List<double> _dashPattern(PathLayer l) {
  final u = math.max(1.0, l.strokeWidth) * l.dashScale;
  return switch (l.dash) {
    DashStyle.solid => const [],
    DashStyle.dashed => [u * 3, u * 2],
    DashStyle.dotted => [0.01, u * 2],
    DashStyle.dashDot => [u * 3, u * 1.6, 0.01, u * 1.6],
    // Dash, gap… in stroke widths (a 0 dash is a dot with round caps).
    DashStyle.custom =>
      l.dashPattern.every((v) => v <= 0)
          ? const []
          : [for (final v in l.dashPattern) math.max(0.01, v * u)],
  };
}

/// Width along a stroke at fraction [t] of its length (0..1 of the full
/// width).
double profileWidth(WidthProfile p, double t) {
  double ease(double x) => math.sin(x.clamp(0.0, 1.0) * math.pi / 2);
  return switch (p) {
    WidthProfile.uniform => 1,
    WidthProfile.taperStart => ease(t / 0.6),
    WidthProfile.taperEnd => ease((1 - t) / 0.6),
    WidthProfile.taperBoth => math.sin(t.clamp(0.0, 1.0) * math.pi),
    WidthProfile.bulge => 0.35 + 0.65 * math.sin(t.clamp(0.0, 1.0) * math.pi),
  };
}

/// A variable-width stroke as a filled outline: the path sampled finely,
/// both sides pushed out by half the profile's width, round ends.
Path _profiledStroke(Path src, double width, WidthProfile p, bool roundEnds) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    if (m.length <= 0) continue;
    final n = math
        .max(8, (m.length / math.max(1.0, width * 0.25)).ceil())
        .clamp(8, 2000);
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final tg = m.getTangentForOffset(m.length * i / n);
      if (tg == null) continue;
      final w = width / 2 * profileWidth(p, i / n);
      final nrm = Offset(-tg.vector.dy, tg.vector.dx);
      left.add(tg.position + nrm * w);
      right.add(tg.position - nrm * w);
    }
    if (left.length < 2) continue;
    var piece = Path()..addPolygon([...left, ...right.reversed], true);
    if (roundEnds) {
      // Round ends joined by a union: added as plain ovals, their winding
      // cancelled the outline and left notches.
      for (final (i, t) in [(0, 0.0), (left.length - 1, 1.0)]) {
        final r = width / 2 * profileWidth(p, t);
        if (r > 0.3) {
          piece = Path.combine(
            PathOperation.union,
            piece,
            Path()..addOval(
              Rect.fromCircle(center: (left[i] + right[i]) / 2, radius: r),
            ),
          );
        }
      }
    }
    out.addPath(piece, Offset.zero);
  }
  return out;
}

Path _dashed(Path src, List<double> pattern) {
  if (pattern.isEmpty) return src;
  final out = Path();
  for (final m in src.computeMetrics()) {
    var d = 0.0, i = 0;
    var draw = true;
    while (d < m.length) {
      final len = pattern[i % pattern.length];
      if (draw) out.addPath(m.extractPath(d, d + len), Offset.zero);
      d += len;
      draw = !draw;
      i++;
    }
  }
  return out;
}

/// Paints a path layer: fill, (dashed, aligned, profiled) stroke and
/// arrowheads.
void paintPathLayer(Canvas canvas, PathLayer l) {
  final path = pathLayerPath(l);
  final bounds = path.getBounds();
  if (l.fill != null) {
    canvas.drawPath(path, l.fill!.applyTo(Paint()..isAntiAlias = true, bounds));
  }
  if (l.strokeWidth <= 0) return;
  // Inside / outside strokes (closed paths, as Illustrator): a stroke
  // twice as wide, clipped to the shape or to everything but the shape.
  final closed = l.contours.isNotEmpty && l.contours.every((c) => c.closed);
  final aligned = closed && l.align != StrokeAlign.center;
  final width = aligned ? l.strokeWidth * 2 : l.strokeWidth;
  if (aligned) {
    canvas.save();
    if (l.align == StrokeAlign.inside) {
      canvas.clipPath(path);
    } else {
      final room = bounds.inflate(l.strokeWidth * (l.miterLimit + 2) + 4);
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(room)
          ..addPath(path, Offset.zero),
      );
    }
  }
  final pattern = _dashPattern(l);
  if (l.profile != WidthProfile.uniform && pattern.isEmpty) {
    canvas.drawPath(
      _profiledStroke(path, width, l.profile, l.cap == StrokeCap.round),
      Paint()
        ..isAntiAlias = true
        ..color = l.strokeColor,
    );
  } else {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = l.dash == DashStyle.dotted ? StrokeCap.round : l.cap
      ..strokeJoin = l.join
      ..strokeMiterLimit = l.miterLimit
      ..color = l.strokeColor
      ..isAntiAlias = true;
    canvas.drawPath(_dashed(path, pattern), stroke);
  }
  if (aligned) canvas.restore();
  // Arrowheads on open contours (their size follows the profile's end).
  final headPaint = Paint()
    ..color = l.strokeColor
    ..isAntiAlias = true;
  for (final c in l.contours) {
    if (c.closed || c.nodes.length < 2) continue;
    final metrics = contourPath(c).computeMetrics().toList();
    if (metrics.isEmpty) continue;
    final m = metrics.first;
    if (l.startHead != ArrowHead.none) {
      final t = m.getTangentForOffset(math.min(0.5, m.length));
      if (t != null) {
        _head(
          canvas,
          l.startHead,
          t.position,
          -t.vector,
          l.strokeWidth * 3 * l.headSize,
          headPaint,
          l,
        );
      }
    }
    if (l.endHead != ArrowHead.none) {
      final t = m.getTangentForOffset(math.max(0, m.length - 0.5));
      if (t != null) {
        _head(
          canvas,
          l.endHead,
          t.position,
          t.vector,
          l.strokeWidth * 3 * l.endSize,
          headPaint,
          l,
        );
      }
    }
  }
}

void _head(
  Canvas canvas,
  ArrowHead kind,
  Offset tip,
  Offset dir,
  double size,
  Paint paint,
  PathLayer l,
) {
  final len = dir.distance;
  if (len == 0) return;
  final d = dir / len;
  final nrm = Offset(-d.dy, d.dx);
  switch (kind) {
    case ArrowHead.none:
      return;
    case ArrowHead.arrow:
      canvas.drawPath(
        Path()
          ..moveTo(
            tip.dx - d.dx * size + nrm.dx * size * 0.7,
            tip.dy - d.dy * size + nrm.dy * size * 0.7,
          )
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - d.dx * size - nrm.dx * size * 0.7,
            tip.dy - d.dy * size - nrm.dy * size * 0.7,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = l.strokeColor
          ..isAntiAlias = true,
      );
    case ArrowHead.triangle:
      final base = tip - d * size;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + d.dx * size * 0.3, tip.dy + d.dy * size * 0.3)
          ..lineTo(base.dx + nrm.dx * size * 0.6, base.dy + nrm.dy * size * 0.6)
          ..lineTo(base.dx - nrm.dx * size * 0.6, base.dy - nrm.dy * size * 0.6)
          ..close(),
        paint,
      );
    case ArrowHead.circle:
      canvas.drawCircle(tip, size * 0.45, paint);
    case ArrowHead.square:
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(math.atan2(d.dy, d.dx));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: size * 0.8,
          height: size * 0.8,
        ),
        paint,
      );
      canvas.restore();
    case ArrowHead.diamond:
      final a = tip + d * size * 0.5, b = tip - d * size * 0.5;
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(tip.dx + nrm.dx * size * 0.4, tip.dy + nrm.dy * size * 0.4)
          ..lineTo(b.dx, b.dy)
          ..lineTo(tip.dx - nrm.dx * size * 0.4, tip.dy - nrm.dy * size * 0.4)
          ..close(),
        paint,
      );
    case ArrowHead.stealth:
      // A dart with a notched back.
      final back = tip - d * size;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + d.dx * size * 0.3, tip.dy + d.dy * size * 0.3)
          ..lineTo(
            back.dx + nrm.dx * size * 0.65,
            back.dy + nrm.dy * size * 0.65,
          )
          ..lineTo(tip.dx - d.dx * size * 0.55, tip.dy - d.dy * size * 0.55)
          ..lineTo(
            back.dx - nrm.dx * size * 0.65,
            back.dy - nrm.dy * size * 0.65,
          )
          ..close(),
        paint,
      );
    case ArrowHead.openTriangle:
      final base = tip - d * size;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + nrm.dx * size * 0.6, base.dy + nrm.dy * size * 0.6)
          ..lineTo(base.dx - nrm.dx * size * 0.6, base.dy - nrm.dy * size * 0.6)
          ..close(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, l.strokeWidth * 0.7)
          ..strokeJoin = StrokeJoin.round
          ..color = l.strokeColor
          ..isAntiAlias = true,
      );
    case ArrowHead.openCircle:
      canvas.drawCircle(
        tip,
        size * 0.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, l.strokeWidth * 0.7)
          ..color = l.strokeColor
          ..isAntiAlias = true,
      );
    case ArrowHead.bar:
      canvas.drawLine(
        tip + nrm * size * 0.6,
        tip - nrm * size * 0.6,
        Paint()
          ..strokeWidth = l.strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = l.strokeColor,
      );
  }
}
