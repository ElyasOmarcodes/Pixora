import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';
import 'patterns.dart';

/// Gradient styles, like Photoshop's: linear, radial, angle (sweep around
/// a centre) and reflected (linear, mirrored around its centre); and
/// [pattern], a repeating tile (see [Patterns]).
enum FillKind { solid, linear, radial, sweep, reflected, pattern }

/// A paint source: a solid color, a gradient or a pattern.
///
/// Patterns use [pattern] (a built-in id or an image asset), [colors]
/// (foreground, background — built-ins only), [angle] (rotation),
/// [scale], [center] (offset in tiles) and [mirror] (seamless 2×2 tile).
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
    this.pattern,
    this.mirror = false,
    this.detail = 1,
    this.tint = false,
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

  /// A repeating pattern: [id] from [Patterns.builtins] (drawn in [fg] on
  /// [bg]) or [Patterns.forAsset] for an image pattern.
  factory PixFill.pattern(
    String id, {
    Color fg = const Color(0xFF000000),
    Color bg = const Color(0x00000000),
    double angle = 0,
    double scale = 1,
    Offset center = Offset.zero,
    bool mirror = false,
    double detail = 1,
    bool tint = false,
  }) => PixFill._(
    FillKind.pattern,
    List.unmodifiable([fg, bg]),
    null,
    angle,
    scale: scale,
    center: center,
    pattern: id,
    mirror: mirror,
    detail: detail,
    tint: tint,
  );

  final FillKind kind;
  final List<Color> colors;

  /// Pattern id (see [Patterns]); pattern fills only.
  final String? pattern;

  /// Mirror the pattern tile 2×2 so any image repeats without seams.
  final bool mirror;

  /// Size of a built-in pattern's elements (dots, lines, shapes…) within
  /// its tile; 1 = the standard look.
  final double detail;

  /// Image patterns drawn in the fill's colours (their shape as a stencil).
  final bool tint;
  final List<double>? stops;

  /// Gradient direction in degrees (0 = left→right, 90 = top→bottom).
  final double angle;

  /// Stretch of the gradient (1 = fits the painted box).
  final double scale;

  /// Offset of the gradient centre from the box centre, in half-sizes.
  final Offset center;

  static final PixFill white = PixFill.color(const Color(0xFFFFFFFF));

  Color get primary => colors.isEmpty ? const Color(0xFFFFFFFF) : colors.first;

  bool get isGradient =>
      kind != FillKind.solid && kind != FillKind.pattern && colors.length > 1;

  bool get isPattern => kind == FillKind.pattern && pattern != null;

  /// Painted with a shader (gradient or pattern) rather than a flat color.
  bool get hasShader => isGradient || isPattern;

  /// Project asset behind an image pattern, if any.
  String? get assetId => isPattern && Patterns.isAsset(pattern!)
      ? Patterns.assetId(pattern!)
      : null;

  /// Stop positions, evenly spread when none are stored.
  List<double> get effectiveStops =>
      stops ??
      [
        for (var i = 0; i < colors.length; i++)
          colors.length == 1 ? 0 : i / (colors.length - 1),
      ];

  PixFill withPrimary(Color c) {
    if (isPattern) {
      return copyWith(
        colors: [c, colors.length > 1 ? colors[1] : const Color(0x00000000)],
      );
    }
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
    String? pattern,
    bool? mirror,
    double? detail,
    bool? tint,
  }) => PixFill._(
    kind ?? this.kind,
    List.unmodifiable(colors ?? this.colors),
    clearStops
        ? null
        : (stops == null ? this.stops : List<double>.unmodifiable(stops)),
    angle ?? this.angle,
    scale: scale ?? this.scale,
    center: center ?? this.center,
    pattern: pattern ?? this.pattern,
    mirror: mirror ?? this.mirror,
    detail: detail ?? this.detail,
    tint: tint ?? this.tint,
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
    if (isPattern) return _applyPattern(paint, bounds);
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
      case FillKind.solid || FillKind.pattern:
        paint.shader = null;
    }
    return paint;
  }

  /// Pattern tiles start at the painted box's top-left (moved by [center]
  /// tiles), rotated by [angle] and scaled by [scale].
  Paint _applyPattern(Paint paint, Rect bounds) {
    final img = Patterns.tile(
      pattern!,
      fg: colors.isEmpty ? const Color(0xFF000000) : colors.first,
      bg: colors.length > 1 ? colors[1] : const Color(0x00000000),
      mirror: mirror,
      detail: detail,
      tint: tint,
    );
    if (img == null) {
      paint
        ..shader = null
        ..color = const Color(0x00000000);
      return paint;
    }
    final sc = scale.clamp(0.02, 50.0);
    final rad = angle * math.pi / 180;
    final cs = math.cos(rad) * sc, sn = math.sin(rad) * sc;
    final origin =
        bounds.topLeft +
        Offset(center.dx * img.width * sc, center.dy * img.height * sc);
    paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = ImageShader(
        img,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          cs, sn, 0, 0, //
          -sn, cs, 0, 0, //
          0, 0, 1, 0, //
          origin.dx, origin.dy, 0, 1, //
        ]),
        filterQuality: FilterQuality.medium,
      );
    return paint;
  }

  Json toJson() => {
    'kind': kind.name,
    'colors': [for (final c in _effectiveColors) writeColor(c)],
    if (stops != null) 'stops': stops,
    if (pattern != null) 'pattern': pattern,
    if (mirror) 'mirror': true,
    if (detail != 1) 'detail': detail,
    if (tint) 'tint': true,
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
    if (kind == FillKind.pattern && m['pattern'] is String) {
      return PixFill.pattern(
        m['pattern'] as String,
        fg: colors.first,
        bg: colors.length > 1 ? colors[1] : const Color(0x00000000),
        angle: readDouble(m['angle']),
        scale: readDouble(m['scale'], 1).clamp(0.02, 50.0),
        center: Offset(readDouble(m['cx']), readDouble(m['cy'])),
        mirror: readBool(m['mirror']),
        detail: readDouble(m['detail'], 1).clamp(0.1, 4.0),
        tint: readBool(m['tint']),
      );
    }
    if (kind == FillKind.solid ||
        kind == FillKind.pattern ||
        colors.length < 2) {
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
      other.pattern == pattern &&
      other.mirror == mirror &&
      other.detail == detail &&
      other.tint == tint &&
      listEquals(other._effectiveColors, _effectiveColors) &&
      listEquals(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    kind,
    angle,
    scale,
    center,
    pattern,
    mirror,
    detail,
    tint,
    Object.hashAll(_effectiveColors),
    stops == null ? null : Object.hashAll(stops!),
  );
}
