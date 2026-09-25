import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../model/blend.dart';
import '../model/effect.dart';
import 'mask_jobs.dart';
import 'pixel_ops.dart';

/// Photoshop's Bevel & Emboss styles.
enum BevelKind { inner, outer, emboss, pillow, strokeEmboss }

/// Photoshop's Technique.
enum BevelTechnique { smooth, chiselHard, chiselSoft }

/// Photoshop's contour presets (used for Gloss Contour and Contour).
enum ContourPreset {
  linear,
  cone,
  coneInverted,
  gaussian,
  halfRound,
  ring,
  ringDouble,
  rollingSlope,
  roundedSteps,
  sawtooth,
  coveDeep,
  coveShallow;

  /// The curve, 0..1 → 0..1.
  double apply(double t) {
    final x = t.clamp(0.0, 1.0);
    switch (this) {
      case linear:
        return x;
      case cone:
        return 1 - (2 * x - 1).abs();
      case coneInverted:
        return (2 * x - 1).abs();
      case gaussian:
        return x * x * (3 - 2 * x);
      case halfRound:
        return math.sqrt(1 - (1 - x) * (1 - x));
      case ring:
        return 0.5 - 0.5 * math.cos(2 * math.pi * x);
      case ringDouble:
        return 0.5 - 0.5 * math.cos(4 * math.pi * x);
      case rollingSlope:
        return (x + 0.12 * math.sin(2 * math.pi * x)).clamp(0.0, 1.0);
      case roundedSteps:
        final k = x * 4;
        final f = k - k.floorToDouble();
        return ((k.floorToDouble() + f * f * (3 - 2 * f)) / 4).clamp(0.0, 1.0);
      case sawtooth:
        final k = x * 3;
        return k - k.floorToDouble();
      case coveDeep:
        return x * x * x;
      case coveShallow:
        return math.pow(x, 1.6).toDouble();
    }
  }
}

/// Every Bevel & Emboss setting, read from a `bevel` [LayerEffect].
///
/// Older projects stored a simpler bevel (offset "depth" in pixels, a
/// light angle in screen degrees); those are mapped onto the new set.
@immutable
class BevelParams {
  const BevelParams({
    this.kind = BevelKind.inner,
    this.technique = BevelTechnique.smooth,
    this.depth = 1,
    this.up = true,
    this.size = 5,
    this.soften = 0,
    this.angle = 120,
    this.altitude = 30,
    this.gloss = ContourPreset.linear,
    this.antiAlias = false,
    this.highlightMode = PixBlendMode.screen,
    this.highlight = const Color(0xFFFFFFFF),
    this.highlightOpacity = 0.75,
    this.shadowMode = PixBlendMode.multiply,
    this.shadow = const Color(0xFF000000),
    this.shadowOpacity = 0.75,
    this.contour,
    this.contourRange = 0.5,
    this.texture,
    this.textureScale = 1,
    this.textureDepth = 1,
    this.textureInvert = false,
  });

  final BevelKind kind;
  final BevelTechnique technique;

  /// Photoshop's Depth as a factor (1 = 100%).
  final double depth;
  final bool up;

  /// Bevel width in layer pixels.
  final double size;

  /// Blur of the shading, in layer pixels.
  final double soften;

  /// Light angle in degrees, counter-clockwise from the right (Photoshop).
  final double angle;

  /// Light altitude in degrees (90 = straight above).
  final double altitude;
  final ContourPreset gloss;
  final bool antiAlias;
  final PixBlendMode highlightMode;
  final Color highlight;
  final double highlightOpacity;
  final PixBlendMode shadowMode;
  final Color shadow;
  final double shadowOpacity;

  /// Profile of the bevel (Contour sub-section), null = off.
  final ContourPreset? contour;
  final double contourRange;

  /// Texture pattern id (Texture sub-section), null = off.
  final String? texture;
  final double textureScale;

  /// -10..10 (Photoshop's -1000%..+1000%).
  final double textureDepth;
  final bool textureInvert;

  static T _enum<T extends Enum>(List<T> values, double v) =>
      values[v.round().clamp(0, values.length - 1)];

