import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/blend.dart';
import '../model/effect.dart';
import 'bevel_engine.dart' show ContourPreset;
import 'mask_jobs.dart';
import 'pixel_ops.dart';

/// Every Outer / Inner Glow setting (Photoshop's Structure, Elements and
/// Quality groups), read from a `glow` or `innerGlow` [LayerEffect].
@immutable
class GlowParams {
  const GlowParams({
    required this.inner,
    this.blend = PixBlendMode.screen,
    this.opacity = 0.75,
    this.noise = 0,
    this.color = const Color(0xFFFFFFBE),
    this.gradient = false,
    this.color2 = const Color(0x00FFFFBE),
    this.precise = false,
    this.center = false,
    this.spread = 0,
    this.size = 5,
    this.contour = ContourPreset.linear,
    this.antiAlias = false,
    this.range = 0.5,
    this.jitter = 0,
    this.clip = true,
  });

  /// Photoshop's Spread / Choke on a Drop / Inner Shadow of [blur] (the
  /// shadow's softness, σ = blur / 2): the same growing and softening as
  /// a glow; the renderer moves and colours the mask.
  factory GlowParams.shadow({
    required bool inner,
    required double blur,
    required double spread,
  }) => GlowParams(
    inner: inner,
    size: blur * 1.5,
    spread: spread,
    range: 1,
    clip: false,
  );

  /// Inner Glow (inside the shape) or Outer Glow.
  final bool inner;
  final PixBlendMode blend;
  final double opacity;

  /// 0..1: speckles the glow.
  final double noise;
  final Color color;

  /// Gradient fill from [color] (at the source) to [color2].
  final bool gradient;
  final Color color2;

  /// Technique: Precise (exact distance falloff) or Softer (blur).
  final bool precise;

  /// Inner Glow source: from the Center or from the Edge.
  final bool center;

  /// Spread (outer) / Choke (inner), 0..1 of [size].
  final double spread;

  /// Pixels.
  final double size;
  final ContourPreset contour;
  final bool antiAlias;

  /// Range, 0.01..1: the part of the glow the contour spans.
  final double range;

  /// Gradient jitter, 0..1.
  final double jitter;

  /// Inner masks end at the shape's edge (off for inner shadows, which
  /// are moved before they are clipped).
  final bool clip;

  factory GlowParams.of(LayerEffect e) {
    final inner = e.type == 'innerGlow';
    double n(String k, double d) => e.number(k, d);
    if (n('v', 0) < 2) {
      // Older glows: a plain blurred silhouette (σ = blur / 2).
      return GlowParams(
        inner: inner,
        blend: PixBlendMode.normal,
        opacity: n('opacity', 0.9).clamp(0.0, 1.0),
        color: e.color(
          'color',
          inner ? const Color(0xFFFFF3A0) : const Color(0xFF7C9CFF),
        ),
        size: n('blur', inner ? 18 : 24).clamp(0.0, 1000.0) * 1.5,
        range: 1,
      );
    }
    T pick<T extends Enum>(List<T> v, String k, double d) =>
        v[n(k, d).round().clamp(0, v.length - 1)];
    return GlowParams(
      inner: inner,
      blend: pick(PixBlendMode.values, 'blend', 5),
      opacity: n('opacity', 0.75).clamp(0.0, 1.0),
      noise: n('noise', 0).clamp(0, 100) / 100,
      color: e.color('color', const Color(0xFFFFFFBE)),
      gradient: n('fill', 0) >= 1,
      color2: e.color('color2', const Color(0x00FFFFBE)),
      precise: n('technique', 0) >= 1,
      center: n('source', 0) >= 1,
      spread: n('spread', 0).clamp(0, 100) / 100,
      size: n('size', 5).clamp(0, 250).toDouble(),
      contour: pick(ContourPreset.values, 'contour', 0),
      antiAlias: n('antiAlias', 0) >= 1,
      range: n('range', 50).clamp(1, 100) / 100,
      jitter: n('jitter', 0).clamp(0, 100) / 100,
    );
  }

  /// Whether the GPU can draw it exactly (a blurred silhouette with the
  /// range as a linear alpha ramp); otherwise it runs in the background.
  bool get fast =>
      !precise &&
      spread == 0 &&
      contour == ContourPreset.linear &&
      noise == 0 &&
      !gradient;

  /// How far it reaches outside the shape (layer pixels).
  double get reach => inner ? 0 : size + 2;

  /// Blur σ of the soft falloff: the glow fades out over [size].
  double get sigma => size * (1 - spread) / 3;

