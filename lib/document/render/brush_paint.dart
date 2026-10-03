import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show HSVColor;

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
double brushReach(BrushStroke s) => s.tip != null
    ? s.width * (0.75 + s.tip!.scatter)
    : switch (s.type) {
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
  final tip = s.tip ?? BrushTip.presetFor(s.type);
  if (tip != null) {
    // The whole stroke at its opacity (dabs build up inside it, never
    // past it), or erasing.
    final layer = Paint()..color = Color.fromRGBO(0, 0, 0, s.opacity);
    if (s.eraser) layer.blendMode = BlendMode.dstOut;
    canvas.saveLayer(null, layer);
    paintTipStroke(canvas, s, tip);
    canvas.restore();
    return;
  }
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
    // Tip brushes are drawn by paintTipStroke.
    default:
      stroke(w, blur: soft);
  }

  if (layered) canvas.restore();
}

// ─────────────────────────────── tip brushes

/// Tip bitmaps by (shape, hardness, roundness): white with the tip's
/// coverage in alpha, tinted per dab.
final Map<(TipShape, int, int), Image> _tips = {};
const double _tipSize = 128;

Image _tipImage(BrushTip t) {
  final key = (t.shape, (t.hardness * 20).round(), (t.roundness * 20).round());
  final hit = _tips[key];
  if (hit != null) return hit;
  final hard = key.$2 / 20, round = math.max(0.05, key.$3 / 20);
  final rec = PictureRecorder();
  final c = Canvas(rec);
  const half = _tipSize / 2;
  c
    ..translate(half, half)
    ..scale(1, round);
  final white = Paint()
    ..isAntiAlias = true
    ..color = const Color(0xFFFFFFFF);
  if (t.shape == TipShape.round) {
    // Soft edge as Photoshop: solid to `hardness` of the radius, then
    // falling to nothing at the rim.
    if (hard >= 0.999) {
      c.drawCircle(Offset.zero, half - 1, white);
    } else {
      c.drawCircle(
        Offset.zero,
        half,
        Paint()
          ..shader = Gradient.radial(
            Offset.zero,
            half,
            const [
              Color(0xFFFFFFFF),
              Color(0xFFFFFFFF),
              Color(0x80FFFFFF),
              Color(0x00FFFFFF),
            ],
            [0, hard, hard + (1 - hard) * 0.5, 1],
          ),
      );
    }
  } else {
    // Other shapes: softened with a blur, kept inside the bitmap.
    final soft = (1 - hard) * half * 0.35;
    final r = half - 2 - soft * 2.2;
    if (soft > 0.3) {
      white.maskFilter = MaskFilter.blur(BlurStyle.normal, soft);
    }
    c.drawPath(_tipPath(t.shape, r), white);
  }
  final pic = rec.endRecording();
  final img = pic.toImageSync(_tipSize.toInt(), _tipSize.toInt());
  pic.dispose();
  if (_tips.length > 48) _tips.remove(_tips.keys.first);
  return _tips[key] = img;
}

Path _tipPath(TipShape shape, double r) {
  switch (shape) {
    case TipShape.round:
      return Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
    case TipShape.square:
      return Path()
        ..addRect(Rect.fromCircle(center: Offset.zero, radius: r * 0.82));
    case TipShape.diamond:
      return Path()..addPolygon([
        Offset(0, -r),
        Offset(r, 0),
        Offset(0, r),
        Offset(-r, 0),
      ], true);
    case TipShape.star:
      final pts = <Offset>[
        for (var i = 0; i < 10; i++)
          Offset.fromDirection(
            -math.pi / 2 + i * math.pi / 5,
            i.isEven ? r : r * 0.42,
          ),
      ];
      return Path()..addPolygon(pts, true);
    case TipShape.leaf:
      // Pointed at both ends, with a central vein cut out.
      final leaf = Path()
        ..moveTo(0, -r)
        ..quadraticBezierTo(r * 0.95, -r * 0.1, 0, r)
        ..quadraticBezierTo(-r * 0.95, -r * 0.1, 0, -r)
        ..close();
      final vein = Path()
        ..addRect(Rect.fromLTRB(-r * 0.03, -r * 0.8, r * 0.03, r * 0.85));
      return Path.combine(PathOperation.difference, leaf, vein);
  }
}

