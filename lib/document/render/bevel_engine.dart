import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../model/blend.dart';
import '../model/effect.dart';
import '../model/patterns.dart';

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

/// The two shading masks (highlight, shadow) of a computed bevel, over
/// [rect] (layer space).
class BevelResult {
  BevelResult(this.highlight, this.shadow, this.rect);
  final ui.Image highlight;
  final ui.Image shadow;
  final Rect rect;

  void dispose() {
    highlight.dispose();
    shadow.dispose();
  }
}

/// Computes Photoshop-accurate Bevel & Emboss shading off the paint path
/// and caches the results; listeners are told when a bevel is ready so the
/// canvas can repaint. Export awaits [ensure] instead.
class BevelCache extends ChangeNotifier {
  BevelCache._();
  static final BevelCache instance = BevelCache._();

  static const _max = 32;
  final LinkedHashMap<Object, BevelResult> _done = LinkedHashMap();
  final Map<Object, Future<BevelResult?>> _pending = {};

  BevelResult? lookup(Object key) {
    final hit = _done.remove(key);
    if (hit != null) _done[key] = hit;
    return hit;
  }

  bool isReady(Object key) => _done.containsKey(key);
  bool isPending(Object key) => _pending.containsKey(key);

  /// Completes when [key] is computed (at once if it is not running).
  Future<void> wait(Object key) async {
    await _pending[key];
  }

  /// Starts computing (once) from [alpha], the layer's shape rendered over
  /// [rect] at [res] pixels per layer unit. [alpha] is disposed here.
  Future<BevelResult?> request(
    Object key,
    ui.Image alpha,
    Rect rect,
    double res,
    BevelParams p,
  ) {
    final hit = _done[key];
    if (hit != null) {
      alpha.dispose();
      return Future.value(hit);
    }
    final running = _pending[key];
    if (running != null) {
      alpha.dispose();
      return running;
    }
    final f = _compute(alpha, rect, res, p).then((r) {
      _pending.remove(key);
      if (r != null) {
        _done[key] = r;
        while (_done.length > _max) {
          _done.remove(_done.keys.first)?.dispose();
        }
        notifyListeners();
      }
      return r;
    });
    _pending[key] = f;
    return f;
  }

