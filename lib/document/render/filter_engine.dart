import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A pixel filter (Photoshop's Filter menu, applied as a smart filter):
/// it works on the layer's own pixels, before the layer mask and before
/// layer styles, so styles follow the filtered result.
sealed class PixFilter {
  const PixFilter();

  /// How far (layer units) the filter can move pixels outwards.
  double get reach => 0;
}

/// Filter ▸ Blur ▸ Gaussian Blur. [radius] in pixels (≈ standard
/// deviation, as in Photoshop).
class GaussianBlurFilter extends PixFilter {
  const GaussianBlurFilter(this.radius);
  final double radius;
  @override
  double get reach => radius * 3;
}

/// Filter ▸ Blur ▸ Box Blur: the average of a (2r+1)² square.
class BoxBlurFilter extends PixFilter {
  const BoxBlurFilter(this.radius);
  final double radius;
  @override
  double get reach => radius + 1;
}

/// Filter ▸ Blur ▸ Motion Blur: the average along a line of [distance]
/// pixels at [angle] degrees (counter-clockwise, −90…90).
class MotionBlurFilter extends PixFilter {
  const MotionBlurFilter(this.angle, this.distance);
  final double angle;
  final double distance;
  @override
  double get reach => distance / 2 + 1;
}

/// Filter ▸ Blur ▸ Radial Blur: Spin (along circles) or Zoom (along rays)
/// around [center] (0..1 in the layer box).
class RadialBlurFilter extends PixFilter {
  const RadialBlurFilter({
    required this.amount,
    required this.zoom,
    required this.center,
    required this.box,
  });

  /// 1..100.
  final double amount;
  final bool zoom;
  final Offset center;

  /// The layer box [center] refers to.
  final Rect box;

  @override
  double get reach => zoom ? box.longestSide * amount / 100 * 0.35 : 0;
}

/// Blur Gallery ▸ Tilt-Shift: sharp band, blur growing away from it.
class TiltShiftFilter extends PixFilter {
  const TiltShiftFilter({
    required this.blur,
    required this.angle,
    required this.center,
    required this.focus,
    required this.transition,
    required this.box,
  });
  final double blur;

  /// Band direction, degrees.
  final double angle;

  /// Band centre, 0..1 in the layer box.
  final Offset center;

  /// Half the sharp band's width, and the fade, as fractions of the box.
  final double focus;
  final double transition;
  final Rect box;
  @override
  double get reach => blur * 3;
}

/// Filter ▸ Noise ▸ Add Noise: [amount] 0..4 (0–400 %), Uniform or
/// Gaussian, colour or Monochromatic. Alpha is kept.
class AddNoiseFilter extends PixFilter {
  const AddNoiseFilter({
    required this.amount,
    required this.gaussian,
    required this.mono,
    required this.seed,
  });
  final double amount;
  final bool gaussian;
  final bool mono;
  final int seed;
}

/// Film grain: soft monochrome grain of [size] pixels; [roughness] mixes
/// in fine grain.
class FilmGrainFilter extends PixFilter {
  const FilmGrainFilter({
    required this.amount,
    required this.size,
    required this.roughness,
    required this.seed,
  });

  /// 0..1.
  final double amount;
  final double size;
  final double roughness;
  final int seed;
}

/// Salt & pepper: random white and black specks covering [density]
/// (0..1) of the pixels.
class SaltPepperFilter extends PixFilter {
  const SaltPepperFilter({
    required this.density,
    required this.size,
    required this.seed,
  });
  final double density;
  final double size;
  final int seed;
}

/// Runs [PixFilter]s on the GPU: blurs as exact multi-tap averages built
/// by repeated doubling (log₂ passes, so even 2000 px motion blurs stay
/// fast and free of 8-bit banding), noise as pre-generated tiles added
/// with exact signed arithmetic (Photoshop adds noise, it does not
/// overlay it).
abstract final class FilterEngine {
  /// Applies [filters] in order to [src], an image of the layer covering
  /// [rect] (layer units). Returns a new image of the same size; [src] is
  /// left alone.
  static ui.Image apply(ui.Image src, Rect rect, List<PixFilter> filters) {
    var img = src;
    final res = src.width / rect.width;
    for (final f in filters) {
      final next = switch (f) {
        GaussianBlurFilter g => _gaussian(img, g.radius * res),
        BoxBlurFilter b => _box(img, b.radius * res),
        MotionBlurFilter m => _motion(img, m, res),
        RadialBlurFilter r => _radial(img, r, rect, res),
        TiltShiftFilter t => _tiltShift(img, t, rect, res),
        AddNoiseFilter n => _addNoise(img, [
          _NoisePass(
            NoiseTiles.signed(n.gaussian, n.mono, n.seed),
            res,
            n.amount * (n.gaussian ? 1.05 : 0.5),
            smooth: false,
          ),
        ]),
        FilmGrainFilter g => _addNoise(img, [
          _NoisePass(
            NoiseTiles.signed(true, true, g.seed),
            res * math.max(1, g.size),
            g.amount * 0.9 * (1 - g.roughness * 0.5),
            smooth: true,
          ),
          if (g.roughness > 0)
            _NoisePass(
              NoiseTiles.signed(true, true, g.seed + 7),
              res,
              g.amount * 0.9 * g.roughness * 0.5,
              smooth: false,
            ),
        ]),
        SaltPepperFilter s => _saltPepper(img, s, res),
      };
      if (next == null) continue;
      if (!identical(img, src)) img.dispose();
      img = next;
    }
    return identical(img, src) ? _copy(src) : img;
  }

  static ui.Image _draw(int w, int h, void Function(Canvas c) paint) {
    final rec = ui.PictureRecorder();
    paint(Canvas(rec));
    final pic = rec.endRecording();
    final out = pic.toImageSync(w, h);
    pic.dispose();
    return out;
  }

  static ui.Image _copy(ui.Image src) => _draw(
    src.width,
    src.height,
    (c) => c.drawImage(src, Offset.zero, Paint()),
  );

  static Rect _full(ui.Image i) =>
      Rect.fromLTWH(0, 0, i.width.toDouble(), i.height.toDouble());

  static ui.Image? _gaussian(ui.Image src, double sigma) {
    if (sigma < 0.05) return null;
    return _draw(src.width, src.height, (c) {
      c.saveLayer(
        _full(src),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
      );
      c.drawImage(src, Offset.zero, Paint());
      c.restore();
    });
  }

  /// Averages `2^steps` copies of [src], each moved by a combination of
  /// ± the per-step transforms: copy `i` gets `Σ ±xf(step)`. With evenly
  /// doubling steps this is an even N-tap average in log₂ N passes, each
  /// pass averaging just two images (so 8-bit rounding never piles up).
  static ui.Image _doubling(
    ui.Image src,
    int steps,
    void Function(Canvas c, int step, double sign) xf,
  ) {
    var img = src;
    final half = Paint()
      ..color = const Color.fromRGBO(0, 0, 0, 0.5)
      ..filterQuality = FilterQuality.low;
    final add = Paint()
      ..color = const Color.fromRGBO(0, 0, 0, 0.5)
      ..filterQuality = FilterQuality.low
      ..blendMode = BlendMode.plus;
    for (var j = 0; j < steps; j++) {
      final cur = img;
      final next = _draw(src.width, src.height, (c) {
        c
          ..save()
          ..clipRect(_full(src));
        for (final sign in const [-1.0, 1.0]) {
          c.save();
          xf(c, j, sign);
          c.drawImage(cur, Offset.zero, sign < 0 ? half : add);
          c.restore();
        }
        c.restore();
      });
      if (!identical(cur, src)) cur.dispose();
      img = next;
    }
    return img;
  }

  /// Tap count (as doubling steps) for spans of [span] pixels: taps at
  /// most ~1 px apart, up to 512.
  static int _steps(double span) {
    var k = 0;
    while (k < 9 && span / (1 << k) > 1) {
      k++;
    }
    return k;
  }

  /// An even average along [dir] (unit) over [length] pixels.
  static ui.Image? _line(ui.Image src, Offset dir, double length) {
    if (length < 1.2) return null;
    final k = _steps(length);
    final spacing = length / (1 << k);
    var out = _doubling(src, k, (c, j, sign) {
      final a = spacing * (1 << j) / 2 * sign;
      c.translate(dir.dx * a, dir.dy * a);
    });
    // Very long blurs: close the gaps between taps.
    if (spacing > 1.2) {
      final smooth = _gaussian(out, spacing * 0.45);
      if (smooth != null) {
        out.dispose();
        out = smooth;
      }
    }
    return out;
  }

  static ui.Image? _box(ui.Image src, double r) {
    final len = 2 * r + 1;
    final h = _line(src, const Offset(1, 0), len);
    final v = _line(h ?? src, const Offset(0, 1), len);
    if (v != null && h != null) h.dispose();
    return v ?? h;
  }

  static ui.Image? _motion(ui.Image src, MotionBlurFilter m, double res) {
    final a = m.angle * math.pi / 180;
    return _line(src, Offset(math.cos(a), -math.sin(a)), m.distance * res);
  }

  static ui.Image? _radial(
    ui.Image src,
    RadialBlurFilter r,
    Rect rect,
    double res,
  ) {
    final c0 = Offset(
      (r.box.left + r.center.dx * r.box.width - rect.left) * res,
      (r.box.top + r.center.dy * r.box.height - rect.top) * res,
    );
    // Farthest corner: where taps spread the most.
    var far = 0.0;
    for (final p in [
      Offset.zero,
      Offset(src.width.toDouble(), 0),
      Offset(0, src.height.toDouble()),
      Offset(src.width.toDouble(), src.height.toDouble()),
    ]) {
      far = math.max(far, (p - c0).distance);
    }
    if (r.zoom) {
      // Log-even scales around the centre: rays streak evenly.
      final beta = math.log(1 + r.amount / 100 * 0.7);
      final k = _steps(far * beta);
      if (k == 0) return null;
      final step = beta / (1 << k);
      return _doubling(src, k, (c, j, sign) {
        final s = math.exp(step * (1 << j) / 2 * sign);
        c
          ..translate(c0.dx, c0.dy)
          ..scale(s)
          ..translate(-c0.dx, -c0.dy);
      });
    }
    final theta = r.amount * math.pi / 180;
    final k = _steps(far * theta);
    if (k == 0) return null;
    final step = theta / (1 << k);
    return _doubling(src, k, (c, j, sign) {
      c
        ..translate(c0.dx, c0.dy)
        ..rotate(step * (1 << j) / 2 * sign)
        ..translate(-c0.dx, -c0.dy);
    });
  }

  static ui.Image? _tiltShift(
    ui.Image src,
    TiltShiftFilter t,
    Rect rect,
    double res,
  ) {
    final sigma = t.blur * res;
    if (sigma < 0.05) return null;
    final soft = _gaussian(src, sigma)!;
    final half = _gaussian(src, sigma * 0.45);
    final center = Offset(
      (t.box.left + t.center.dx * t.box.width - rect.left) * res,
      (t.box.top + t.center.dy * t.box.height - rect.top) * res,
    );
    final a = t.angle * math.pi / 180;
    // Across the band.
    final n = Offset(math.sin(a), math.cos(a));
    final size = t.box.shortestSide * res;
    final f = math.max(0.5, t.focus * size);
    final tr = math.max(0.5, t.transition * size);
    ui.Gradient band(double inner, double outer) {
      final total = inner + outer;
      return ui.Gradient.linear(
        center - n * total,
        center + n * total,
        const [
          Color(0x00FFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x00FFFFFF),
        ],
        [0, outer / (2 * total), (total + inner) / (2 * total), 1],
      );
    }

    final out = _draw(src.width, src.height, (c) {
      final full = _full(src);
      c.drawImage(soft, Offset.zero, Paint());
      // Half-blurred through the fade, sharp in the band.
      if (half != null) {
        c
          ..saveLayer(full, Paint())
          ..drawImage(half, Offset.zero, Paint())
          ..drawRect(
            full,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = band(f + tr * 0.5, tr),
          )
          ..restore();
      }
      c
        ..saveLayer(full, Paint())
        ..drawImage(src, Offset.zero, Paint())
        ..drawRect(
          full,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = band(f, tr),
        )
        ..restore();
    });
    soft.dispose();
    half?.dispose();
    return out;
  }

  // ---------------------------------------------------------------- noise

  static const _invertOpaque = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 0, 255, //
  ]);
  static const _invert = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  static ColorFilter _scale(double k) => ColorFilter.matrix([
    k, 0, 0, 0, 0, //
    0, k, 0, 0, 0, //
    0, 0, k, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  static Paint _tilePaint(ui.Image tile, double scale, double k, bool smooth) =>
      Paint()
        ..blendMode = BlendMode.plus
        ..colorFilter = _scale(k)
        ..filterQuality = smooth ? FilterQuality.medium : FilterQuality.none
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Float64List.fromList([
            scale, 0, 0, 0, //
            0, scale, 0, 0, //
            0, 0, 1, 0, //
            0, 0, 0, 1, //
          ]),
          filterQuality: smooth ? FilterQuality.medium : FilterQuality.none,
        );

  /// Adds signed noise to the colour of every pixel, keeping its alpha:
  /// `c' = c + p − n` on straight colour, done as
  /// `1 − ((1 − c) + n)` (the subtraction, via inverted layers) `+ p`,
  /// with the alpha put back at the end.
  static ui.Image? _addNoise(ui.Image src, List<_NoisePass> passes) {
    final live = [
      for (final p in passes)
        if (p.k > 0.001) p,
    ];
    if (live.isEmpty) return null;
    return _draw(src.width, src.height, (c) {
      final full = _full(src);
      c
        ..saveLayer(full, Paint())
        ..saveLayer(full, Paint()..colorFilter = _invert)
        ..drawImage(src, Offset.zero, Paint()..colorFilter = _invertOpaque);
      for (final p in live) {
        c.drawRect(full, _tilePaint(p.tiles.$2, p.scale, p.k, p.smooth));
      }
      c.restore();
      for (final p in live) {
        c.drawRect(full, _tilePaint(p.tiles.$1, p.scale, p.k, p.smooth));
      }
      c
        ..drawImage(src, Offset.zero, Paint()..blendMode = BlendMode.dstIn)
        ..restore();
    });
  }

  static ui.Image? _saltPepper(ui.Image src, SaltPepperFilter s, double res) {
    final d = s.density.clamp(0.0, 1.0);
    if (d <= 0) return null;
    final tile = NoiseTiles.uniform(s.seed);
    final scale = res * math.max(1, s.size);
    const k = 48.0;
    Paint specks(double threshold, bool white) => Paint()
      ..blendMode = BlendMode.srcATop
      ..filterQuality = FilterQuality.none
      ..colorFilter = ColorFilter.matrix([
        0, 0, 0, 0, white ? 255 : 0, //
        0, 0, 0, 0, white ? 255 : 0, //
        0, 0, 0, 0, white ? 255 : 0, //
        if (white) ...[
          k,
          0,
          0,
          0,
          -k * threshold * 255,
        ] else ...[
          -k,
          0,
          0,
          0,
          k * threshold * 255,
        ],
      ])
      ..shader = ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          scale, 0, 0, 0, //
          0, scale, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1, //
        ]),
        filterQuality: FilterQuality.none,
      );
    return _draw(src.width, src.height, (c) {
      final full = _full(src);
      c
        ..saveLayer(full, Paint())
        ..drawImage(src, Offset.zero, Paint())
        ..drawRect(full, specks(1 - d / 2, true))
        ..drawRect(full, specks(d / 2, false))
        ..restore();
    });
  }
}