/// Draws [s] as dabs of [tip] along its path — Photoshop's brush engine:
/// spacing, size from taper / pressure / jitter (never below the minimum),
/// angle (fixed, along the stroke, jittered), scattering with several dabs
/// a step, flow with jitter, and hue / saturation / brightness jitter.
void paintTipStroke(Canvas canvas, BrushStroke s, BrushTip tip) {
  final atlas = _tipImage(tip);
  final rnd = math.Random(s.seed);
  final w = s.width;
  final pts = s.points;
  final xforms = <RSTransform>[];
  final colors = <Color>[];
  final base = HSVColor.fromColor(s.color.withValues(alpha: 1));
  final jitterColour =
      tip.hueJitter > 0 || tip.saturationJitter > 0 || tip.brightnessJitter > 0;
  final rects = <Rect>[];
  const src = Rect.fromLTWH(0, 0, _tipSize, _tipSize);

  void dab(Offset at, double dir, double sizeK, double pressure) {
    final n = (tip.count * (1 - tip.countJitter * rnd.nextDouble()))
        .round()
        .clamp(1, 16);
    for (var k = 0; k < n; k++) {
      var size = sizeK * (1 - tip.sizeJitter * rnd.nextDouble());
      if (tip.pressureSize) size *= pressure;
      final floor = tip.minSize;
      if (size < floor && (tip.sizeJitter > 0 || tip.pressureSize)) {
        size = floor * sizeK;
      }
      final d = w * size;
      if (d < 0.2) continue;
      var a = tip.angle * math.pi / 180;
      if (tip.followPath) a += dir;
      if (tip.angleJitter > 0) {
        a += (rnd.nextDouble() * 2 - 1) * math.pi * tip.angleJitter;
      }
      var p = at;
      if (tip.scatter > 0) {
        final r = tip.scatter * w * math.sqrt(rnd.nextDouble());
        final t = rnd.nextDouble() * math.pi * 2;
        p += Offset(math.cos(t) * r, math.sin(t) * r);
      }
      var alpha = tip.flow * (1 - tip.flowJitter * rnd.nextDouble());
      if (tip.pressureOpacity) alpha *= pressure;
      var c = base;
      if (jitterColour) {
        c = HSVColor.fromAHSV(
          1,
          (base.hue + (rnd.nextDouble() * 2 - 1) * 180 * tip.hueJitter) % 360,
          (base.saturation + (rnd.nextDouble() * 2 - 1) * tip.saturationJitter)
              .clamp(0.0, 1.0),
          (base.value + (rnd.nextDouble() * 2 - 1) * tip.brightnessJitter)
              .clamp(0.0, 1.0),
        );
      }
      xforms.add(
        RSTransform.fromComponents(
          rotation: a,
          scale: d / _tipSize,
          anchorX: _tipSize / 2,
          anchorY: _tipSize / 2,
          translateX: p.dx,
          translateY: p.dy,
        ),
      );
      rects.add(src);
      colors.add(c.toColor().withValues(alpha: alpha.clamp(0.0, 1.0)));
    }
  }

  // Pressure at a fraction of the drawn length.
  final pr = s.pressures;
  final cum = <double>[0];
  for (var i = 1; i < pts.length; i++) {
    cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
  }
  final rawLen = cum.last;
  double pressureAt(double f) {
    if (pr == null || pr.isEmpty) return 1;
    if (pts.length < 2 || rawLen <= 0) return pr.first;
    final target = f * rawLen;
    var lo = 0, hi = cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      cum[mid] <= target ? lo = mid : hi = mid;
    }
    final span = cum[hi] - cum[lo];
    final t = span <= 0 ? 0.0 : (target - cum[lo]) / span;
    return pr[lo] + (pr[hi] - pr[lo]) * t;
  }

  if (pts.length == 1) {
    dab(pts.first, 0, 1, pressureAt(0));
  } else {
    final metrics = brushPath(pts).computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, m) => a + m.length);
    var walked = 0.0;
    var next = 0.0;
    var sizeK = 1.0;
    for (final m in metrics) {
      while (next <= walked + m.length && xforms.length < 60000) {
        final t = m.getTangentForOffset(next - walked);
        if (t == null) break;
        final f = total <= 0 ? 0.0 : next / total;
        // Taper: size grows in over the first part, out over the last.
        var taper = 1.0;
        if (tip.taperStart > 0 && f < tip.taperStart) {
          taper = f / tip.taperStart;
        }
        if (tip.taperEnd > 0 && f > 1 - tip.taperEnd) {
          taper = math.min(taper, (1 - f) / tip.taperEnd);
        }
        taper = math.max(tip.minSize, Curves.easeOut(taper));
        final p = pressureAt(f);
        sizeK = taper;
        dab(t.position, -t.angle, sizeK, p);
        // Photoshop spaces dabs by the current diameter.
        final cur = sizeK * (tip.pressureSize ? math.max(p, 0.2) : 1);
        next += math.max(0.35, tip.spacing * w * math.max(cur, 0.15));
      }
      walked += m.length;
    }
  }
  if (xforms.isEmpty) return;
  final paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;
  canvas.drawAtlas(
    atlas,
    xforms,
    rects,
    colors,
    BlendMode.modulate,
    null,
    paint,
  );
}

/// Ease-out, as a plain function (no Flutter animation import here).
abstract final class Curves {
  static double easeOut(double t) {
    final x = t.clamp(0.0, 1.0);
    return 1 - (1 - x) * (1 - x);
  }
}