  Future<BevelResult?> _compute(
    ui.Image alpha,
    Rect rect,
    double res,
    BevelParams p,
  ) async {
    try {
      final data = await alpha.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final w = alpha.width, h = alpha.height;
      alpha.dispose();
      if (data == null) return null;
      final a = Float32List(w * h);
      final bytes = data.buffer.asUint8List();
      for (var i = 0; i < a.length; i++) {
        a[i] = bytes[i * 4 + 3] / 255;
      }
      Float32List? tex;
      if (p.texture != null) tex = await _texture(p, w, h, res);
      final (hl, sh) = shade(a, w, h, res, p, texture: tex);
      // Pure coverage masks (grey = alpha, valid premultiplied or not);
      // colours, opacities and modes are applied when drawing.
      Future<ui.Image> image(Float32List amount) {
        final px = Uint8List(w * h * 4);
        for (var i = 0; i < amount.length; i++) {
          final j = i * 4;
          final v = (amount[i] * 255).round().clamp(0, 255);
          px[j] = v;
          px[j + 1] = v;
          px[j + 2] = v;
          px[j + 3] = v;
        }
        final done = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          px,
          w,
          h,
          ui.PixelFormat.rgba8888,
          done.complete,
        );
        return done.future;
      }

      return BevelResult(await image(hl), await image(sh), rect);
    } catch (e) {
      debugPrint('Pixora: bevel failed: $e');
      return null;
    }
  }

  /// Texture heights (0..1) laid over the bevel's pixels.
  static Future<Float32List?> _texture(
    BevelParams p,
    int w,
    int h,
    double res,
  ) async {
    final tile = Patterns.tile(
      p.texture!,
      fg: const Color(0xFFFFFFFF),
      bg: const Color(0xFF000000),
    );
    if (tile == null) return null;
    final rec = ui.PictureRecorder();
    final k = p.textureScale * res;
    Canvas(rec).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList([
            k,
            0,
            0,
            0,
            0,
            k,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1,
          ]),
        ),
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(w, h);
    pic.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) return null;
    final b = data.buffer.asUint8List();
    final out = Float32List(w * h);
    for (var i = 0; i < out.length; i++) {
      final j = i * 4;
      out[i] = (0.2126 * b[j] + 0.7152 * b[j + 1] + 0.0722 * b[j + 2]) / 255;
    }
    return out;
  }

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
    final dIn = _edt(inside, w, h, 0); // distance to nearest outside pixel
    final dOut = _edt(inside, w, h, 1); // distance to nearest inside pixel
    final sd = Float32List(n);
    for (var i = 0; i < n; i++) {
      sd[i] = inside[i] == 1
          ? math.sqrt(dIn[i]) - 0.5 + (alpha[i] - 0.5)
          : -(math.sqrt(dOut[i]) - 0.5) + (alpha[i] - 0.5);
    }

    // Height 0..1 by style.
    var height = Float32List(n);
    final half = sizePx / 2;
    for (var i = 0; i < n; i++) {
      final d = sd[i];
      double v;
      switch (p.kind) {
        case BevelKind.inner || BevelKind.strokeEmboss:
          v = (d / sizePx).clamp(0.0, 1.0);
        case BevelKind.outer:
          v = d >= 0 ? 1 : (1 + d / sizePx).clamp(0.0, 1.0);
        case BevelKind.emboss:
          v = (0.5 + d / sizePx).clamp(0.0, 1.0);
        case BevelKind.pillow:
          v = (d.abs() / half).clamp(0.0, 1.0);
      }
      height[i] = v;
    }

    // Technique: Smooth rounds the ramp, Chisel Soft slightly; Chisel
    // Hard keeps the exact distance ramp (crisp ridges).
    switch (p.technique) {
      case BevelTechnique.smooth:
        height = _blur(height, w, h, math.max(1, (sizePx / 3).round()));
      case BevelTechnique.chiselSoft:
        height = _blur(height, w, h, math.max(1, (sizePx / 10).round()));
      case BevelTechnique.chiselHard:
        // Just enough to hide pixel steps; ridges stay crisp.
        height = _box(height, w, h, 1);
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

    var hl = Float32List(n), sh = Float32List(n);
    for (var y = 0; y < h; y++) {
      final y0 = y > 0 ? y - 1 : y, y1 = y < h - 1 ? y + 1 : y;
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final x0 = x > 0 ? x - 1 : x, x1 = x < w - 1 ? x + 1 : x;
        final gx = (z[y * w + x1] - z[y * w + x0]) / math.max(1, x1 - x0);
        final gy = (z[y1 * w + x] - z[y0 * w + x]) / math.max(1, y1 - y0);
        final len = math.sqrt(gx * gx + gy * gy + 1);
        final s = (-gx * lx - gy * ly + lz) / len;
        var up = s > flat ? (s - flat) / math.max(1e-4, 1 - flat) : 0.0;
        var down = s < flat ? (flat - s) / math.max(1e-4, flat + 1) * 2 : 0.0;
        up = p.gloss.apply(up.clamp(0.0, 1.0));
        down = p.gloss.apply(down.clamp(0.0, 1.0));
        hl[i] = up;
        sh[i] = down;
      }
    }

    // Anti-aliased gloss: smooth the contour's steps a little.
    if (p.antiAlias) {
      hl = _blur(hl, w, h, 1);
      sh = _blur(sh, w, h, 1);
    }
    final soft = (p.soften * res).round();
    if (soft > 0) {
      hl = _blur(hl, w, h, soft);
      sh = _blur(sh, w, h, soft);
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

  /// Squared Euclidean distance from each pixel to the nearest pixel whose
  /// [set] value is [target] (Felzenszwalb & Huttenlocher, two 1D passes).
  static Float32List _edt(Uint8List set, int w, int h, int target) {
    const inf = 1e20;
    final f = Float32List(math.max(w, h));
    final d = Float32List(math.max(w, h));
    final v = Int32List(math.max(w, h));
    final z = Float32List(math.max(w, h) + 1);
    final grid = Float32List(w * h);
    for (var i = 0; i < w * h; i++) {
      grid[i] = set[i] == target ? 0 : inf;
    }
    void pass(int len) {
      var k = 0;
      v[0] = 0;
      z[0] = -inf;
      z[1] = inf;
      for (var q = 1; q < len; q++) {
        var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        while (s <= z[k]) {
          k--;
          s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        }
        k++;
        v[k] = q;
        z[k] = s;
        z[k + 1] = inf;
      }
      k = 0;
      for (var q = 0; q < len; q++) {
        while (z[k + 1] < q) {
          k++;
        }
        final dq = q - v[k];
        d[q] = dq * dq + f[v[k]];
      }
    }

    for (var x = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        f[y] = grid[y * w + x];
      }
      pass(h);
      for (var y = 0; y < h; y++) {
        grid[y * w + x] = d[y];
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        f[x] = grid[y * w + x];
      }
      pass(w);
      for (var x = 0; x < w; x++) {
        grid[y * w + x] = d[x];
      }
    }
    return grid;
  }

  /// Three box blurs (≈ Gaussian) of radius [r].
  static Float32List _blur(Float32List src, int w, int h, int r) {
    var a = src;
    for (var k = 0; k < 3; k++) {
      a = _box(a, w, h, r);
    }
    return a;
  }

  static Float32List _box(Float32List src, int w, int h, int r) {
    final tmp = Float32List(src.length), out = Float32List(src.length);
    final n = 2 * r + 1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var sum = 0.0;
      for (var k = -r; k <= r; k++) {
        sum += src[row + k.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        tmp[row + x] = sum / n;
        sum +=
            src[row + math.min(w - 1, x + r + 1)] -
            src[row + math.max(0, x - r)];
      }
    }
    for (var x = 0; x < w; x++) {
      var sum = 0.0;
      for (var k = -r; k <= r; k++) {
        sum += tmp[k.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        out[y * w + x] = sum / n;
        sum +=
            tmp[math.min(h - 1, y + r + 1) * w + x] -
            tmp[math.max(0, y - r) * w + x];
      }
    }
    return out;
  }
}
