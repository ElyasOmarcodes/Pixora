import 'dart:math' as math;
import 'dart:ui';

import 'effect.dart';

/// How a warp is edited (the geometry is the same for all three).
enum WarpMode {
  /// Photoshop's Distort: drag each corner anywhere.
  distort,

  /// Photoshop's Perspective: corners move in mirrored pairs.
  perspective,

  /// Photoshop's Warp: a 4 × 4 Bézier mesh over the layer.
  warp,
}

/// Photoshop's Edit ▸ Transform ▸ Distort / Perspective / Warp for a
/// layer, stored in a `warp` effect: the layer's box (the unit square)
/// is bent by a bicubic Bézier mesh, then mapped onto a free quad.
///
/// Params hold offsets from the untouched shape, in fractions of the
/// layer's width and height: `q0x`…`q3y` for the corners (top-left
/// clockwise) and `m00x`…`m33y` for the mesh points (row, column).
class WarpGeometry {
  WarpGeometry(this.corners, this.mesh);

  factory WarpGeometry.of(LayerEffect e) => WarpGeometry(
    [
      for (var k = 0; k < 4; k++)
        baseCorners[k] + Offset(e.number('q${k}x', 0), e.number('q${k}y', 0)),
    ],
    [
      for (var i = 0; i < 4; i++)
        for (var j = 0; j < 4; j++)
          Offset(j / 3, i / 3) +
              Offset(e.number('m$i${j}x', 0), e.number('m$i${j}y', 0)),
    ],
  );

  static const baseCorners = [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ];

  /// Corners of the quad the (bent) box lands on, unit coordinates.
  final List<Offset> corners;

  /// Bézier control points, row-major, unit coordinates.
  final List<Offset> mesh;

  /// Every param key of a warp effect.
  static List<String> get keys => [
    for (var k = 0; k < 4; k++) ...['q${k}x', 'q${k}y'],
    for (var i = 0; i < 4; i++)
      for (var j = 0; j < 4; j++) ...['m$i${j}x', 'm$i${j}y'],
  ];

  /// The params that store this geometry.
  Map<String, double> toParams() => {
    for (var k = 0; k < 4; k++) ...{
      'q${k}x': corners[k].dx - baseCorners[k].dx,
      'q${k}y': corners[k].dy - baseCorners[k].dy,
    },
    for (var i = 0; i < 4; i++)
      for (var j = 0; j < 4; j++) ...{
        'm$i${j}x': mesh[i * 4 + j].dx - j / 3,
        'm$i${j}y': mesh[i * 4 + j].dy - i / 3,
      },
  };

  bool get isIdentity {
    for (var k = 0; k < 4; k++) {
      if ((corners[k] - baseCorners[k]).distance > 1e-6) return false;
    }
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        if ((mesh[i * 4 + j] - Offset(j / 3, i / 3)).distance > 1e-6) {
          return false;
        }
      }
    }
    return true;
  }

  bool get hasMesh {
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        if ((mesh[i * 4 + j] - Offset(j / 3, i / 3)).distance > 1e-6) {
          return true;
        }
      }
    }
    return false;
  }

  static double _b(int i, double t) => switch (i) {
    0 => (1 - t) * (1 - t) * (1 - t),
    1 => 3 * t * (1 - t) * (1 - t),
    2 => 3 * t * t * (1 - t),
    _ => t * t * t,
  };

  /// The mesh alone: where unit point ([u], [v]) goes.
  Offset bend(double u, double v) {
    var x = 0.0, y = 0.0;
    for (var i = 0; i < 4; i++) {
      final bv = _b(i, v);
      for (var j = 0; j < 4; j++) {
        final w = bv * _b(j, u);
        final p = mesh[i * 4 + j];
        x += p.dx * w;
        y += p.dy * w;
      }
    }
    return Offset(x, y);
  }

  /// Projective map of the unit square onto [corners].
  late final List<double> _h = _squareToQuad(corners);

  Offset project(Offset p) {
    final h = _h;
    final w = h[6] * p.dx + h[7] * p.dy + 1;
    final ww = w.abs() < 1e-9 ? 1e-9 : w;
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / ww,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / ww,
    );
  }

  /// The inverse of [project]: which point of the bent square lands on
  /// [p] (for dragging mesh points after a distort).
  Offset unproject(Offset p) {
    final h = _h;
    // Inverse of [[a b c][d e f][g h 1]].
    final a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5];
    final g = h[6], k = h[7];
    final i00 = e - f * k, i01 = c * k - b, i02 = b * f - c * e;
    final i10 = f * g - d, i11 = a - c * g, i12 = c * d - a * f;
    final i20 = d * k - e * g, i21 = b * g - a * k, i22 = a * e - b * d;
    final w = i20 * p.dx + i21 * p.dy + i22;
    final ww = w.abs() < 1e-12 ? 1e-12 : w;
    return Offset(
      (i00 * p.dx + i01 * p.dy + i02) / ww,
      (i10 * p.dx + i11 * p.dy + i12) / ww,
    );
  }

  /// Where unit point ([u], [v]) of the layer's box ends up.
  Offset map(double u, double v) => project(bend(u, v));

  /// The warped outline's reach outside the box, in unit coordinates.
  double get reach {
    var r = 0.0;
    for (var s = 0; s <= 16; s++) {
      final t = s / 16;
      for (final p in [map(t, 0), map(t, 1), map(0, t), map(1, t)]) {
        r = math.max(r, math.max(-p.dx, p.dx - 1));
        r = math.max(r, math.max(-p.dy, p.dy - 1));
      }
    }
    return r;
  }

  /// Heckbert's square → quad homography (row-major, h8 = 1).
  static List<double> _squareToQuad(List<Offset> q) {
    final x0 = q[0].dx, y0 = q[0].dy, x1 = q[1].dx, y1 = q[1].dy;
    final x2 = q[2].dx, y2 = q[2].dy, x3 = q[3].dx, y3 = q[3].dy;
    final sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3;
    if (sx.abs() < 1e-12 && sy.abs() < 1e-12) {
      // Affine.
      return [x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0];
    }
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final den = dx1 * dy2 - dx2 * dy1;
    final d = den.abs() < 1e-12 ? 1e-12 : den;
    final g = (sx * dy2 - dx2 * sy) / d;
    final h = (dx1 * sy - sx * dy1) / d;
    return [
      x1 - x0 + g * x1,
      x3 - x0 + h * x3,
      x0,
      y1 - y0 + g * y1,
      y3 - y0 + h * y3,
      y0,
      g,
      h,
    ];
  }
}
