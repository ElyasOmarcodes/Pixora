import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';

enum FillKind { solid, linear, radial }

/// A paint source: a solid color or a gradient.
///
/// Fills are used by the document background, shapes and text. Gradients are
/// resolved against the bounds of whatever they paint, so they scale with the
/// layer.
@immutable
class PixFill {
  const PixFill._(this.kind, this.colors, this.stops, this.angle);

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

  final FillKind kind;
  final List<Color> colors;
  final List<double>? stops;

  /// Gradient direction in degrees (0 = left→right, 90 = top→bottom).
  final double angle;

  static final PixFill white = PixFill.color(const Color(0xFFFFFFFF));

  Color get primary => colors.isEmpty ? const Color(0xFFFFFFFF) : colors.first;

  bool get isGradient => kind != FillKind.solid && colors.length > 1;

  PixFill withPrimary(Color c) {
    if (!isGradient) return PixFill.color(c);
    final next = [...colors]..[0] = c;
    return PixFill._(kind, List.unmodifiable(next), stops, angle);
  }

  PixFill copyWith({FillKind? kind, List<Color>? colors, double? angle}) =>
      PixFill._(
        kind ?? this.kind,
        List.unmodifiable(colors ?? this.colors),
        stops,
        angle ?? this.angle,
      );

  /// Applies this fill to [paint] for content occupying [bounds].
  Paint applyTo(Paint paint, Rect bounds) {
    if (!isGradient) {
      paint
        ..shader = null
        ..color = primary;
      return paint;
    }
    paint.color = const Color(0xFFFFFFFF);
    if (kind == FillKind.linear) {
      final rad = angle * math.pi / 180;
      final dx = math.cos(rad), dy = math.sin(rad);
      final half = (bounds.width * dx.abs() + bounds.height * dy.abs()) / 2;
      final c = bounds.center;
      paint.shader = Gradient.linear(
        c - Offset(dx, dy) * half,
        c + Offset(dx, dy) * half,
        colors,
        stops,
      );
    } else {
      paint.shader = Gradient.radial(
        bounds.center,
        bounds.shortestSide / 2 + bounds.longestSide / 4,
        colors,
        stops,
      );
    }
    return paint;
  }

  Json toJson() => {
    'kind': kind.name,
    'colors': [for (final c in _effectiveColors) writeColor(c)],
    if (stops != null) 'stops': stops,
    if (kind == FillKind.linear) 'angle': angle,
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
    return switch (readEnum(FillKind.values, m['kind'], FillKind.solid)) {
      FillKind.solid => PixFill.color(colors.first),
      FillKind.linear =>
        colors.length < 2
            ? PixFill.color(colors.first)
            : PixFill.linear(
                colors,
                angle: readDouble(m['angle'], 135),
                stops: stops,
              ),
      FillKind.radial =>
        colors.length < 2
            ? PixFill.color(colors.first)
            : PixFill.radial(colors, stops: stops),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PixFill &&
      other.kind == kind &&
      other.angle == angle &&
      listEquals(other._effectiveColors, _effectiveColors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode =>
      Object.hash(kind, angle, Object.hashAll(_effectiveColors));
}
