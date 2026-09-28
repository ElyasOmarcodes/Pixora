import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/layer.dart';

/// One adjustable option of a shape (drives sliders and the AI schema).
class ShapeParam {
  const ShapeParam(
    this.key,
    this.min,
    this.max,
    this.defaultValue, {
    this.step,
    this.unit = ShapeParamUnit.ratio,
  });
  final String key;
  final double min;
  final double max;
  final double defaultValue;
  final double? step;
  final ShapeParamUnit unit;
}

enum ShapeParamUnit { ratio, degrees, count }

/// What each shape can be tuned with (besides size, corner radius and
/// point/side count which are fields of the layer).
List<ShapeParam> shapeParams(ShapeKind k) => switch (k) {
  ShapeKind.ellipse => const [
    ShapeParam('sweep', 1, 360, 360, unit: ShapeParamUnit.degrees),
    ShapeParam('start', -180, 180, 0, unit: ShapeParamUnit.degrees),
    ShapeParam('inner', 0, 0.95, 0),
  ],
  ShapeKind.triangle => const [ShapeParam('apex', 0, 1, 0.5)],
  ShapeKind.star => const [
    ShapeParam('inner', 0.1, 0.95, 0.45),
    ShapeParam('round', 0, 1, 0),
  ],
  ShapeKind.polygon ||
  ShapeKind.diamond => const [ShapeParam('round', 0, 1, 0)],
  ShapeKind.parallelogram => const [ShapeParam('skew', -0.8, 0.8, 0.25)],
  ShapeKind.trapezoid => const [ShapeParam('top', 0.05, 1, 0.6)],
  ShapeKind.cross => const [ShapeParam('thickness', 0.1, 0.9, 0.33)],
  ShapeKind.crescent => const [ShapeParam('offset', 0.1, 0.9, 0.35)],
  ShapeKind.speechBubble => const [
    ShapeParam('tailPos', 0, 1, 0.25),
    ShapeParam('tail', 0.05, 0.5, 0.22),
    ShapeParam('round', 0, 0.5, 0.18),
  ],
  ShapeKind.blockArrow => const [
    ShapeParam('shaft', 0.1, 0.9, 0.42),
    ShapeParam('head', 0.1, 0.9, 0.4),
    ShapeParam('heads', 1, 2, 1, step: 1, unit: ShapeParamUnit.count),
  ],
  ShapeKind.chevron => const [ShapeParam('thickness', 0.1, 0.9, 0.4)],
  ShapeKind.gear => const [
    ShapeParam('depth', 0.05, 0.45, 0.18),
    ShapeParam('hole', 0, 0.8, 0.3),
  ],
  ShapeKind.frame => const [ShapeParam('thickness', 0.02, 0.49, 0.12)],
  ShapeKind.rectangle || ShapeKind.heart || ShapeKind.line => const [],
};

double _p(ShapeLayer s, String k) {
  for (final spec in shapeParams(s.shape)) {
    if (spec.key == k) return s.param(k, spec.defaultValue);
  }
  return 0;
}

