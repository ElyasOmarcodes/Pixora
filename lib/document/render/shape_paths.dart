import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../model/layer.dart';

/// Builds the outline of a shape layer, centred on the origin.
Path buildShapePath(ShapeLayer s) {
  final w = s.width, h = s.height;
  final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
  switch (s.shape) {
    case ShapeKind.rectangle:
      final radius = s.cornerRadius.clamp(0.0, math.min(w, h) / 2);
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    case ShapeKind.ellipse:
      return Path()..addOval(r);
    case ShapeKind.triangle:
      return Path()
        ..moveTo(0, -h / 2)
        ..lineTo(w / 2, h / 2)
        ..lineTo(-w / 2, h / 2)
        ..close();
    case ShapeKind.star:
      return _star(w, h, s.sides.clamp(3, 64), 0.45);
    case ShapeKind.polygon:
      return _polygon(w, h, s.sides.clamp(3, 64));
    case ShapeKind.heart:
      return _heart(w, h);
    case ShapeKind.line:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)));
  }
}

Path _polygon(double w, double h, int n) {
  final p = Path();
  for (var i = 0; i < n; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / n;
    final pt = Offset(math.cos(a) * w / 2, math.sin(a) * h / 2);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

Path _star(double w, double h, int points, double inner) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final a = -math.pi / 2 + i * math.pi / points;
    final k = i.isEven ? 1.0 : inner;
    final pt = Offset(math.cos(a) * w / 2 * k, math.sin(a) * h / 2 * k);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
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
