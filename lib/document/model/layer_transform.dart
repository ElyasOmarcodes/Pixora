import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

/// Placement of a layer inside the document.
///
/// Every layer is drawn centred on its local origin, then scaled, tilted in
/// 3D (optional), rotated and finally translated to ([x], [y]) in document
/// pixels. Flipping is a negative scale. This single representation covers
/// move / scale / rotate / flip / 3D rotate and is what hit-testing,
/// snapping and rendering all share.
@immutable
class LayerTransform {
  const LayerTransform({
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tiltX = 0,
    this.tiltY = 0,
  });

  /// Viewer distance (document px) for the 3D perspective.
  static const double perspective = 1600;

  final double x;
  final double y;

  /// Rotation in radians, clockwise.
  final double rotation;
  final double scaleX;
  final double scaleY;

  /// 3D rotation around the horizontal axis, degrees (−180..180).
  final double tiltX;

  /// 3D rotation around the vertical axis, degrees (−180..180).
  final double tiltY;

  Offset get position => Offset(x, y);

  bool get flippedX => scaleX < 0;
  bool get flippedY => scaleY < 0;
  bool get hasTilt => tiltX != 0 || tiltY != 0;

  LayerTransform copyWith({
    double? x,
    double? y,
    double? rotation,
    double? scaleX,
    double? scaleY,
    double? tiltX,
    double? tiltY,
  }) => LayerTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    scaleX: scaleX ?? this.scaleX,
    scaleY: scaleY ?? this.scaleY,
    tiltX: tiltX ?? this.tiltX,
    tiltY: tiltY ?? this.tiltY,
  );

  LayerTransform movedTo(Offset p) => copyWith(x: p.dx, y: p.dy);

  /// Uniformly scales, preserving any flip.
  LayerTransform scaledBy(double f) =>
      copyWith(scaleX: scaleX * f, scaleY: scaleY * f);

  /// 3×3 homography (row-major) local → document.
  List<double> get homography => homographyAt(0);

  /// The layer's 3D rotation as unit axes (x right, y down, z towards the
  /// viewer): where its local x, y and z (depth) axes point.
  (List<double>, List<double>, List<double>) get axes {
    final a = tiltX * math.pi / 180, b = tiltY * math.pi / 180;
    return (
      [math.cos(b), math.sin(a) * math.sin(b), -math.sin(b) * math.cos(a)],
      [0.0, math.cos(a), math.sin(a)],
      [math.sin(b), -math.cos(b) * math.sin(a), math.cos(b) * math.cos(a)],
    );
  }

  /// Homography of the plane [z] document px in front of (negative:
  /// behind) the layer, in the layer's 3D rotation and perspective — the
  /// slices a real 3D extrusion is made of.
  List<double> homographyAt(double z) {
    final c = math.cos(rotation), s = math.sin(rotation);
    final (ax, ay, az) = axes;
    const d = perspective;
    // P · S, plus the depth offset along the rotated z axis.
    final m00 = ax[0] * scaleX, m01 = 0.0, m02 = az[0] * z;
    final m10 = ax[1] * scaleX, m11 = ay[1] * scaleY, m12 = az[1] * z;
    final m20 = -ax[2] / d * scaleX, m21 = -ay[2] / d * scaleY;
    final m22 = 1 - az[2] * z / d;
    // T · R · (P·S)
    return [
      c * m00 - s * m10 + x * m20,
      c * m01 - s * m11 + x * m21,
      c * m02 - s * m12 + x * m22,
      s * m00 + c * m10 + y * m20,
      s * m01 + c * m11 + y * m21,
      s * m02 + c * m12 + y * m22,
      m20,
      m21,
      m22,
    ];
  }

  /// Maps a point in layer-local space into document space.
  Offset toDocument(Offset local) {
    if (!hasTilt) {
      final sx = local.dx * scaleX, sy = local.dy * scaleY;
      final c = math.cos(rotation), s = math.sin(rotation);
      return Offset(x + sx * c - sy * s, y + sx * s + sy * c);
    }
    final h = homography;
    final u = local.dx, v = local.dy;
    final w = h[6] * u + h[7] * v + h[8];
    final ww = w.abs() < 1e-9 ? 1e-9 : w;
    return Offset(
      (h[0] * u + h[1] * v + h[2]) / ww,
      (h[3] * u + h[4] * v + h[5]) / ww,
    );
  }

  /// Maps a document-space point into layer-local space.
  Offset toLocal(Offset doc) {
    if (!hasTilt) {
      final dx = doc.dx - x, dy = doc.dy - y;
      final c = math.cos(-rotation), s = math.sin(-rotation);
      final rx = dx * c - dy * s, ry = dx * s + dy * c;
      return Offset(
        scaleX == 0 ? 0 : rx / scaleX,
        scaleY == 0 ? 0 : ry / scaleY,
      );
    }
    final h = homography;
    // Inverse via the adjugate.
    final a = h[0], b = h[1], c = h[2];
    final d = h[3], e = h[4], f = h[5];
    final g = h[6], hh = h[7], i = h[8];
    final i00 = e * i - f * hh, i01 = c * hh - b * i, i02 = b * f - c * e;
    final i10 = f * g - d * i, i11 = a * i - c * g, i12 = c * d - a * f;
    final i20 = d * hh - e * g, i21 = b * g - a * hh, i22 = a * e - b * d;
    final px = doc.dx, py = doc.dy;
    final w = i20 * px + i21 * py + i22;
    final ww = w.abs() < 1e-12 ? 1e-12 : w;
    return Offset(
      (i00 * px + i01 * py + i02) / ww,
      (i10 * px + i11 * py + i12) / ww,
    );
  }

  /// Applies this transform to a canvas so local drawing lands correctly.
  void applyTo(Canvas canvas) {
    if (!hasTilt) {
      canvas
        ..translate(x, y)
        ..rotate(rotation)
        ..scale(scaleX, scaleY);
      return;
    }
    final h = homography;
    // 4×4 column-major, z passes through.
    canvas.transform(
      Float64List.fromList([
        h[0], h[3], 0, h[6], //
        h[1], h[4], 0, h[7], //
        0, 0, 1, 0, //
        h[2], h[5], 0, h[8], //
      ]),
    );
  }

  Json toJson() => {
    'x': x,
    'y': y,
    if (rotation != 0) 'rotation': rotation,
    if (scaleX != 1) 'scaleX': scaleX,
    if (scaleY != 1) 'scaleY': scaleY,
    if (tiltX != 0) 'tiltX': tiltX,
    if (tiltY != 0) 'tiltY': tiltY,
  };

  static LayerTransform fromJson(Object? json) {
    final m = readMap(json);
    return LayerTransform(
      x: readDouble(m['x']),
      y: readDouble(m['y']),
      rotation: readDouble(m['rotation']),
      scaleX: readDouble(m['scaleX'], 1),
      scaleY: readDouble(m['scaleY'], 1),
      tiltX: readDouble(m['tiltX']).clamp(-180.0, 180.0),
      tiltY: readDouble(m['tiltY']).clamp(-180.0, 180.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayerTransform &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.tiltX == tiltX &&
      other.tiltY == tiltY;

  @override
  int get hashCode => Object.hash(x, y, rotation, scaleX, scaleY, tiltX, tiltY);
}