/// The sharp corners of a shape (centred on the origin), in order —
/// rectangles and frames from the top-left, clockwise — or null for
/// shapes without corners (ellipse, heart, crescent, line, bubble).
List<Offset>? shapeCorners(ShapeLayer s) {
  final w = s.width, h = s.height;
  double p(String k) => _p(s, k);
  return switch (s.shape) {
    ShapeKind.rectangle || ShapeKind.frame => [
      Offset(-w / 2, -h / 2),
      Offset(w / 2, -h / 2),
      Offset(w / 2, h / 2),
      Offset(-w / 2, h / 2),
    ],
    ShapeKind.triangle => [
      Offset(-w / 2 + w * p('apex'), -h / 2),
      Offset(w / 2, h / 2),
      Offset(-w / 2, h / 2),
    ],
    ShapeKind.star => _starPoints(w, h, s.sides.clamp(3, 64), p('inner')),
    ShapeKind.polygon => _polygonPoints(w, h, s.sides.clamp(3, 64)),
    ShapeKind.diamond => [
      Offset(0, -h / 2),
      Offset(w / 2, 0),
      Offset(0, h / 2),
      Offset(-w / 2, 0),
    ],
    ShapeKind.parallelogram => () {
      final k = p('skew') * w / 2;
      return [
        Offset(-w / 2 + k.clamp(0, w), -h / 2),
        Offset(w / 2 + math.min(0, k), -h / 2),
        Offset(w / 2 - k.clamp(0, w), h / 2),
        Offset(-w / 2 - math.min(0, k), h / 2),
      ];
    }(),
    ShapeKind.trapezoid => () {
      final t = p('top') * w / 2;
      return [
        Offset(-t, -h / 2),
        Offset(t, -h / 2),
        Offset(w / 2, h / 2),
        Offset(-w / 2, h / 2),
      ];
    }(),
    ShapeKind.cross => () {
      final tx = w * p('thickness') / 2, ty = h * p('thickness') / 2;
      return [
        Offset(-tx, -h / 2),
        Offset(tx, -h / 2),
        Offset(tx, -ty),
        Offset(w / 2, -ty),
        Offset(w / 2, ty),
        Offset(tx, ty),
        Offset(tx, h / 2),
        Offset(-tx, h / 2),
        Offset(-tx, ty),
        Offset(-w / 2, ty),
        Offset(-w / 2, -ty),
        Offset(-tx, -ty),
      ];
    }(),
    ShapeKind.blockArrow => () {
      final sh = h * p('shaft') / 2;
      final two = p('heads') >= 1.5;
      final head = w * p('head') * (two ? 0.5 : 1);
      return <Offset>[
        Offset(two ? -w / 2 + head : -w / 2, -sh),
        Offset(w / 2 - head, -sh),
        Offset(w / 2 - head, -h / 2),
        Offset(w / 2, 0),
        Offset(w / 2 - head, h / 2),
        Offset(w / 2 - head, sh),
        Offset(two ? -w / 2 + head : -w / 2, sh),
        if (two) ...[
          Offset(-w / 2 + head, h / 2),
          Offset(-w / 2, 0),
          Offset(-w / 2 + head, -h / 2),
        ],
      ];
    }(),
    ShapeKind.chevron => () {
      final t = w * p('thickness');
      return [
        Offset(-w / 2, -h / 2),
        Offset(-w / 2 + t, -h / 2),
        Offset(w / 2, 0),
        Offset(-w / 2 + t, h / 2),
        Offset(-w / 2, h / 2),
        Offset(w / 2 - t, 0),
      ];
    }(),
    ShapeKind.gear => _gearPoints(w, h, s.sides.clamp(4, 64), p('depth')),
    ShapeKind.ellipse ||
    ShapeKind.heart ||
    ShapeKind.line ||
    ShapeKind.crescent ||
    ShapeKind.speechBubble => null,
  };
}

/// Corners edited one by one only up to this many (a 64-point star
/// keeps one radius for all).
const maxIndividualCorners = 16;

/// Whether the corners share one radius (the default) or each has its
/// own (params `c0`, `c1`…).
bool cornersLinked(ShapeLayer s) => s.param('cornerLink', 1) >= 0.5;

/// Radius of corner [i] (layer pixels).
double cornerRadiusAt(ShapeLayer s, int i) =>
    cornersLinked(s) ? s.cornerRadius : s.param('c$i', s.cornerRadius);

/// [s] with every corner radius (the shared one and each corner's)
/// multiplied by [f] — for resizing.
ShapeLayer scaleCorners(ShapeLayer s, double f) => s.copyWith(
  cornerRadius: s.cornerRadius * f,
  params: {
    for (final e in s.params.entries)
      e.key: RegExp(r'^c\d+$').hasMatch(e.key) ? e.value * f : e.value,
  },
);