class _NoisePass {
  _NoisePass(this.tiles, this.scale, this.k, {required this.smooth});
  final (ui.Image, ui.Image) tiles;
  final double scale;
  final double k;
  final bool smooth;
}

/// Noise tiles, generated once per kind (synchronously, by drawing each
/// grey level's pixels as one batch of points).
abstract final class NoiseTiles {
  static const size = 256;
  static final Map<(bool, bool, int), (ui.Image, ui.Image)> _signed = {};
  static final Map<int, ui.Image> _uniform = {};

  /// Positive and negative parts of signed noise in −1..1 (Gaussian: the
  /// standard normal / 3), per channel or [mono].
  static (ui.Image, ui.Image) signed(bool gaussian, bool mono, int seed) {
    final key = (gaussian, mono, seed);
    final hit = _signed[key];
    if (hit != null) return hit;
    if (_signed.length > 24) _signed.clear();
    final rnd = math.Random(seed * 7919 + (gaussian ? 1 : 0));
    final channels = mono ? 1 : 3;
    final values = List.generate(channels, (_) => Float32List(size * size));
    for (final v in values) {
      for (var i = 0; i < v.length; i++) {
        if (gaussian) {
          final u1 = math.max(1e-9, rnd.nextDouble()), u2 = rnd.nextDouble();
          final z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
          v[i] = (z / 3).clamp(-1.0, 1.0);
        } else {
          v[i] = rnd.nextDouble() * 2 - 1;
        }
      }
    }
    final pos = _tile(values, (x) => x > 0 ? x : 0);
    final neg = _tile(values, (x) => x < 0 ? -x : 0);
    return _signed[key] = (pos, neg);
  }

