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
  final grow =
      l.strokeWidth / 2 + (heads ? l.strokeWidth * 2.5 * l.headSize : 0);
  return b.inflate(math.max(2, grow));
}

List<double> _dashPattern(DashStyle d, double w, double k) {
  final u = math.max(1.0, w) * k;
  return switch (d) {
    DashStyle.solid => const [],
    DashStyle.dashed => [u * 3, u * 2],
    DashStyle.dotted => [0.01, u * 2],
    DashStyle.dashDot => [u * 3, u * 1.6, 0.01, u * 1.6],
  };
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

/// Paints a path layer: fill, (dashed) stroke and arrowheads.
void paintPathLayer(Canvas canvas, PathLayer l) {
  final path = pathLayerPath(l);
  final bounds = path.getBounds();
  if (l.fill != null) {
    canvas.drawPath(path, l.fill!.applyTo(Paint()..isAntiAlias = true, bounds));
  }
  if (l.strokeWidth <= 0) return;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = l.strokeWidth
    ..strokeCap = l.dash == DashStyle.dotted ? StrokeCap.round : l.cap
    ..strokeJoin = l.join
    ..color = l.strokeColor
    ..isAntiAlias = true;
  canvas.drawPath(
    _dashed(path, _dashPattern(l.dash, l.strokeWidth, l.dashScale)),
    stroke,
  );
  // Arrowheads on open contours.
  final headPaint = Paint()
    ..color = l.strokeColor
    ..isAntiAlias = true;
  final size = l.strokeWidth * 3 * l.headSize;
  for (final c in l.contours) {
    if (c.closed || c.nodes.length < 2) continue;
    final metrics = contourPath(c).computeMetrics().toList();
    if (metrics.isEmpty) continue;
    final m = metrics.first;
    if (l.startHead != ArrowHead.none) {
      final t = m.getTangentForOffset(math.min(0.5, m.length));
      if (t != null) {
        _head(canvas, l.startHead, t.position, -t.vector, size, headPaint, l);
      }
    }
    if (l.endHead != ArrowHead.none) {
      final t = m.getTangentForOffset(math.max(0, m.length - 0.5));
      if (t != null) {
        _head(canvas, l.endHead, t.position, t.vector, size, headPaint, l);
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