/// Builds the outline of a shape layer, centred on the origin.
Path buildShapePath(ShapeLayer s) {
  final w = s.width, h = s.height;
  final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
  double p(String k) => _p(s, k);

  // True circular corners, each with its own radius (Illustrator's live
  // corners) — for every shape that has corners.
  final corners = shapeCorners(s);
  if (corners != null &&
      s.shape != ShapeKind.rectangle &&
      s.shape != ShapeKind.frame) {
    final radii = [
      for (var i = 0; i < corners.length; i++) cornerRadiusAt(s, i),
    ];
    if (radii.any((x) => x > 0)) {
      final path = _arcCorners(corners, radii);
      if (s.shape == ShapeKind.gear && p('hole') > 0) {
        path
          ..fillType = PathFillType.evenOdd
          ..addOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: w * p('hole'),
              height: h * p('hole'),
            ),
          );
      }
      return path;
    }
  }

  RRect rrect(Rect box, double inset) {
    Radius at(int i) => Radius.circular(
      (cornerRadiusAt(s, i) - inset).clamp(0.0, math.min(w, h) / 2),
    );
    return RRect.fromRectAndCorners(
      box,
      topLeft: at(0),
      topRight: at(1),
      bottomRight: at(2),
      bottomLeft: at(3),
    );
  }

  switch (s.shape) {
    case ShapeKind.rectangle:
      return Path()..addRRect(rrect(r, 0));
    case ShapeKind.ellipse:
      return _ellipse(r, p('sweep'), p('start'), p('inner'));
    case ShapeKind.triangle:
      final ax = -w / 2 + w * p('apex');
      return Path()
        ..moveTo(ax, -h / 2)
        ..lineTo(w / 2, h / 2)
        ..lineTo(-w / 2, h / 2)
        ..close();
    case ShapeKind.star:
      return _rounded(
        _starPoints(w, h, s.sides.clamp(3, 64), p('inner')),
        p('round'),
      );
    case ShapeKind.polygon:
      return _rounded(_polygonPoints(w, h, s.sides.clamp(3, 64)), p('round'));
    case ShapeKind.diamond:
      return _rounded([
        Offset(0, -h / 2),
        Offset(w / 2, 0),
        Offset(0, h / 2),
        Offset(-w / 2, 0),
      ], p('round'));
    case ShapeKind.heart:
      return _heart(w, h);
    case ShapeKind.line:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)));
    case ShapeKind.parallelogram:
      final k = p('skew') * w / 2;
      return Path()..addPolygon([
        Offset(-w / 2 + k.clamp(0, w), -h / 2),
        Offset(w / 2 + math.min(0, k), -h / 2),
        Offset(w / 2 - k.clamp(0, w), h / 2),
        Offset(-w / 2 - math.min(0, k), h / 2),
      ], true);
    case ShapeKind.trapezoid:
      final t = p('top') * w / 2;
      return Path()..addPolygon([
        Offset(-t, -h / 2),
        Offset(t, -h / 2),
        Offset(w / 2, h / 2),
        Offset(-w / 2, h / 2),
      ], true);
    case ShapeKind.cross:
      final tx = w * p('thickness') / 2, ty = h * p('thickness') / 2;
      return Path()..addPolygon([
        Offset(-tx, -h / 2),
        Offset(tx, -h / 2),
        Offset(tx, -ty),
        Offset(w / 2, -ty),
        Offset(w / 2, ty),
        Offset(tx, ty),
        Offset(tx, h / 2),
        Offset(-tx, h / 2),
        Offset(-tx, ty),
        Offset(-w / 2, ty),
        Offset(-w / 2, -ty),
        Offset(-tx, -ty),
      ], true);
    case ShapeKind.crescent:
      final outer = Path()..addOval(r);
      final cut = Path()
        ..addOval(r.shift(Offset(w * p('offset'), -h * p('offset') * 0.25)));
      return Path.combine(PathOperation.difference, outer, cut);
    case ShapeKind.speechBubble:
      final bodyH = h * (1 - p('tail'));
      final body = Rect.fromLTWH(-w / 2, -h / 2, w, bodyH);
      final rad = math.min(w, bodyH) * p('round');
      final tx = -w / 2 + w * (0.1 + 0.8 * p('tailPos'));
      final tail = Path()
        ..moveTo(tx - w * 0.08, body.bottom - 1)
        ..lineTo(tx - w * 0.12, h / 2)
        ..lineTo(tx + w * 0.1, body.bottom - 1)
        ..close();
      return Path.combine(
        PathOperation.union,
        Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(rad))),
        tail,
      );
    case ShapeKind.blockArrow:
      final sh = h * p('shaft') / 2;
      final head = w * p('head') * (p('heads') >= 1.5 ? 0.5 : 1);
      final two = p('heads') >= 1.5;
      final pts = <Offset>[
        Offset(two ? -w / 2 + head : -w / 2, -sh),
        Offset(w / 2 - head, -sh),
        Offset(w / 2 - head, -h / 2),
        Offset(w / 2, 0),
        Offset(w / 2 - head, h / 2),
        Offset(w / 2 - head, sh),
        Offset(two ? -w / 2 + head : -w / 2, sh),
        if (two) ...[
          Offset(-w / 2 + head, h / 2),
          Offset(-w / 2, 0),
          Offset(-w / 2 + head, -h / 2),
        ],
      ];
      return Path()..addPolygon(pts, true);
    case ShapeKind.chevron:
      final t = w * p('thickness');
      return Path()..addPolygon([
        Offset(-w / 2, -h / 2),
        Offset(-w / 2 + t, -h / 2),
        Offset(w / 2, 0),
        Offset(-w / 2 + t, h / 2),
        Offset(-w / 2, h / 2),
        Offset(w / 2 - t, 0),
      ], true);
    case ShapeKind.gear:
      return _gear(w, h, s.sides.clamp(4, 64), p('depth'), p('hole'));
    case ShapeKind.frame:
      final t = math.min(w, h) * p('thickness');
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(rrect(r, 0))
        ..addRRect(rrect(r.deflate(t), t));
  }
}