  factory BevelParams.of(LayerEffect e) {
    double n(String k, double d) => e.number(k, d);
    if (e.number('v', 0) < 2) {
      // Older bevel: map it to the closest Photoshop settings.
      final old = n('angle', 225);
      final dir = n('direction', 0) >= 1;
      return BevelParams(
        kind: _enum(BevelKind.values, n('style', 0)),
        technique: n('technique', 0) >= 1
            ? BevelTechnique.chiselHard
            : BevelTechnique.smooth,
        size: n('size', 6) + n('depth', 6),
        soften: n('soften', 0),
        angle: ((-old) % 360 + 360) % 360,
        up: !dir,
        highlight: e.color('highlight', const Color(0xFFFFFFFF)),
        highlightOpacity: n('highlightOpacity', 0.75).clamp(0.0, 1.0),
        shadow: e.color('shadowColor', const Color(0xFF000000)),
        shadowOpacity: n('shadowOpacity', 0.6).clamp(0.0, 1.0),
      );
    }
    return BevelParams(
      kind: _enum(BevelKind.values, n('style', 0)),
      technique: _enum(BevelTechnique.values, n('technique', 0)),
      depth: n('depth', 100).clamp(1, 1000) / 100,
      up: n('direction', 0) < 1,
      size: n('size', 5).clamp(0, 250).toDouble(),
      soften: n('soften', 0).clamp(0, 16).toDouble(),
      angle: n('angle', 120),
      altitude: n('altitude', 30).clamp(0, 90).toDouble(),
      gloss: _enum(ContourPreset.values, n('gloss', 0)),
      antiAlias: n('antiAlias', 0) >= 1,
      highlightMode: _enum(PixBlendMode.values, n('highlightMode', 5)),
      highlight: e.color('highlight', const Color(0xFFFFFFFF)),
      highlightOpacity: n('highlightOpacity', 0.75).clamp(0.0, 1.0),
      shadowMode: _enum(PixBlendMode.values, n('shadowMode', 2)),
      shadow: e.color('shadowColor', const Color(0xFF000000)),
      shadowOpacity: n('shadowOpacity', 0.75).clamp(0.0, 1.0),
      contour: n('contourOn', 0) >= 1
          ? _enum(ContourPreset.values, n('contour', 0))
          : null,
      contourRange: n('contourRange', 50).clamp(1, 100) / 100,
      texture: n('textureOn', 0) >= 1 ? e.string('texture', 'dots') : null,
      textureScale: n('textureScale', 100).clamp(1, 1000) / 100,
      textureDepth: n('textureDepth', 100).clamp(-1000, 1000) / 100,
      textureInvert: n('textureInvert', 0) >= 1,
    );
  }

  /// These settings as `bevel` effect params (current format).
  Map<String, Object> toParams() => {
    'v': 2,
    'style': kind.index,
    'technique': technique.index,
    'depth': depth * 100,
    'direction': up ? 0 : 1,
    'size': size,
    'soften': soften,
    'angle': angle,
    'altitude': altitude,
    'gloss': gloss.index,
    'antiAlias': antiAlias ? 1 : 0,
    'highlightMode': highlightMode.index,
    'highlight': highlight.toARGB32(),
    'highlightOpacity': highlightOpacity,
    'shadowMode': shadowMode.index,
    'shadowColor': shadow.toARGB32(),
    'shadowOpacity': shadowOpacity,
    'contourOn': contour == null ? 0 : 1,
    'contour': (contour ?? ContourPreset.linear).index,
    'contourRange': contourRange * 100,
    'textureOn': texture == null ? 0 : 1,
    'texture': ?texture,
    'textureScale': textureScale * 100,
    'textureDepth': textureDepth * 100,
    'textureInvert': textureInvert ? 1 : 0,
  };

  /// The settings that change the computed shading (not its colours,
  /// opacities or blend modes, which are applied when drawing).
  Object get computeKey => Object.hashAll([
    kind,
    technique,
    depth,
    up,
    size,
    soften,
    angle,
    altitude,
    gloss,
    antiAlias,
    contour,
    contourRange,
    texture,
    textureScale,
    textureDepth,
    textureInvert,
  ]);

  /// How far the bevel paints outside the shape (layer pixels).
  double get reach => switch (kind) {
    BevelKind.inner || BevelKind.strokeEmboss => soften * 2,
    BevelKind.outer => size + soften * 2,
    BevelKind.emboss || BevelKind.pillow => size / 2 + soften * 2,
  };

