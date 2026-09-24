import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';
import 'layer.dart' show PathContour;

/// What a mask stroke does: hide the layer where it paints, or reveal it
/// again (Photoshop's black / white brush on a layer mask).
enum MaskMode { hide, show }

/// How the stroke's points are drawn.
enum MaskShape {
  /// Freehand brush along the points.
  brush,

  /// A closed, filled area through the points (lasso / pen polygon).
  area,

  /// The whole mask (Hide all / Reveal all / fill with a grey).
  fill,

  /// Linear gradient from `points[0]` (at [MaskStroke.value]) to
  /// `points[1]` (at the opposite value).
  linear,

  /// Radial gradient: centre `points[0]`, edge at `points[1]`.
  radial,
}

/// One brush or pen stroke on a layer mask, in the layer's local space so
/// it follows every move, scale and rotation. Vector strokes keep masks
/// sharp at any zoom and make them part of normal undo/redo.
@immutable
class MaskStroke {
  MaskStroke({
    required this.mode,
    required List<Offset> points,
    this.shape = MaskShape.brush,
    this.width = 40,
    this.softness = 0,
    this.contour,
    this.level,
    this.opacity = 1,
  }) : points = List.unmodifiable(points);

  /// Grey painted into the mask, Photoshop style: 0 = black (hide),
  /// 1 = white (reveal), in between = partly visible. Null = from [mode].
  final double? level;

  /// Brush opacity/flow 0..1: how much of [value] replaces the mask.
  final double opacity;

  /// The effective grey (0 black … 1 white).
  double get value => level ?? (mode == MaskMode.hide ? 0 : 1);

  /// The same stroke painting the opposite grey (for invert).
  MaskStroke inverted() => MaskStroke(
    mode: mode == MaskMode.hide ? MaskMode.show : MaskMode.hide,
    shape: shape,
    points: points,
    width: width,
    softness: softness,
    contour: contour,
    level: level == null ? null : 1 - level!,
    opacity: opacity,
  );

  /// Bezier outline drawn with the pen (area strokes); overrides [points].
  final PathContour? contour;

  final MaskMode mode;
  final MaskShape shape;
  final List<Offset> points;

  /// Brush diameter in layer pixels.
  final double width;

  /// Edge feather 0..1.
  final double softness;

  MaskStroke copyWith({List<Offset>? points}) => MaskStroke(
    mode: mode,
    shape: shape,
    points: points ?? this.points,
    width: width,
    softness: softness,
    contour: contour,
    level: level,
    opacity: opacity,
  );

  Json toJson() => {
    'mode': mode.name,
    if (shape != MaskShape.brush) 'shape': shape.name,
    'width': width,
    if (softness > 0) 'soft': softness,
    // Compact "x,y;x,y" keeps project files small.
    'pts': [for (final p in points) '${_n(p.dx)},${_n(p.dy)}'].join(';'),
    if (contour != null) 'path': contour!.toJson(),
    if (level != null) 'lv': level,
    if (opacity != 1) 'op': opacity,
  };

  static String _n(double v) => (v * 10).round() / 10 == v.roundToDouble()
      ? v.round().toString()
      : ((v * 10).round() / 10).toString();

  static MaskStroke fromJson(Json m) {
    final pts = <Offset>[];
    for (final pair in readString(m['pts']).split(';')) {
      final xy = pair.split(',');
      if (xy.length != 2) continue;
      final x = double.tryParse(xy[0]), y = double.tryParse(xy[1]);
      if (x != null && y != null) pts.add(Offset(x, y));
    }
    return MaskStroke(
      mode: readEnum(MaskMode.values, m['mode'], MaskMode.hide),
      shape: readEnum(MaskShape.values, m['shape'], MaskShape.brush),
      width: readDouble(m['width'], 40).clamp(0.5, 5000).toDouble(),
      softness: readDouble(m['soft']).clamp(0.0, 1.0),
      points: pts,
      contour: m['path'] is Map
          ? PathContour.fromJson(readMap(m['path']))
          : null,
      level: m['lv'] == null ? null : readDouble(m['lv']).clamp(0.0, 1.0),
      opacity: readDouble(m['op'], 1).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MaskStroke &&
      other.mode == mode &&
      other.shape == shape &&
      other.width == width &&
      other.softness == softness &&
      other.contour == contour &&
      other.level == level &&
      other.opacity == opacity &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(
    mode,
    shape,
    width,
    softness,
    contour,
    level,
    opacity,
    Object.hashAll(points),
  );
}