/// A closed polygon whose corner `i` is a circular arc of `radii[i]`,
/// shrunk where the neighbouring edges are too short to hold it.
Path _arcCorners(List<Offset> pts, List<double> radii) {
  final n = pts.length;
  final path = Path();
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n], v = pts[i], next = pts[(i + 1) % n];
    final a = prev - v, b = next - v;
    final la = a.distance, lb = b.distance;
    var r = radii[i];
    Offset start = v, end = v;
    var arc = false;
    if (r > 0 && la > 1e-9 && lb > 1e-9) {
      final ua = a / la, ub = b / lb;
      final cos = (ua.dx * ub.dx + ua.dy * ub.dy).clamp(-1.0, 1.0);
      final theta = math.acos(cos); // the corner's inner angle
      if (theta > 1e-3 && theta < math.pi - 1e-3) {
        // Distance from the corner to where the arc meets each edge.
        var d = r / math.tan(theta / 2);
        final limit = math.min(la, lb) / 2;
        if (d > limit) {
          d = limit;
          r = d * math.tan(theta / 2);
        }
        start = v + ua * d;
        end = v + ub * d;
        arc = true;
      }
    }
    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    if (arc) {
      final cross = a.dx * b.dy - a.dy * b.dx;
      path.arcToPoint(end, radius: Radius.circular(r), clockwise: cross < 0);
    }
  }
  return path..close();
}

List<Offset> _gearPoints(double w, double h, int teeth, double depth) {
  final pts = <Offset>[];
  for (var i = 0; i < teeth; i++) {
    final a = i * 2 * math.pi / teeth;
    final step = 2 * math.pi / teeth;
    for (final (f, k) in [
      (0.0, 1 - depth),
      (0.15, 1.0),
      (0.45, 1.0),
      (0.6, 1 - depth),
    ]) {
      final ang = a + f * step - math.pi / 2;
      pts.add(Offset(math.cos(ang) * w / 2 * k, math.sin(ang) * h / 2 * k));
    }
  }
  return pts;
}

