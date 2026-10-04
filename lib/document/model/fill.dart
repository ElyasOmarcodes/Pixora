import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/utils/json.dart';
import 'patterns.dart';

/// Gradient styles, like Photoshop's: linear, radial, angle (sweep around
/// a centre), reflected (linear, mirrored around its centre) and diamond;
/// plus square (rings of squares), elliptical (radial fitted to the box)
/// and conic (an angle gradient mirrored halfway round), as in advanced
/// editors; and [pattern], a repeating tile (see [Patterns]).
enum FillKind {
  solid,
  linear,
  radial,
  sweep,
  reflected,
  pattern,
  diamond,
  square,
  elliptical,
  conic,
}

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

  /// [stops], or even spacing when more than two colours have none (the
  /// engine needs stops then).
  List<double>? get evenStops =>
      stops ??
      (colors.length > 2
          ? [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)]
          : null);

  /// The gradient's colour at [t] (0..1 along its stops); the colour of a
  /// solid fill.
  Color colorAt(double t) {
    if (colors.length < 2) return primary;
    final s = evenStops ?? const [0.0, 1.0];
    final x = t.clamp(0.0, 1.0);
    if (x <= s.first) return colors.first;
    for (var i = 1; i < colors.length; i++) {
      if (x <= s[i]) {
        final span = s[i] - s[i - 1];
        final f = span <= 0 ? 1.0 : (x - s[i - 1]) / span;
        return Color.lerp(colors[i - 1], colors[i], f)!;
      }
    }
    return colors.last;
  }

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
    final s = evenStops;
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
      case FillKind.conic:
        // Half a turn out, half a turn back: symmetric about the angle.
        paint.shader = Gradient.sweep(
          c,
          colors,
          s,
          TileMode.mirror,
          rad,
          rad + math.pi,
        );
      case FillKind.elliptical:
        // A radial gradient stretched to the box's proportions.
        final rx = math.max(0.5, bounds.width / 2 * scale);
        final ry = math.max(0.5, bounds.height / 2 * scale);
        final cs = math.cos(rad), sn = math.sin(rad);
        paint.shader = Gradient.radial(
          Offset.zero,
          1,
          colors,
          s,
          TileMode.clamp,
          Float64List.fromList([
            cs * rx, sn * rx, 0, 0, //
            -sn * ry, cs * ry, 0, 0, //
            0, 0, 1, 0, //
            c.dx, c.dy, 0, 1, //
          ]),
        );
      case FillKind.diamond || FillKind.square:
        paint.shader = _ringShader(c, rad, math.max(0.5, radialRadius(bounds)));
      case FillKind.solid || FillKind.pattern:
        paint.shader = null;
    }
    return paint;
  }

  static final Map<Object, Image> _rings = {};
  static const _ringSize = 512;

  /// Diamond (|u| + |v|) or square (max(|u|, |v|)) rings from the centre
  /// out to [radius], drawn once into a texture per colour set (four
  /// linear gradients, one per quarter) and laid onto the box.
  Shader _ringShader(Offset c, double rad, double radius) {
    final key = Object.hash(
      kind,
      Object.hashAll(colors),
      stops == null ? null : Object.hashAll(stops!),
    );
    final img = _rings[key] ??= () {
      if (_rings.length > 48) _rings.clear();
      const n = _ringSize;
      const h = n / 2;
      final rec = PictureRecorder();
      final canvas = Canvas(rec);
      const o = Offset(h, h);
      // Corners of the texture and, for diamonds, the axis ends.
      final quarters = kind == FillKind.square
          ? [
              // (triangle, direction of growth)
              (
                [o, const Offset(0, 0), const Offset(n * 1.0, 0)],
                const Offset(0, -1),
              ),
              (
                [o, const Offset(n * 1.0, 0), const Offset(n * 1.0, n * 1.0)],
                const Offset(1, 0),
              ),
              (
                [o, const Offset(n * 1.0, n * 1.0), const Offset(0, n * 1.0)],
                const Offset(0, 1),
              ),
              (
                [o, const Offset(0, n * 1.0), const Offset(0, 0)],
                const Offset(-1, 0),
              ),
            ]
          : [
              (
                [
                  o,
                  const Offset(h, 0),
                  const Offset(n * 1.0, 0),
                  const Offset(n * 1.0, h),
                ],
                const Offset(1, -1),
              ),
              (
                [
                  o,
                  const Offset(n * 1.0, h),
                  const Offset(n * 1.0, n * 1.0),
                  const Offset(h, n * 1.0),
                ],
                const Offset(1, 1),
              ),
              (
                [
                  o,
                  const Offset(h, n * 1.0),
                  const Offset(0, n * 1.0),
                  const Offset(0, h),
                ],
                const Offset(-1, 1),
              ),
              (
                [o, const Offset(0, h), const Offset(0, 0), const Offset(h, 0)],
                const Offset(-1, -1),
              ),
            ];
      for (final (pts, dir) in quarters) {
        // Value 1 where the ring reaches the texture's half-size.
        final end = kind == FillKind.square
            ? o + dir * h
            : o + dir * (h / 2); // |u| + |v| = h along the diagonal
        canvas.drawPath(
          Path()..addPolygon(pts, true),
          Paint()
            ..isAntiAlias = false
            ..shader = Gradient.linear(o, end, colors, evenStops),
        );
      }
      final pic = rec.endRecording();
      final out = pic.toImageSync(n, n);
      pic.dispose();
      return out;
    }();
    // Texture half-size ↔ [radius], turned by the angle, at the centre.
    final k = radius / (_ringSize / 2);
    final cs = math.cos(rad) * k, sn = math.sin(rad) * k;
    const h = _ringSize / 2;
    return ImageShader(
      img,
      TileMode.clamp,
      TileMode.clamp,
      Float64List.fromList([
        cs, sn, 0, 0, //
        -sn, cs, 0, 0, //
        0, 0, 1, 0, //
        c.dx - (cs * h - sn * h), c.dy - (sn * h + cs * h), 0, 1, //
      ]),
      filterQuality: FilterQuality.medium,
    );
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