  /// Settings that change the computed mask (not colour or blending,
  /// except for gradients, whose colours are baked in).
  Object get computeKey => Object.hashAll([
    inner,
    noise,
    gradient,
    if (gradient) ...[color, color2, jitter],
    precise,
    center,
    spread,
    size,
    contour,
    antiAlias,
    range,
    clip,
  ]);
}

/// Precise / spread / contour / noise / gradient glows, per pixel.
abstract final class GlowEngine {
  /// The job for [p] at [res] pixels per layer unit: shape alpha →
  /// glow coverage (and, for gradients, its colours).
  static MaskCompute job(GlowParams p, double res) =>
      (rgba, w, h) => compute(alphaOf(rgba), w, h, res, p);

  @visibleForTesting
  static List<Uint8List> compute(
    Float32List alpha,
    int w,
    int h,
    double res,
    GlowParams p,
  ) {
    final n = w * h;
    // The source: the shape (outer) or everything outside it (inner).
    final src = Float32List(n);
    for (var i = 0; i < n; i++) {
      src[i] = p.inner ? 1 - alpha[i] : alpha[i];
    }
    final sizePx = math.max(0.0, p.size * res);
    final spreadPx = sizePx * p.spread;
    final fadePx = sizePx - spreadPx;

    // Spread / Choke: grow the source by an exact round distance.
    var grown = src;
    if (spreadPx > 0.25) {
      final dist = _distanceTo(src, w, h);
      grown = Float32List(n);
      for (var i = 0; i < n; i++) {
        grown[i] = math.max(src[i], (spreadPx + 0.5 - dist[i]).clamp(0.0, 1.0));
      }
    }

    // Falloff over the rest of the size.
    Float32List t;
    if (fadePx < 0.5) {
      t = grown;
    } else if (p.precise) {
      // Precise: opacity falls off linearly with the exact distance.
      final dist = _distanceTo(grown, w, h);
      t = Float32List(n);
      for (var i = 0; i < n; i++) {
        t[i] = math.max(grown[i], (1 - dist[i] / fadePx).clamp(0.0, 1.0));
      }
    } else {
      // Softer: a blur (three box passes ≈ Gaussian, σ ≈ fade / 3).
      final r = math.max(1, (fadePx / 3).round());
      t = blur3(grown, w, h, r);
    }

    // Contour over the range, anti-aliased on request.
    var out = Float32List(n);
    final pos = p.gradient ? Float32List(n) : null;
    for (var i = 0; i < n; i++) {
      var x = (t[i] / p.range).clamp(0.0, 1.0);
      if (p.inner && p.center) x = 1 - x;
      pos?[i] = x;
      out[i] = p.contour.apply(x);
    }
    if (p.antiAlias && p.contour != ContourPreset.linear) {
      out = boxBlur(out, w, h, 1);
    }

    // Noise: some pixels jump to full or none, as often as their opacity.
    final rnd = math.Random(12345);
    if (p.noise > 0) {
      for (var i = 0; i < n; i++) {
        final v = out[i];
        if (v <= 0) continue;
        final speck = rnd.nextDouble() < v ? 1.0 : 0.0;
        out[i] = v + (speck - v) * p.noise;
      }
    }

    // Inner glows stay inside the shape.
    if (p.inner && p.clip) {
      for (var i = 0; i < n; i++) {
        out[i] *= alpha[i];
      }
    }

    if (!p.gradient) return [toBytes(out)];

    // Gradient: colour by position (jittered), its alpha into the mask.
    final rgb = Uint8List(n * 3);
    final c1 = p.color, c2 = p.color2;
    for (var i = 0; i < n; i++) {
      var g = pos![i];
      if (p.jitter > 0) {
        g = (g + (rnd.nextDouble() - 0.5) * p.jitter).clamp(0.0, 1.0);
      }
      final j = i * 3;
      rgb[j] = ((c2.r + (c1.r - c2.r) * g) * 255).round().clamp(0, 255);
      rgb[j + 1] = ((c2.g + (c1.g - c2.g) * g) * 255).round().clamp(0, 255);
      rgb[j + 2] = ((c2.b + (c1.b - c2.b) * g) * 255).round().clamp(0, 255);
      out[i] *= c2.a + (c1.a - c2.a) * g;
    }
    return [toBytes(out), rgb];
  }

  /// Distance (pixels) from each pixel to the coverage [a] (0 inside),
  /// refined by the anti-aliased edge.
  static Float32List _distanceTo(Float32List a, int w, int h) {
    final n = w * h;
    final inside = Uint8List(n);
    for (var i = 0; i < n; i++) {
      inside[i] = a[i] >= 0.5 ? 1 : 0;
    }
    final d2 = edtSquared(inside, w, h, 1);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = inside[i] == 1 ? 0 : math.max(0, math.sqrt(d2[i]) - 0.5 - a[i]);
    }
    return out;
  }
}
