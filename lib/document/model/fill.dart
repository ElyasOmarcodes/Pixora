import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

/// Gradient styles, like Photoshop's: linear, radial, angle (sweep around
/// a centre) and reflected (linear, mirrored around its centre).
enum FillKind { solid, linear, radial, sweep, reflected }

/// A paint source: a solid color or a gradient.
///
/// Fills are used by the document background, shapes and text. Gradients are
/// resolved against the bounds of whatever they paint, so they scale with the
/// layer: [center] is an offset from the middle in half-sizes (−1…1), and
/// [scale] stretches the gradient (1 = fits the box).
@immutable
class PixFill {
  const PixFill._(
    this.kind,
    this.colors,
    this.stops,
    this.angle, {
    this.scale = 1,
    this.center = Offset.zero,
  });

  factory PixFill.color(Color color) =>
      PixFill._(FillKind.solid, [color], null, 0);

  factory PixFill.linear(
    List<Color> colors, {
    double angle = 135,
    List<double>? stops,
  }) => PixFill._(
    FillKind.linear,
    List.unmodifiable(colors),
    stops == null ? null : List.unmodifiable(stops),
    angle,
  );

  factory PixFill.radial(List<Color> colors, {List<double>? stops}) =>
      PixFill._(
        FillKind.radial,
        List.unmodifiable(colors),
        stops == null ? null : List.unmodifiable(stops),
        0,
      );

  /// Any gradient style with full control.
  factory PixFill.gradient(
    FillKind kind,
    List<Color> colors, {
    List<double>? stops,
    double angle = 90,
    double scale = 1,
    Offset center = Offset.zero,
  }) => PixFill._(
    kind,
    List.unmodifiable(colors),
    stops == null ? null : List.unmodifiable(stops),
    angle,
    scale: scale,
    center: center,
  );

  final FillKind kind;
  final List<Color> colors;
  final List<double>? stops;

  /// Gradient direction in degrees (0 = left→right, 90 = top→bottom).
  final double angle;

  /// Stretch of the gradient (1 = fits the painted box).
  final double scale;

  /// Offset of the gradient centre from the box centre, in half-sizes.
  final Offset center;

  static final PixFill white = PixFill.color(const Color(0xFFFFFFFF));

  Color get primary => colors.isEmpty ? const Color(0xFFFFFFFF) : colors.first;

  bool get isGradient => kind != FillKind.solid && colors.length > 1;

  /// Stop positions, evenly spread when none are stored.
  List<double> get effectiveStops =>
      stops ??
      [
        for (var i = 0; i < colors.length; i++)
          colors.length == 1 ? 0 : i / (colors.length - 1),
      ];

  PixFill withPrimary(Color c) {
    if (!isGradient) return PixFill.color(c);
    final next = [...colors]..[0] = c;
    return copyWith(colors: next);
  }

  PixFill copyWith({
    FillKind? kind,
    List<Color>? colors,
    List<double>? stops,
    bool clearStops = false,
    double? angle,
    double? scale,
    Offset? center,
  }) => PixFill._(
    kind ?? this.kind,
    List.unmodifiable(colors ?? this.colors),
    clearStops
        ? null
        : (stops == null ? this.stops : List<double>.unmodifiable(stops)),
    angle ?? this.angle,
    scale: scale ?? this.scale,
    center: center ?? this.center,
  );

  /// The same gradient with its colours in the opposite order.
  PixFill reversed() {
    if (!isGradient) return this;
    final s = effectiveStops;
    return copyWith(
      colors: colors.reversed.toList(),
      stops: [for (final p in s.reversed) 1 - p],
    );
  }

  /// Where the gradient's centre lands inside [bounds].
  Offset centerIn(Rect bounds) =>
      bounds.center +
      Offset(center.dx * bounds.width / 2, center.dy * bounds.height / 2);

  /// Half the length of a linear gradient across [bounds].
  double linearHalf(Rect bounds) {
    final rad = angle * math.pi / 180;
    final dx = math.cos(rad), dy = math.sin(rad);
    return (bounds.width * dx.abs() + bounds.height * dy.abs()) / 2 * scale;
  }

  /// Radius of a radial gradient across [bounds].
  double radialRadius(Rect bounds) =>
      (bounds.shortestSide / 2 + bounds.longestSide / 4) * scale;

  /// Applies this fill to [paint] for content occupying [bounds].
  Paint applyTo(Paint paint, Rect bounds) {
    if (!isGradient) {
      paint
        ..shader = null
        ..color = primary;
      return paint;
    }
    paint.color = const Color(0xFFFFFFFF);
    final c = centerIn(bounds);
    final rad = angle * math.pi / 180;
    final d = Offset(math.cos(rad), math.sin(rad));
    final s = stops;
    switch (kind) {
      case FillKind.linear:
        final half = math.max(0.5, linearHalf(bounds));
        paint.shader = Gradient.linear(c - d * half, c + d * half, colors, s);
      case FillKind.reflected:
        final half = math.max(0.5, linearHalf(bounds));
        paint.shader = Gradient.linear(
          c,
          c + d * half,
          colors,
          s,
          TileMode.mirror,
        );
      case FillKind.radial:
        paint.shader = Gradient.radial(
          c,
          math.max(0.5, radialRadius(bounds)),
          colors,
          s,
        );
      case FillKind.sweep:
        paint.shader = Gradient.sweep(
          c,
          colors,
          s,
          TileMode.clamp,
          rad,
          rad + math.pi * 2,
        );
      case FillKind.solid:
        paint.shader = null;
    }
    return paint;
  }

  Json toJson() => {
    'kind': kind.name,
    'colors': [for (final c in _effectiveColors) writeColor(c)],
    if (stops != null) 'stops': stops,
    if (kind != FillKind.solid && kind != FillKind.radial) 'angle': angle,
    if (scale != 1) 'scale': scale,
    if (center != Offset.zero) 'cx': center.dx,
    if (center != Offset.zero) 'cy': center.dy,
  };

  List<Color> get _effectiveColors => colors.isEmpty ? [primary] : colors;

  static PixFill fromJson(Object? json, [PixFill? fallback]) {
    fallback ??= white;
    if (json is int || json is String) return PixFill.color(readColor(json));
    if (json is! Map) return fallback;
    final m = readMap(json);
    final colors = [for (final c in readList(m['colors'])) readColor(c)];
    if (colors.isEmpty) return fallback;
    final stopsRaw = readList(m['stops']);
    final stops = stopsRaw.length == colors.length
        ? [for (final s in stopsRaw) readDouble(s)]
        : null;
    final kind = readEnum(FillKind.values, m['kind'], FillKind.solid);
    if (kind == FillKind.solid || colors.length < 2) {
      return PixFill.color(colors.first);
    }
    return PixFill.gradient(
      kind,
      colors,
      stops: stops,
      angle: readDouble(m['angle'], kind == FillKind.linear ? 135 : 0),
      scale: readDouble(m['scale'], 1).clamp(0.05, 20.0),
      center: Offset(readDouble(m['cx']), readDouble(m['cy'])),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PixFill &&
      other.kind == kind &&
      other.angle == angle &&
      other.scale == scale &&
      other.center == center &&
      listEquals(other._effectiveColors, _effectiveColors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    kind,
    angle,
    scale,
    center,
    Object.hashAll(_effectiveColors),
    stops == null ? null : Object.hashAll(stops!),
  );
}
