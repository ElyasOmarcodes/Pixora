import 'dart:math' as math;
import 'dart:ui';

import '../model/layer.dart';

/// Smooth path through freehand points (quadratic curves between
/// midpoints), so strokes look fluid instead of jagged.
Path brushPath(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length < 3) {
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final m = (pts[i] + pts[i + 1]) / 2;
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

/// How far a stroke's paint reaches beyond its centre line.
double brushReach(BrushStroke s) => switch (s.type) {
  BrushType.neon => s.width * 1.6,
  BrushType.airbrush => s.width * 1.3,
  BrushType.spray => s.width * 0.6,
  _ => s.width * (0.5 + s.softness),
};

/// Local bounds of a drawing layer.
Rect drawingRect(DrawingLayer l) {
  Rect? r;
  for (final s in l.strokes) {
    if (s.points.isEmpty) continue;
    var b = Rect.fromPoints(s.points.first, s.points.first);
    for (final p in s.points) {
      b = b.expandToInclude(Rect.fromPoints(p, p));
    }
    b = b.inflate(brushReach(s) + 1);
    r = r == null ? b : r.expandToInclude(b);
  }
  return r ?? Rect.fromCenter(center: Offset.zero, width: 40, height: 40);
}

/// Paints all strokes of [l] (erasers only affect this layer).
void paintDrawing(Canvas canvas, DrawingLayer l) {
  if (l.strokes.isEmpty) return;
  final isolate = l.strokes.any((s) => s.eraser);
  if (isolate) canvas.saveLayer(drawingRect(l), Paint());
  for (final s in l.strokes) {
    paintBrushStroke(canvas, s);
  }
  if (isolate) canvas.restore();
}

/// Paints one stroke.
void paintBrushStroke(Canvas canvas, BrushStroke s) {
  if (s.points.isEmpty || s.opacity <= 0) return;
  final w = s.width;
  final color = s.color.withValues(alpha: 1);

  // Whole-stroke opacity (so the stroke never darkens where it overlaps
  // itself) and eraser / highlighter blending happen on a layer.
  final layered =
      s.eraser ||
      s.opacity < 1 ||
      s.type == BrushType.marker ||
      s.type == BrushType.highlighter ||
      s.type == BrushType.calligraphy ||
      s.type == BrushType.spray ||
      s.type == BrushType.neon;
  if (layered) {
    final layer = Paint()
      ..color = Color.fromRGBO(
        0,
        0,
        0,
        (s.type == BrushType.highlighter ? 0.45 : 1) * s.opacity,
      );
    if (s.eraser) layer.blendMode = BlendMode.dstOut;
    if (s.type == BrushType.highlighter && !s.eraser) {
      layer.blendMode = BlendMode.multiply;
    }
    canvas.saveLayer(null, layer);
  }

  Paint line(double width, {Color? c, double blur = 0}) {
    final p = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c ?? color;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  Paint dotPaint(double r, {Color? c, double blur = 0}) {
    final p = Paint()
      ..isAntiAlias = true
      ..color = c ?? color;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  void stroke(double width, {Color? c, double blur = 0, StrokeCap? cap}) {
    if (s.points.length == 1) {
      final p = s.points.first;
      if (cap == StrokeCap.square) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: width, height: width),
          dotPaint(width / 2, c: c, blur: blur),
        );
      } else {
        canvas.drawCircle(p, width / 2, dotPaint(width / 2, c: c, blur: blur));
      }
      return;
    }
    final paint = line(width, c: c, blur: blur);
    if (cap != null) {
      paint
        ..strokeCap = cap
        ..strokeJoin = cap == StrokeCap.square
            ? StrokeJoin.bevel
            : StrokeJoin.round;
    }
    canvas.drawPath(brushPath(s.points), paint);
  }

  final soft = s.softness * w * 0.35;
  switch (s.type) {
    case BrushType.pen:
      stroke(w, blur: soft);
    case BrushType.pencil:
      stroke(
        math.max(0.5, w * 0.6),
        c: color.withValues(alpha: 0.85),
        blur: soft * 0.3,
      );
    case BrushType.marker:
      stroke(w, blur: soft, cap: StrokeCap.square);
    case BrushType.highlighter:
      stroke(w * 1.4, blur: soft, cap: StrokeCap.square);
    case BrushType.airbrush:
      stroke(
        w,
        c: color.withValues(alpha: 0.75),
        blur: w * (0.35 + s.softness * 0.4),
      );
    case BrushType.calligraphy:
      // A flat nib held at 45°: wide on one diagonal, thin on the other.
      final n =
          Offset(math.cos(-math.pi / 4), math.sin(-math.pi / 4)) * (w / 2);
      final fill = Paint()
        ..isAntiAlias = true
        ..color = color;
      if (soft > 0) fill.maskFilter = MaskFilter.blur(BlurStyle.normal, soft);
      final pts = s.points;
      if (pts.length == 1) {
        canvas.drawLine(pts.first - n, pts.first + n, line(w * 0.15));
      }
      for (var i = 0; i + 1 < pts.length; i++) {
        final a = pts[i], b = pts[i + 1];
        canvas.drawPath(
          Path()..addPolygon([a + n, b + n, b - n, a - n], true),
          fill,
        );
      }
      stroke(math.max(0.5, w * 0.12));
    case BrushType.spray:
      final rnd = math.Random(s.seed);
      final dots = <Offset>[];
      final step = math.max(1.0, w / 5);
      final pts = s.points;
      void sprayAt(Offset c) {
        final n = (w * 0.9).clamp(4, 60).round();
        for (var k = 0; k < n; k++) {
          final r = w / 2 * math.sqrt(rnd.nextDouble());
          final a = rnd.nextDouble() * math.pi * 2;
          dots.add(c + Offset(math.cos(a) * r, math.sin(a) * r));
        }
      }

      sprayAt(pts.first);
      for (var i = 0; i + 1 < pts.length && dots.length < 20000; i++) {
        final a = pts[i], b = pts[i + 1];
        final d = (b - a).distance;
        for (var t = step; t <= d; t += step) {
          sprayAt(Offset.lerp(a, b, t / d)!);
        }
      }
      canvas.drawPoints(
        PointMode.points,
        dots,
        Paint()
          ..isAntiAlias = true
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1, w * 0.06)
          ..color = color,
      );
    case BrushType.neon:
      stroke(w * 1.6, c: color.withValues(alpha: 0.55), blur: w * 0.6);
      stroke(w * 0.8, blur: w * 0.08);
      stroke(w * 0.3, c: Color.lerp(color, const Color(0xFFFFFFFF), 0.8));
  }

  if (layered) canvas.restore();
}