  @override
  bool operator ==(Object other) =>
      other is BevelParams &&
      other.kind == kind &&
      other.technique == technique &&
      other.depth == depth &&
      other.up == up &&
      other.size == size &&
      other.soften == soften &&
      other.angle == angle &&
      other.altitude == altitude &&
      other.gloss == gloss &&
      other.antiAlias == antiAlias &&
      other.highlightMode == highlightMode &&
      other.highlight == highlight &&
      other.highlightOpacity == highlightOpacity &&
      other.shadowMode == shadowMode &&
      other.shadow == shadow &&
      other.shadowOpacity == shadowOpacity &&
      other.contour == contour &&
      other.contourRange == contourRange &&
      other.texture == texture &&
      other.textureScale == textureScale &&
      other.textureDepth == textureDepth &&
      other.textureInvert == textureInvert;

  @override
  int get hashCode => Object.hashAll([
    kind,
    technique,
    depth,
    up,
    size,
    soften,
    angle,
    altitude,
    gloss,
    antiAlias,
    highlightMode,
    highlight,
    highlightOpacity,
    shadowMode,
    shadow,
    shadowOpacity,
    contour,
    contourRange,
    texture,
    textureScale,
    textureDepth,
    textureInvert,
  ]);
}

/// Bevel & Emboss shading maths. The renderer runs it through the
/// `MaskJobCache` (in the background, with live previews).
abstract final class BevelEngine {
  /// The job for [p] at [res] pixels per layer unit: the shape in alpha
  /// (and, with a texture, its heights in the red channel) → highlight
  /// and shadow masks.
  static MaskCompute job(BevelParams p, double res) => (rgba, w, h) {
    final a = alphaOf(rgba);
    Float32List? tex;
    if (p.texture != null) {
      tex = Float32List(w * h);
      for (var i = 0; i < tex.length; i++) {
        tex[i] = rgba[i * 4] / 255;
      }
    }
    final (hl, sh) = shade(a, w, h, res, p, texture: tex);
    return [toBytes(hl), toBytes(sh)];
  };

  // ------------------------------------------------------------ the math

