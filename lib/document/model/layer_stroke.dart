import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';
import 'blend.dart';
import 'fill.dart';

/// Where a stroke sits relative to the layer's edge (Photoshop's Position).
enum StrokePosition { outside, center, inside }

/// Photoshop's Stroke layer style: a band of [size] pixels around the
/// layer's shape, filled with a colour, gradient or pattern, composited
/// with its own [opacity] and [blend] mode. It follows the layer's pixels
/// (text, shapes, icons…) and is not faded by Fill opacity.
@immutable
class LayerStroke {
  const LayerStroke({
    required this.size,
    required this.fill,
    this.position = StrokePosition.outside,
    this.opacity = 1,
    this.blend = PixBlendMode.normal,
    this.enabled = true,
  });

  /// Width of the band in layer pixels.
  final double size;
  final StrokePosition position;
  final PixFill fill;
  final double opacity;
  final PixBlendMode blend;

  /// Switched off from the layer's effects list (kept, not drawn).
  final bool enabled;

  bool get visible => enabled && size > 0 && opacity > 0;

  /// How far it reaches outside the shape.
  double get outside => switch (position) {
    StrokePosition.outside => size,
    StrokePosition.center => size / 2,
    StrokePosition.inside => 0,
  };

  /// How far it reaches into the shape.
  double get inside => switch (position) {
    StrokePosition.outside => 0,
    StrokePosition.center => size / 2,
    StrokePosition.inside => size,
  };

  LayerStroke copyWith({
    double? size,
    StrokePosition? position,
    PixFill? fill,
    double? opacity,
    PixBlendMode? blend,
    bool? enabled,
  }) => LayerStroke(
    size: size ?? this.size,
    position: position ?? this.position,
    fill: fill ?? this.fill,
    opacity: opacity ?? this.opacity,
    blend: blend ?? this.blend,
    enabled: enabled ?? this.enabled,
  );

  Json toJson() => {
    'size': size,
    if (position != StrokePosition.outside) 'pos': position.name,
    'fill': fill.toJson(),
    if (opacity != 1) 'opacity': opacity,
    if (blend != PixBlendMode.normal) 'blend': blend.name,
    if (!enabled) 'off': true,
  };

  static LayerStroke fromJson(Json m) => LayerStroke(
    size: readDouble(m['size'], 3).clamp(0.0, 1000.0),
    position: readEnum(StrokePosition.values, m['pos'], StrokePosition.outside),
    fill: PixFill.fromJson(m['fill'], PixFill.color(const Color(0xFF000000))),
    opacity: readDouble(m['opacity'], 1).clamp(0.0, 1.0),
    blend: readEnum(PixBlendMode.values, m['blend'], PixBlendMode.normal),
    enabled: !readBool(m['off']),
  );

  @override
  bool operator ==(Object other) =>
      other is LayerStroke &&
      other.size == size &&
      other.position == position &&
      other.fill == fill &&
      other.opacity == opacity &&
      other.blend == blend &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(size, position, fill, opacity, blend, enabled);
}