  /// Grey uniform noise 0..1.
  static ui.Image uniform(int seed) => _uniform[seed] ??= () {
    final rnd = math.Random(seed * 104729 + 3);
    final v = Float32List(size * size);
    for (var i = 0; i < v.length; i++) {
      v[i] = rnd.nextDouble();
    }
    return _tile([v], (x) => x);
  }();

  static ui.Image _tile(List<Float32List> channels, double Function(double) f) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    const s = size;
    c.drawRect(
      const Rect.fromLTWH(0, 0, s * 1.0, s * 1.0),
      Paint()..color = const Color(0xFF000000),
    );
    for (var ch = 0; ch < channels.length; ch++) {
      final buckets = List.generate(256, (_) => <double>[]);
      final v = channels[ch];
      for (var i = 0; i < v.length; i++) {
        final b = (f(v[i]) * 255).round().clamp(0, 255);
        if (b == 0) continue;
        buckets[b]
          ..add((i % s) + 0.5)
          ..add((i ~/ s) + 0.5);
      }
      for (var b = 1; b < 256; b++) {
        if (buckets[b].isEmpty) continue;
        final color = channels.length == 1
            ? Color.fromARGB(255, b, b, b)
            : Color.fromARGB(
                255,
                ch == 0 ? b : 0,
                ch == 1 ? b : 0,
                ch == 2 ? b : 0,
              );
        c.drawRawPoints(
          ui.PointMode.points,
          Float32List.fromList(buckets[b]),
          Paint()
            ..color = color
            ..blendMode = BlendMode.plus
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.square
            ..isAntiAlias = false,
        );
      }
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync(s, s);
    pic.dispose();
    return img;
  }
}