  /// Highlight and shadow amounts (0..1) for a shape [alpha] of [w]×[h]
  /// pixels at [res] pixels per layer unit — Photoshop's pipeline:
  /// distance from the edge → bevel height (style, technique, contour,
  /// texture) → surface normals (depth, direction) → light (angle,
  /// altitude) → gloss contour → soften.
  @visibleForTesting
  static (Float32List, Float32List) shade(
    Float32List alpha,
    int w,
    int h,
    double res,
    BevelParams p, {
    Float32List? texture,
  }) {
    final n = w * h;
    final sizePx = math.max(0.5, p.size * res);
    // Signed distances to the edge (inside > 0), from exact Euclidean
    // distance transforms of the inside and the outside, refined by the
    // anti-aliased alpha.
    final inside = Uint8List(n);
    for (var i = 0; i < n; i++) {
      inside[i] = alpha[i] >= 0.5 ? 1 : 0;
    }
    // Inner bevels need no distances outside the shape, outer ones none
    // inside it (only the side), so skip the transform that is not used.
    final needIn = p.kind != BevelKind.outer;
    final needOut =
        p.kind != BevelKind.inner && p.kind != BevelKind.strokeEmboss;
    // Distance to the nearest outside / inside pixel.
    final dIn = needIn ? edtSquared(inside, w, h, 0) : null;
    final dOut = needOut ? edtSquared(inside, w, h, 1) : null;
    final sd = Float32List(n);
    for (var i = 0; i < n; i++) {
      final a = alpha[i] - 0.5;
      if (inside[i] == 1) {
        sd[i] = dIn == null ? 0.5 + a : math.sqrt(dIn[i]) - 0.5 + a;
      } else {
        sd[i] = dOut == null ? -0.5 + a : -(math.sqrt(dOut[i]) - 0.5) + a;
      }
    }

    // Height 0..1 by style (one loop per style: this runs per pixel).
    var height = Float32List(n);
    final half = sizePx / 2;
    final inv = 1 / sizePx;
    switch (p.kind) {
      case BevelKind.inner || BevelKind.strokeEmboss:
        for (var i = 0; i < n; i++) {
          final v = sd[i] * inv;
          height[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
        }
      case BevelKind.outer:
        for (var i = 0; i < n; i++) {
          final d = sd[i];
          final v = d >= 0 ? 1.0 : 1 + d * inv;
          height[i] = v < 0 ? 0 : v;
        }
      case BevelKind.emboss:
        for (var i = 0; i < n; i++) {
          final v = 0.5 + sd[i] * inv;
          height[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
        }
      case BevelKind.pillow:
        for (var i = 0; i < n; i++) {
          final v = sd[i].abs() / half;
          height[i] = v > 1 ? 1 : v;
        }
    }

    // Technique: Smooth rounds the ramp, Chisel Soft slightly; Chisel
    // Hard keeps the exact distance ramp (crisp ridges).
    switch (p.technique) {
      case BevelTechnique.smooth:
        height = blur3(height, w, h, math.max(1, (sizePx / 3).round()));
      case BevelTechnique.chiselSoft:
        height = blur3(height, w, h, math.max(1, (sizePx / 10).round()));
      case BevelTechnique.chiselHard:
        // Just enough to hide pixel steps; ridges stay crisp.
        height = boxBlur(height, w, h, 1);
    }

    // Contour (profile), over the range.
    final c = p.contour;
    if (c != null) {
      final range = p.contourRange;
      for (var i = 0; i < n; i++) {
        final t = (height[i] / range).clamp(0.0, 1.0);
        height[i] = c.apply(t) * range + (height[i] - range).clamp(0.0, 1.0);
      }
    }

    // Height in pixels; texture bumps the surface inside the shape.
    // 100% depth ≈ a 20° bevel face; more depth makes it steeper.
    final scale = sizePx * p.depth * 0.35 * (p.up ? 1 : -1);
    final z = Float32List(n);
    for (var i = 0; i < n; i++) {
      var v = height[i] * scale;
      if (texture != null && alpha[i] > 0) {
        final t = p.textureInvert ? 1 - texture[i] : texture[i];
        v += (t - 0.5) * p.textureDepth * res * 2 * alpha[i];
      }
      z[i] = v;
    }

    // Light, Photoshop convention: angle counter-clockwise from the right
    // (y up), altitude above the surface.
    final th = p.angle * math.pi / 180, al = p.altitude * math.pi / 180;
    final lx = math.cos(al) * math.cos(th);
    final ly = -math.cos(al) * math.sin(th); // screen y points down
    final lz = math.sin(al);
    final flat = lz;

    // Gloss contour as a lookup table (it runs twice per pixel).
    const lutSize = 1024;
    final lut = Float32List(lutSize + 1);
    for (var i = 0; i <= lutSize; i++) {
      lut[i] = p.gloss.apply(i / lutSize);
    }
    final upScale = 1 / math.max(1e-4, 1 - flat);
    final downScale = 2 / math.max(1e-4, flat + 1);

    var hl = Float32List(n), sh = Float32List(n);
    if (lut[0] != 0) {
      hl.fillRange(0, n, lut[0]);
      sh.fillRange(0, n, lut[0]);
    }
    for (var y = 0; y < h; y++) {
      final r0 = (y > 0 ? y - 1 : y) * w, r1 = (y < h - 1 ? y + 1 : y) * w;
      final dy = (y > 0 && y < h - 1) ? 0.5 : 1.0;
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final i = row + x;
        final x0 = x > 0 ? x - 1 : x, x1 = x < w - 1 ? x + 1 : x;
        final gx = (z[row + x1] - z[row + x0]) * ((x0 < x && x < x1) ? 0.5 : 1);
        final gy = (z[r1 + x] - z[r0 + x]) * dy;
        if (gx == 0 && gy == 0) continue; // flat: neither lit nor shaded
        final s = (-gx * lx - gy * ly + lz) / math.sqrt(gx * gx + gy * gy + 1);
        if (s > flat) {
          var u = (s - flat) * upScale;
          if (u > 1) u = 1;
          hl[i] = lut[(u * lutSize).round()];
        } else if (s < flat) {
          var d = (flat - s) * downScale;
          if (d > 1) d = 1;
          sh[i] = lut[(d * lutSize).round()];
        }
      }
    }

    // Anti-aliased gloss: smooth the contour's steps a little.
    if (p.antiAlias) {
      hl = blur3(hl, w, h, 1);
      sh = blur3(sh, w, h, 1);
    }
    final soft = (p.soften * res).round();
    if (soft > 0) {
      hl = blur3(hl, w, h, soft);
      sh = blur3(sh, w, h, soft);
    }

    // Where each style shows: inside (inner), outside (outer), both.
    for (var i = 0; i < n; i++) {
      final m = switch (p.kind) {
        BevelKind.inner || BevelKind.strokeEmboss => alpha[i],
        BevelKind.outer => (1 - alpha[i]) * (sd[i] > -sizePx - 1 ? 1 : 0),
        BevelKind.emboss || BevelKind.pillow => sd[i] > -half - 1 ? 1.0 : 0.0,
      };
      hl[i] *= m;
      sh[i] *= m;
    }
    return (hl, sh);
  }
}