/// Full ellipse, pie slice, arc band or ring.
Path _ellipse(Rect r, double sweep, double start, double inner) {
  final full = sweep >= 359.9;
  if (full && inner <= 0) return Path()..addOval(r);
  final inR = Rect.fromCenter(
    center: r.center,
    width: r.width * inner,
    height: r.height * inner,
  );
  if (full) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(r)
      ..addOval(inR);
  }
  final a0 = (start - 90) * math.pi / 180;
  final sw = sweep * math.pi / 180;
  final p = Path()..arcTo(r, a0, sw, true);
  if (inner <= 0) {
    p.lineTo(0, 0);
  } else {
    p.arcTo(inR, a0 + sw, -sw, false);
  }
  return p..close();
}

List<Offset> _polygonPoints(double w, double h, int n) => [
  for (var i = 0; i < n; i++)
    Offset(
      math.cos(-math.pi / 2 + i * 2 * math.pi / n) * w / 2,
      math.sin(-math.pi / 2 + i * 2 * math.pi / n) * h / 2,
    ),
];

List<Offset> _starPoints(double w, double h, int points, double inner) => [
  for (var i = 0; i < points * 2; i++)
    Offset(
      math.cos(-math.pi / 2 + i * math.pi / points) *
          w /
          2 *
          (i.isEven ? 1 : inner),
      math.sin(-math.pi / 2 + i * math.pi / points) *
          h /
          2 *
          (i.isEven ? 1 : inner),
    ),
];

/// Closed polygon with corners rounded by [round] (0 = sharp, 1 = as
/// round as the edges allow).
Path _rounded(List<Offset> pts, double round) {
  final p = Path();
  if (round <= 0.001) return p..addPolygon(pts, true);
  final n = pts.length;
  final t = (round * 0.5).clamp(0.0, 0.5);
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n], v = pts[i], next = pts[(i + 1) % n];
    final a = Offset.lerp(v, prev, t)!, b = Offset.lerp(v, next, t)!;
    if (i == 0) {
      p.moveTo(a.dx, a.dy);
    } else {
      p.lineTo(a.dx, a.dy);
    }
    p.quadraticBezierTo(v.dx, v.dy, b.dx, b.dy);
  }
  return p..close();
}

Path _gear(double w, double h, int teeth, double depth, double hole) {
  final pts = <Offset>[];
  for (var i = 0; i < teeth; i++) {
    final a = i * 2 * math.pi / teeth;
    final step = 2 * math.pi / teeth;
    for (final (f, k) in [
      (0.0, 1 - depth),
      (0.15, 1.0),
      (0.45, 1.0),
      (0.6, 1 - depth),
    ]) {
      final ang = a + f * step - math.pi / 2;
      pts.add(Offset(math.cos(ang) * w / 2 * k, math.sin(ang) * h / 2 * k));
    }
  }
  final p = Path()
    ..fillType = PathFillType.evenOdd
    ..addPolygon(pts, true);
  if (hole > 0) {
    p.addOval(
      Rect.fromCenter(center: Offset.zero, width: w * hole, height: h * hole),
    );
  }
  return p;
}

Path _heart(double w, double h) {
  // Drawn in a unit box then scaled.
  final p = Path()
    ..moveTo(0.5, 0.95)
    ..cubicTo(0.1, 0.65, -0.05, 0.4, 0.1, 0.18)
    ..cubicTo(0.22, 0.0, 0.45, 0.02, 0.5, 0.22)
    ..cubicTo(0.55, 0.02, 0.78, 0.0, 0.9, 0.18)
    ..cubicTo(1.05, 0.4, 0.9, 0.65, 0.5, 0.95)
    ..close();
  final m = Float64List.fromList([
    w, 0, 0, 0, //
    0, h, 0, 0, //
    0, 0, 1, 0, //
    -w / 2, -h / 2, 0, 1, //
  ]);
  return p.transform(m);
}
