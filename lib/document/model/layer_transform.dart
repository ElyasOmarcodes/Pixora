import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

/// Placement of a layer inside the document.
///
/// Every layer is drawn centred on its local origin, then scaled, rotated and
/// finally translated to ([x], [y]) in document pixels. Flipping is a negative
/// scale. This single representation covers move / scale / rotate / flip and
/// is what hit-testing, snapping and rendering all share.
@immutable
class LayerTransform {
  const LayerTransform({
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.scaleX = 1,
    this.scaleY = 1,
  });

  final double x;
  final double y;

  /// Rotation in radians, clockwise.
  final double rotation;
  final double scaleX;
  final double scaleY;

  Offset get position => Offset(x, y);

  bool get flippedX => scaleX < 0;
  bool get flippedY => scaleY < 0;

  LayerTransform copyWith({
    double? x,
    double? y,
    double? rotation,
    double? scaleX,
    double? scaleY,
  }) => LayerTransform(
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    scaleX: scaleX ?? this.scaleX,
    scaleY: scaleY ?? this.scaleY,
  );

  LayerTransform movedTo(Offset p) => copyWith(x: p.dx, y: p.dy);

  /// Uniformly scales, preserving any flip.
  LayerTransform scaledBy(double f) =>
      copyWith(scaleX: scaleX * f, scaleY: scaleY * f);

  /// Maps a point in layer-local space into document space.
  Offset toDocument(Offset local) {
    final sx = local.dx * scaleX, sy = local.dy * scaleY;
    final c = math.cos(rotation), s = math.sin(rotation);
    return Offset(x + sx * c - sy * s, y + sx * s + sy * c);
  }

  /// Maps a document-space point into layer-local space.
  Offset toLocal(Offset doc) {
    final dx = doc.dx - x, dy = doc.dy - y;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    final rx = dx * c - dy * s, ry = dx * s + dy * c;
    return Offset(scaleX == 0 ? 0 : rx / scaleX, scaleY == 0 ? 0 : ry / scaleY);
  }

  /// Applies this transform to a canvas so local drawing lands correctly.
  void applyTo(Canvas canvas) {
    canvas
      ..translate(x, y)
      ..rotate(rotation)
      ..scale(scaleX, scaleY);
  }

  Json toJson() => {
    'x': x,
    'y': y,
    if (rotation != 0) 'rotation': rotation,
    if (scaleX != 1) 'scaleX': scaleX,
    if (scaleY != 1) 'scaleY': scaleY,
  };

  static LayerTransform fromJson(Object? json) {
    final m = readMap(json);
    return LayerTransform(
      x: readDouble(m['x']),
      y: readDouble(m['y']),
      rotation: readDouble(m['rotation']),
      scaleX: readDouble(m['scaleX'], 1),
      scaleY: readDouble(m['scaleY'], 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LayerTransform &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY;

  @override
  int get hashCode => Object.hash(x, y, rotation, scaleX, scaleY);
}
