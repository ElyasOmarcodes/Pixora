import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import '../model/warp.dart';

/// A pixel filter (Photoshop's Filter menu, applied as a smart filter):
/// it works on the layer's own pixels, before the layer mask and before
/// layer styles, so styles follow the filtered result.
sealed class PixFilter {
  const PixFilter();

  /// How far (document pixels) the filter can move pixels outwards.
  double get reach => 0;

  /// [reach] in layer units.
  double reachIn(FilterSpace space) => reach * space.maxPer;
}

/// Filter ▸ Blur ▸ Gaussian Blur. [radius] in document pixels: the
/// standard deviation of the Gaussian, as in Photoshop.
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

  /// In layer units: the zoom follows the layer box.
  @override
  double get reach => zoom ? box.longestSide * amount / 100 * 0.35 : 0;

  @override
  double reachIn(FilterSpace space) => reach;
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

/// Filter ▸ Sharpen ▸ Unsharp Mask (Sharpen is a small fixed one):
/// `src + amount · (src − blur(src, radius))`.
class UnsharpMaskFilter extends PixFilter {
  const UnsharpMaskFilter(this.amount, this.radius);

  /// 0..5 (0–500 %).
  final double amount;

  /// Document pixels.
  final double radius;
}

/// Filter ▸ Other ▸ High Pass: `50 % grey + (src − blur(src, radius))`.
class HighPassFilter extends PixFilter {
  const HighPassFilter(this.radius);
  final double radius;
}

/// Filter ▸ Stylize ▸ Emboss: grey relief from the luminance, lit from
/// [angle] degrees, [height] document pixels, [amount] 0..5.
class EmbossFilter extends PixFilter {
  const EmbossFilter(this.angle, this.height, this.amount);
  final double angle;
  final double height;
  final double amount;
  @override
  double get reach => height + 1;
}

/// Filter ▸ Pixelate ▸ Mosaic: square cells of [cell] document pixels.
class MosaicFilter extends PixFilter {
  const MosaicFilter(this.cell);
  final double cell;
}

/// Filter ▸ Other ▸ Maximum (lighter areas grow) or Minimum (darker areas
/// grow) by [radius] document pixels.
class MorphologyFilter extends PixFilter {
  const MorphologyFilter(this.radius, {required this.maximum});
  final double radius;
  final bool maximum;
  @override
  double get reach => maximum ? radius + 1 : 0;
}

/// Filter ▸ Other ▸ Offset: shifts the pixels, wrapping around the layer
/// box ([dx], [dy] in document pixels).
class OffsetFilter extends PixFilter {
  const OffsetFilter(this.dx, this.dy, this.box);
  final double dx, dy;
  final Rect box;
}

/// Lens Correction ▸ Vignette: darkens (amount < 0) or lightens the
/// corners of the layer box. [midpoint] 0…1: how far in the falloff starts.
class VignetteFilter extends PixFilter {
  const VignetteFilter(this.amount, this.midpoint, this.box);
  final double amount, midpoint;
  final Rect box;
}

/// Dispersion (Photoshop's "disintegration" technique — liquify smear,
/// splatter-brush masks — as one filter): past a gradient line the layer
/// breaks into particles that fly off in one direction, taking their own
/// pixels with them and leaving holes behind.
enum DispersionShape { square, circle, shard, splatter }

class DispersionFilter extends PixFilter {
  const DispersionFilter({
    required this.angle,
    required this.distance,
    required this.start,
    required this.transition,
    required this.density,
    required this.size,
    required this.sizeJitter,
    required this.shape,
    required this.spread,
    required this.erode,
    required this.stretch,
    required this.fade,
    required this.spin,
    this.turbulence = 0,
    required this.seed,
    required this.box,
  });

  /// Direction the particles fly, degrees counter-clockwise (0 = right).
  final double angle;

  /// How far the particles fly, document pixels.
  final double distance;

  /// Where the break begins along the direction, and how long the
  /// gradual part is (0..1 of the layer's extent along [angle]).
  final double start, transition;

  /// 0..1: how many pieces break away.
  final double density;

  /// Particle size, document pixels, and its random variation (0..1).
  final double size, sizeJitter;
  final DispersionShape shape;

  /// Random deviation from [angle], degrees.
  final double spread;

  /// 0..1: how much of the original dissolves where it breaks.
  final double erode;

  /// 0..1: particles smeared along their path (Liquify's streaks).
  final double stretch;

  /// 0..1: particles fade as they fly.
  final double fade;

  /// 0..1: random turning of the particles.
  final double spin;

  /// 0..1: particles weave sideways along their path.
  final double turbulence;
  final int seed;

  /// The layer's box (layer units) the gradient runs across.
  final Rect box;

  @override
  double get reach =>
      distance * (1 + turbulence * 0.4) + size * (3 + stretch * 6);
}

/// Filter ▸ Distort ▸ Twirl / Pinch / Spherize / Ripple, over the layer
/// box (mesh distortions, drawn on the GPU).
enum DistortKind { twirl, pinch, spherize, ripple }

class DistortFilter extends PixFilter {
  const DistortFilter(this.kind, this.amount, this.box, {this.size = 0.1});
  final DistortKind kind;

  /// Twirl: degrees (−999…999); pinch / spherize: −1…1; ripple: 0…1 of
  /// the box's short side.
  final double amount;

  /// Ripple wavelength, fraction of the short side.
  final double size;
  final Rect box;

  /// In layer units: the distortion follows the layer box.
  @override
  double reachIn(FilterSpace space) => 0;
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

/// How document pixels map to the layer's own units (the inverse of the
/// layer's scale and rotation): `local = [a b; c d] · doc`.
///
/// Like Photoshop's smart filters, every distance and angle a filter
/// takes is in document pixels, whatever the layer's size: a 10 px blur
/// on a photo scaled down to fit the canvas is 10 canvas pixels, not 10
/// of the photo's own pixels, and a motion blur keeps its angle when the
/// layer turns.
@immutable
class FilterSpace {
  const FilterSpace(this.a, this.b, this.c, this.d);
  static const identity = FilterSpace(1, 0, 0, 1);

  /// The inverse of a layer's `rotate(rotation) · scale(sx, sy)`.
  factory FilterSpace.inverseOf(double rotation, double sx, double sy) {
    final cs = math.cos(rotation), sn = math.sin(rotation);
    final ix = sx.abs() < 1e-6 ? 1e6 * sx.sign : 1 / sx;
    final iy = sy.abs() < 1e-6 ? 1e6 * sy.sign : 1 / sy;
    return FilterSpace(cs * ix, sn * ix, -sn * iy, cs * iy);
  }

  final double a, b, c, d;

  /// A document-space vector in layer units.
  Offset map(Offset v) => Offset(a * v.dx + b * v.dy, c * v.dx + d * v.dy);

  /// Layer units per document pixel along the layer's x / y axes.
  double get perX => math.sqrt(a * a + b * b);
  double get perY => math.sqrt(c * c + d * d);

  /// The most layer units one document pixel can span.
  double get maxPer => math.max(perX, perY);

  /// The average (area) scale.
  double get meanPer => math.sqrt(perX * perY);

  @override
  bool operator ==(Object other) =>
      other is FilterSpace &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d;

  @override
  int get hashCode => Object.hash(a, b, c, d);
}

/// Edit ▸ Transform ▸ Distort / Perspective / Warp: the layer's own
/// pixels bent by [geometry] over [box] (the layer's box, layer units).
/// Runs before the other filters, so styles follow the new shape.
class WarpFilter extends PixFilter {
  const WarpFilter(this.geometry, this.box);
  final WarpGeometry geometry;
  final Rect box;

  @override
  double get reach => geometry.reach * box.longestSide + 2;

  /// In layer units: the warp follows the layer box.
  @override
  double reachIn(FilterSpace space) => reach;
}

/// A filter with its Blending Options.
class FilterStep {
  const FilterStep(
    this.filter, {
    this.mode = BlendMode.srcOver,
    this.opacity = 1,
  });
  final PixFilter filter;
  final BlendMode mode;
  final double opacity;
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
  ///
  /// Filter distances are in document pixels; [space] maps them into the
  /// layer (see [FilterSpace]). [solid] (layer units) is a photo's own
  /// area: blurs repeat its edge pixels outwards and stay inside it.
  static ui.Image apply(
    ui.Image src,
    Rect rect,
    List<FilterStep> steps, {
    FilterSpace space = FilterSpace.identity,
    Rect? solid,
  }) {
    var img = src;
    final res = src.width / rect.width;
    // Image pixels per document pixel.
    final grain = res * space.meanPer;
    // A photo's own pixels (image pixels), when given.
    final box = solid == null
        ? null
        : Rect.fromLTRB(
            ((solid.left - rect.left) * res).ceilToDouble(),
            ((solid.top - rect.top) * res).ceilToDouble(),
            ((solid.right - rect.left) * res).floorToDouble(),
            ((solid.bottom - rect.top) * res).floorToDouble(),
          );
    for (final step in steps) {
      final f = step.filter;
      final spreads =
          box != null &&
          box.width >= 1 &&
          box.height >= 1 &&
          (f is GaussianBlurFilter ||
              f is BoxBlurFilter ||
              f is MotionBlurFilter ||
              f is RadialBlurFilter ||
              f is TiltShiftFilter);
      // Photoshop blurs a photo with its edge pixels repeated outwards, so
      // its edges stay solid instead of fading into a thin transparent
      // fringe; the result keeps the photo's bounds.
      final input = spreads ? _extend(img, box) : img;
      var next = switch (f) {
        GaussianBlurFilter g => _gaussian(
          input,
          g.radius * space.perX * res,
          g.radius * space.perY * res,
        ),
        BoxBlurFilter b => _box(input, b.radius, space, res),
        MotionBlurFilter m => _motion(input, m, space, res),
        RadialBlurFilter r => _radial(input, r, rect, res),
        TiltShiftFilter t => _tiltShift(input, t, rect, res, space.meanPer),
        AddNoiseFilter n => _addNoise(img, [
          _NoisePass(
            NoiseTiles.signed(n.gaussian, n.mono, n.seed),
            grain,
            n.gaussian
                ? n.amount * _levels * NoiseTiles.gaussianSpan
                : n.amount * _levels,
            smooth: false,
          ),
        ]),
        FilmGrainFilter g => _addNoise(img, [
          _NoisePass(
            NoiseTiles.signed(true, true, g.seed),
            grain * math.max(1, g.size),
            g.amount * 0.9 * (1 - g.roughness * 0.5),
            smooth: true,
          ),
          if (g.roughness > 0)
            _NoisePass(
              NoiseTiles.signed(true, true, g.seed + 7),
              grain,
              g.amount * 0.9 * g.roughness * 0.5,
              smooth: false,
            ),
        ]),
        SaltPepperFilter s => _saltPepper(img, s, grain),
        WarpFilter w => _warp(img, w, rect, res),
        UnsharpMaskFilter u => _unsharp(
          img,
          u.amount,
          u.radius * space.meanPer * res,
        ),
        HighPassFilter h => _highPass(img, h.radius * space.meanPer * res),
        EmbossFilter e => _emboss(img, e, space, res),
        MosaicFilter m => _mosaic(img, m.cell * space.meanPer * res),
        MorphologyFilter m => _morphology(
          img,
          m.radius * space.perX * res,
          m.radius * space.perY * res,
          m.maximum,
        ),
        OffsetFilter o => _offset(img, o, space, rect, res),
        VignetteFilter v => _vignette(img, v, rect, res),
        DispersionFilter d => _dispersion(img, d, space, rect, res),
        DistortFilter d => _distort(img, d, rect, res),
      };
      if (!identical(input, img)) input.dispose();
      if (next == null) continue;
      if (spreads) {
        final blurred = next;
        next = _clip(blurred, box);
        blurred.dispose();
      }
      // Photoshop's filter Blending Options: the result laid over the
      // unfiltered pixels with a mode and opacity.
      if (step.mode != BlendMode.srcOver || step.opacity < 1) {
        final filtered = next;
        final before = img;
        next = _draw(img.width, img.height, (c) {
          c
            ..drawImage(before, Offset.zero, Paint())
            ..drawImage(
              filtered,
              Offset.zero,
              Paint()
                ..blendMode = step.mode
                ..color = Color.fromRGBO(0, 0, 0, step.opacity.clamp(0.0, 1.0)),
            );
        });
        filtered.dispose();
      }
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

  /// [src] with everything outside [box] filled by its nearest edge pixel.
  static ui.Image _extend(ui.Image src, Rect box) {
    final inner = _draw(
      box.width.toInt(),
      box.height.toInt(),
      (c) => c.drawImageRect(
        src,
        box,
        Offset.zero & box.size,
        Paint()..filterQuality = FilterQuality.none,
      ),
    );
    final out = _draw(src.width, src.height, (c) {
      c.drawRect(
        _full(src),
        Paint()
          ..shader = ImageShader(
            inner,
            TileMode.clamp,
            TileMode.clamp,
            Float64List.fromList([
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              box.left, box.top, 0, 1, //
            ]),
            filterQuality: FilterQuality.none,
          ),
      );
    });
    inner.dispose();
    return out;
  }

  /// Bends [src] (covering [rect], layer units) through a fine triangle
  /// mesh: each vertex sits where the warp sends it and samples where it
  /// came from.
  static ui.Image? _warp(ui.Image src, WarpFilter f, Rect rect, double res) {
    final g = f.geometry;
    if (g.isIdentity) return null;
    final b = f.box;
    // A finer mesh for Bézier warps; perspective is smooth enough at 24.
    final n = g.hasMesh ? 40 : 24;
    final pos = Float32List((n + 1) * (n + 1) * 2);
    final tex = Float32List((n + 1) * (n + 1) * 2);
    var k = 0;
    for (var i = 0; i <= n; i++) {
      final v = i / n;
      for (var j = 0; j <= n; j++) {
        final u = j / n;
        final to = g.map(u, v);
        pos[k] = (b.left + to.dx * b.width - rect.left) * res;
        pos[k + 1] = (b.top + to.dy * b.height - rect.top) * res;
        tex[k] = (b.left + u * b.width - rect.left) * res;
        tex[k + 1] = (b.top + v * b.height - rect.top) * res;
        k += 2;
      }
    }
    final idx = Uint16List(n * n * 6);
    var t = 0;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final a = i * (n + 1) + j, c = a + n + 1;
        idx
          ..[t++] = a
          ..[t++] = a + 1
          ..[t++] = c
          ..[t++] = a + 1
          ..[t++] = c + 1
          ..[t++] = c;
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: tex,
      indices: idx,
    );
    final out = _draw(src.width, src.height, (c) {
      c.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..shader = ImageShader(
            src,
            TileMode.decal,
            TileMode.decal,
            Float64List.fromList([
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              0, 0, 0, 1, //
            ]),
            filterQuality: FilterQuality.medium,
          ),
      );
    });
    vertices.dispose();
    return out;
  }

  /// [src] cleared outside [box].
  static ui.Image _clip(ui.Image src, Rect box) =>
      _draw(src.width, src.height, (c) {
        c
          ..clipRect(box)
          ..drawImage(src, Offset.zero, Paint());
      });

  /// Photoshop's Add Noise: at Amount 100 % Uniform noise moves each
  /// channel by up to ±256 levels (12.5 % → ±32), and Gaussian noise has
  /// that as its standard deviation, so its tails reach past the range.
  static const _levels = 256 / 255;

  static ui.Image? _gaussian(ui.Image src, double sigma, [double? sigmaY]) {
    final sy = sigmaY ?? sigma;
    if (sigma < 0.05 && sy < 0.05) return null;
    return _draw(src.width, src.height, (c) {
      c.saveLayer(
        _full(src),
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: math.max(0, sigma),
            sigmaY: math.max(0, sy),
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

  /// A (2r+1)² square of the document: two even averages along the
  /// document's axes, as seen in the layer.
  static ui.Image? _box(ui.Image src, double r, FilterSpace space, double res) {
    final len = 2 * r + 1;
    final h = _lineDoc(src, space.map(const Offset(1, 0)) * res, len);
    final v = _lineDoc(h ?? src, space.map(const Offset(0, 1)) * res, len);
    if (v != null && h != null) h.dispose();
    return v ?? h;
  }

  /// An even average over [length] document pixels along [step] (one
  /// document pixel, in image pixels).
  static ui.Image? _lineDoc(ui.Image src, Offset step, double length) {
    final d = step.distance;
    if (d < 1e-9) return null;
    return _line(src, step / d, length * d);
  }

  /// Photoshop's angle is on the canvas (counter-clockwise), whatever the
  /// layer's rotation or flip.
  static ui.Image? _motion(
    ui.Image src,
    MotionBlurFilter m,
    FilterSpace space,
    double res,
  ) {
    final a = m.angle * math.pi / 180;
    final dir = space.map(Offset(math.cos(a), -math.sin(a))) * res;
    return _lineDoc(src, dir, m.distance);
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
    double per,
  ) {
    final sigma = t.blur * per * res;
    if (sigma < 0.05) return null;
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
    // Photoshop's Blur Gallery grows the blur smoothly with distance:
    // several blur levels, each blended into the next over its stretch of
    // the transition, so no step between them shows.
    const levels = 8;
    final images = [
      for (var i = 0; i < levels; i++)
        i == 0 ? src : _gaussian(src, sigma * i / (levels - 1)) ?? src,
    ];
    final step = tr / (levels - 1);
    // Level i weighs 1 at distance f + i·step from the band's middle,
    // falling to 0 at the neighbouring levels' distances: the weights add
    // up to 1 everywhere, so the levels are summed (a sharp level laid
    // over blurred ones would leave their halos around transparent
    // content such as text).
    final far = f + tr + 1;
    ui.Gradient weight(int i) {
      // (distance, weight) breakpoints on one side, mirrored.
      final pts = <(double, double)>[
        if (i == 0) ...[
          (0, 1),
          (f, 1),
          (f + step, 0),
        ] else ...[
          (0, 0),
          (f + step * (i - 1), 0),
          (f + step * i, 1),
          if (i < levels - 1) (f + step * (i + 1), 0) else (far, 1),
        ],
      ];
      if (pts.last.$1 < far) pts.add((far, pts.last.$2));
      final colors = <Color>[], stops = <double>[];
      for (final (d, w) in pts.reversed) {
        colors.add(Color.fromRGBO(255, 255, 255, w));
        stops.add(0.5 - d / (2 * far));
      }
      for (final (d, w) in pts) {
        colors.add(Color.fromRGBO(255, 255, 255, w));
        stops.add(0.5 + d / (2 * far));
      }
      return ui.Gradient.linear(
        center - n * far,
        center + n * far,
        colors,
        stops,
      );
    }

    final out = _draw(src.width, src.height, (c) {
      final full = _full(src);
      for (var i = 0; i < levels; i++) {
        c
          ..saveLayer(full, Paint()..blendMode = BlendMode.plus)
          ..drawImage(images[i], Offset.zero, Paint())
          ..drawRect(
            full,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = weight(i),
          )
          ..restore();
      }
    });
    for (final img in images) {
      if (!identical(img, src)) img.dispose();
    }
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

  // ------------------------------------------------ Photoshop filters

  /// The positive and negative parts of `a − b`, per channel:
  /// `max(a, b) − b` and `b − min(a, b)` (lighten / darken, then
  /// difference) — signed arithmetic with blend modes, on the GPU.
  static (ui.Image, ui.Image) _signed(ui.Image a, ui.Image b) {
    ui.Image part(BlendMode pick) => _draw(a.width, a.height, (c) {
      c
        ..drawImage(a, Offset.zero, Paint())
        ..drawImage(b, Offset.zero, Paint()..blendMode = pick)
        ..drawImage(b, Offset.zero, Paint()..blendMode = BlendMode.difference);
    });
    return (part(BlendMode.lighten), part(BlendMode.darken));
  }

  /// `base + k·pos − k·neg`, keeping [alpha]'s transparency.
  static ui.Image _addParts(
    ui.Image base,
    ui.Image pos,
    ui.Image neg,
    double k,
    ui.Image alpha,
  ) => _draw(base.width, base.height, (c) {
    final full = _full(base);
    c
      ..saveLayer(full, Paint())
      ..saveLayer(full, Paint()..colorFilter = _invert)
      ..drawImage(base, Offset.zero, Paint()..colorFilter = _invertOpaque)
      ..drawImage(
        neg,
        Offset.zero,
        Paint()
          ..blendMode = BlendMode.plus
          ..colorFilter = _scale(k),
      )
      ..restore()
      ..drawImage(
        pos,
        Offset.zero,
        Paint()
          ..blendMode = BlendMode.plus
          ..colorFilter = _scale(k),
      )
      ..drawImage(alpha, Offset.zero, Paint()..blendMode = BlendMode.dstIn)
      ..restore();
  });

  static ui.Image? _unsharp(ui.Image src, double amount, double sigma) {
    if (amount <= 0.001 || sigma < 0.05) return null;
    final blur = _gaussian(src, sigma)!;
    final (pos, neg) = _signed(src, blur);
    final out = _addParts(src, pos, neg, amount, src);
    for (final i in [blur, pos, neg]) {
      i.dispose();
    }
    return out;
  }

  static ui.Image _grey(ui.Image src, {bool luminance = false}) =>
      _draw(src.width, src.height, (c) {
        if (luminance) {
          // Opaque: height = luminance × alpha, so a layer's outline makes
          // relief too (transparent pixels would break the arithmetic).
          c.drawRect(_full(src), Paint()..color = const Color(0xFF000000));
          c.drawImage(
            src,
            Offset.zero,
            Paint()
              ..colorFilter = const ColorFilter.matrix([
                0.299, 0.587, 0.114, 0, 0, //
                0.299, 0.587, 0.114, 0, 0, //
                0.299, 0.587, 0.114, 0, 0, //
                0, 0, 0, 1, 0, //
              ]),
          );
        } else {
          c.drawRect(_full(src), Paint()..color = const Color(0xFF808080));
        }
      });

  static ui.Image? _highPass(ui.Image src, double sigma) {
    if (sigma < 0.05) return null;
    final blur = _gaussian(src, sigma)!;
    final (pos, neg) = _signed(src, blur);
    final grey = _grey(src);
    final out = _addParts(grey, pos, neg, 1, src);
    for (final i in [blur, pos, neg, grey]) {
      i.dispose();
    }
    return out;
  }

  static ui.Image? _emboss(
    ui.Image src,
    EmbossFilter e,
    FilterSpace space,
    double res,
  ) {
    if (e.amount <= 0.001 || e.height <= 0) return null;
    final a = e.angle * math.pi / 180;
    final d = space.map(Offset(math.cos(a), -math.sin(a))) * (e.height * res);
    final lum = _grey(src, luminance: true);
    ui.Image shifted(Offset o) => _draw(src.width, src.height, (c) {
      // Edge pixels repeat, so the relief has no false rim.
      c.drawRect(
        _full(src),
        Paint()
          ..shader = ImageShader(
            lum,
            TileMode.clamp,
            TileMode.clamp,
            Float64List.fromList([
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              o.dx, o.dy, 0, 1, //
            ]),
          ),
      );
    });
    final lit = shifted(d / 2), shade = shifted(-d / 2);
    final (pos, neg) = _signed(lit, shade);
    final grey = _grey(src);
    final out = _addParts(grey, pos, neg, e.amount, src);
    for (final i in [lum, lit, shade, pos, neg, grey]) {
      i.dispose();
    }
    return out;
  }

  static ui.Image? _mosaic(ui.Image src, double cell) {
    if (cell < 1.5) return null;
    // Average each cell by halving (every step a 2×2 box average), then
    // blow the cells back up without smoothing.
    final cw = math.max(1, (src.width / cell).ceil());
    final ch = math.max(1, (src.height / cell).ceil());
    var img = src;
    while (img.width > cw * 2 || img.height > ch * 2) {
      final w = math.max(cw, (img.width / 2).ceil());
      final h = math.max(ch, (img.height / 2).ceil());
      final cur = img;
      img = _draw(w, h, (c) {
        c.drawImageRect(
          cur,
          _full(cur),
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..filterQuality = FilterQuality.low,
        );
      });
      if (!identical(cur, src)) cur.dispose();
    }
    final small = img;
    final cells = _draw(cw, ch, (c) {
      c.drawImageRect(
        small,
        _full(small),
        Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()),
        Paint()..filterQuality = FilterQuality.low,
      );
    });
    if (!identical(small, src)) small.dispose();
    final out = _draw(src.width, src.height, (c) {
      c.drawImageRect(
        cells,
        _full(cells),
        Rect.fromLTWH(0, 0, cw * cell, ch * cell),
        Paint()..filterQuality = FilterQuality.none,
      );
    });
    cells.dispose();
    return out;
  }

  static ui.Image? _morphology(
    ui.Image src,
    double rx,
    double ry,
    bool maximum,
  ) {
    if (rx < 0.5 && ry < 0.5) return null;
    return _draw(src.width, src.height, (c) {
      c
        ..saveLayer(
          _full(src),
          Paint()
            ..imageFilter = maximum
                ? ui.ImageFilter.dilate(radiusX: rx, radiusY: ry)
                : ui.ImageFilter.erode(radiusX: rx, radiusY: ry),
        )
        ..drawImage(src, Offset.zero, Paint())
        ..restore();
    });
  }

  /// Photoshop's dispersion look, built the way designers build it by
  /// hand: past the break line the layer is cut into cells; a cell whose
  /// random value falls under the break level (the gradient on the mask)
  /// is knocked out of the body — leaving a ragged, hard-edged gap — and
  /// flies off carrying its own pixels, joined by fine dust. Most pieces
  /// stay close to the body and big chunks break into smaller ones as
  /// they go, so the cloud is dense at the edge and thins out.
  static ui.Image? _dispersion(
    ui.Image src,
    DispersionFilter f,
    FilterSpace space,
    Rect rect,
    double res,
  ) {
    if (f.density <= 0 && f.erode <= 0) return null;
    final b = Rect.fromLTRB(
      (f.box.left - rect.left) * res,
      (f.box.top - rect.top) * res,
      (f.box.right - rect.left) * res,
      (f.box.bottom - rect.top) * res,
    );
    if (b.width < 1 || b.height < 1) return null;
    // The direction in image pixels (y down), and one document pixel's
    // length along it.
    final a = f.angle * math.pi / 180;
    final v = space.map(Offset(math.cos(a), -math.sin(a))) * res;
    final perDoc = v.distance;
    if (perDoc < 1e-9) return null;
    final dir = v / perDoc;
    final nx = -dir.dy, ny = dir.dx;
    final grain = space.meanPer * res;
    // Extent of the box along the direction.
    var pMin = double.infinity, pMax = -double.infinity;
    for (final c in [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight]) {
      final p = c.dx * dir.dx + c.dy * dir.dy;
      pMin = math.min(pMin, p);
      pMax = math.max(pMax, p);
    }
    final span = math.max(1.0, pMax - pMin);
    final start = f.start.clamp(0.0, 1.0);
    final trans = math.max(0.005, f.transition.clamp(0.0, 1.0));
    double breakAt(double x, double y) {
      final t = ((x * dir.dx + y * dir.dy - pMin) / span - start) / trans;
      final k = t.clamp(0.0, 1.0);
      return k * k * (3 - 2 * k);
    }

    final dist = f.distance * perDoc;
    var cell = math.max(1.5, f.size * grain);
    // Keep the cell count bounded on huge layers.
    final est =
        b.width * b.height * (1 - start).clamp(0.02, 1.0) / (cell * cell);
    if (est > 36000) cell *= math.sqrt(est / 36000);
    final seed = f.seed * 101.37 + 7.1;
    // A stable per-cell random number: the pattern stays put while any
    // slider moves.
    double h(int i, int j, int k) {
      final x =
          math.sin(i * 12.9898 + j * 78.233 + k * 37.719 + seed) * 43758.5453;
      return x - x.floorToDouble();
    }

    final pieces = _TriBuffer(colors: true);
    final holes = _TriBuffer();
    final stretch = f.stretch.clamp(0.0, 1.0) * 6;
    final spread = f.spread * math.pi / 180;
    final base = math.atan2(dir.dy, dir.dx);
    final outline = <Offset>[];

    /// [outline] ← the shape of piece (i, j, k), radius [r] around (0,0).
    void shapeOf(int i, int j, int k, double r, {bool upright = false}) {
      outline.clear();
      // Squares stay upright unless Spin turns them.
      final turn = upright || f.shape == DispersionShape.square
          ? 0.0
          : h(i, j, k + 11) * math.pi * 2;
      switch (f.shape) {
        case DispersionShape.square:
          for (var q = 0; q < 4; q++) {
            final an = turn + math.pi / 4 + q * math.pi / 2;
            outline.add(Offset(math.cos(an), math.sin(an)) * (r * math.sqrt2));
          }
        case DispersionShape.circle:
          for (var q = 0; q < 10; q++) {
            final an = q * math.pi / 5;
            outline.add(Offset(math.cos(an), math.sin(an)) * r);
          }
        case DispersionShape.shard:
          final n = 3 + (h(i, j, k + 12) * 2).floor();
          for (var q = 0; q < n; q++) {
            final an = turn + (q + h(i, j, k + 20 + q) * 0.7) * math.pi * 2 / n;
            final rr = r * (0.55 + 0.75 * h(i, j, k + 30 + q));
            outline.add(Offset(math.cos(an), math.sin(an)) * rr);
          }
        case DispersionShape.splatter:
          for (var q = 0; q < 9; q++) {
            final an = turn + (q + h(i, j, k + 20 + q) * 0.5) * math.pi * 2 / 9;
            final rr = r * (0.62 + 0.5 * h(i, j, k + 30 + q));
            outline.add(Offset(math.cos(an), math.sin(an)) * rr);
          }
      }
    }

    /// Adds the piece in [outline] cut at [at] and landed at [to], turned
    /// by [spin] and scaled by [scale].
    void fly(
      Offset at,
      Offset to,
      double spin,
      double scale,
      double mx,
      double my,
      double alpha,
    ) {
      final ct = math.cos(spin) * scale, st = math.sin(spin) * scale;
      final color = (alpha.clamp(0.0, 1.0) * 255).round() << 24 | 0xFFFFFF;
      for (var t = 1; t + 1 < outline.length; t++) {
        for (final o in [outline[0], outline[t], outline[t + 1]]) {
          var px = o.dx * ct - o.dy * st, py = o.dx * st + o.dy * ct;
          final along = px * mx + py * my;
          px += mx * along * stretch;
          py += my * along * stretch;
          pieces.add(to.dx + px, to.dy + py, at.dx + o.dx, at.dy + o.dy, color);
        }
      }
    }

    final cols = (b.width / cell).ceil() + 1;
    final rows = (b.height / cell).ceil() + 1;
    var n = 0;
    for (var j = 0; j < rows && n < 60000; j++) {
      for (var i = 0; i < cols; i++) {
        final cx = b.left + (i + (h(i, j, 1) - 0.5) * 0.8) * cell;
        final cy = b.top + (j + (h(i, j, 2) - 0.5) * 0.8) * cell;
        final g = breakAt(cx, cy);
        if (g <= 0 || h(i, j, 3) >= g) continue;
        final at = Offset(cx, cy);
        // The gap it leaves: a bit bigger than the cell, so neighbours
        // overlap into ragged holes and a fully broken area clears.
        // Gaps lag behind the break: early on pieces peel off an intact
        // body (the Liquify copy of the hand-made effect), and holes only
        // take over as the break completes.
        final bite = g * g * g;
        if (h(i, j, 4) < f.erode * bite) {
          shapeOf(i, j, 0, cell * (0.5 + 0.25 * bite), upright: true);
          for (var t = 1; t + 1 < outline.length; t++) {
            for (final o in [outline[0], outline[t], outline[t + 1]]) {
              holes.add(cx + o.dx, cy + o.dy);
            }
          }
        }
        // The chunk itself, and a few grains of dust.
        for (var k = 0; k < 3; k++) {
          final dust = k > 0;
          if (h(i, j, 5 + k) >= f.density * (dust ? 0.75 : 1)) continue;
          final kk = 40 * (k + 1);
          // Most pieces stay near the body.
          final fl = h(i, j, kk + 1);
          final travel =
              dist * math.pow(fl, dust ? 1.4 : 2.6) * (0.2 + 0.8 * g);
          final th = base + spread * (h(i, j, kk + 2) * 2 - 1);
          final mx = math.cos(th), my = math.sin(th);
          final far = dist > 0 ? travel / dist : 0.0;
          // Turbulence: a sideways wave along the path.
          final wave =
              f.turbulence *
              travel *
              0.35 *
              math.sin(far * math.pi * 2.2 + h(i, j, kk + 3) * 6.3);
          final to = Offset(
            cx + mx * travel + nx * wave,
            cy + my * travel + ny * wave,
          );
          // Chunks: from crumbs to big pieces; they crumble as they fly.
          final r = h(i, j, kk + 4);
          final big = 0.35 + 1.65 * r * r * r;
          var scale = dust ? 0.18 + 0.3 * r : 1 + (big - 1) * f.sizeJitter;
          scale *= 1 - 0.45 * far;
          final radius = cell * 0.62;
          shapeOf(i, j, kk, radius);
          final spin = f.spin * (h(i, j, kk + 5) * 2 - 1) * math.pi;
          final alpha = (1 - f.fade * far) * (0.8 + 0.2 * h(i, j, kk + 6));
          fly(at, to, spin, scale, mx, my, alpha);
          n++;
        }
      }
    }
    // Past the gradient everything is gone (as far as [erode] asks).
    final p1 = dir * (pMin + span * math.min(1, start + trans));
    final p0 = dir * (pMin + span * math.min(1, start + trans * 0.85));
    final out = _draw(src.width, src.height, (c) {
      // The body with its gaps …
      c
        ..saveLayer(null, Paint())
        ..drawImage(src, Offset.zero, Paint());
      if (holes.count > 0) {
        final gaps = holes.build();
        c.drawVertices(
          gaps,
          BlendMode.srcOver,
          Paint()..blendMode = BlendMode.dstOut,
        );
        gaps.dispose();
      }
      c
        ..drawRect(
          _full(src),
          Paint()
            ..blendMode = BlendMode.dstOut
            ..shader = ui.Gradient.linear(p0, p1, [
              const Color(0x00000000),
              Color.fromRGBO(0, 0, 0, f.erode.clamp(0.0, 1.0)),
            ]),
        )
        ..restore();
      // … and the pieces over it: those that barely moved still crowd
      // the broken edge, as in the hand-made effect.
      if (pieces.count > 0) {
        final verts = pieces.build();
        c.drawVertices(
          verts,
          BlendMode.modulate,
          Paint()
            ..filterQuality = FilterQuality.low
            ..shader = ImageShader(
              src,
              TileMode.decal,
              TileMode.decal,
              Float64List.fromList([
                1, 0, 0, 0, //
                0, 1, 0, 0, //
                0, 0, 1, 0, //
                0, 0, 0, 1, //
              ]),
              filterQuality: FilterQuality.low,
            ),
        );
        verts.dispose();
      }
    });
    return out;
  }

  static ui.Image? _vignette(
    ui.Image src,
    VignetteFilter v,
    Rect rect,
    double res,
  ) {
    if (v.amount == 0) return null;
    final b = Rect.fromLTRB(
      (v.box.left - rect.left) * res,
      (v.box.top - rect.top) * res,
      (v.box.right - rect.left) * res,
      (v.box.bottom - rect.top) * res,
    );
    if (b.width < 1 || b.height < 1) return null;
    final k = v.amount.abs().clamp(0.0, 1.0);
    final edge = v.amount < 0
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final start = v.midpoint.clamp(0.0, 0.95);
    // An elliptical falloff over the box that reaches the corners: drawn
    // in a space where the box is (-1,-1)…(1,1), corners at radius √2.
    final shader = ui.Gradient.radial(
      Offset.zero,
      math.sqrt2,
      [
        edge.withValues(alpha: 0),
        edge.withValues(alpha: 0),
        edge.withValues(alpha: k),
      ],
      [0, start, 1],
    );
    return _draw(src.width, src.height, (c) {
      c
        ..drawImage(src, Offset.zero, Paint())
        ..save()
        ..translate(b.center.dx, b.center.dy)
        ..scale(b.width / 2, b.height / 2)
        // Only where there are pixels, like Photoshop.
        ..drawRect(
          const Rect.fromLTRB(-1, -1, 1, 1),
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.srcATop,
        )
        ..restore();
    });
  }

  static ui.Image? _offset(
    ui.Image src,
    OffsetFilter o,
    FilterSpace space,
    Rect rect,
    double res,
  ) {
    if (o.dx == 0 && o.dy == 0) return null;
    final b = Rect.fromLTRB(
      (o.box.left - rect.left) * res,
      (o.box.top - rect.top) * res,
      (o.box.right - rect.left) * res,
      (o.box.bottom - rect.top) * res,
    );
    if (b.width < 1 || b.height < 1) return null;
    final shift = space.map(Offset(o.dx, o.dy)) * res;
    final tile = _draw(b.width.ceil(), b.height.ceil(), (c) {
      c.drawImageRect(src, b, Offset.zero & b.size, Paint());
    });
    final out = _draw(src.width, src.height, (c) {
      c
        ..clipRect(b)
        ..drawRect(
          b,
          Paint()
            ..shader = ImageShader(
              tile,
              TileMode.repeated,
              TileMode.repeated,
              Float64List.fromList([
                1, 0, 0, 0, //
                0, 1, 0, 0, //
                0, 0, 1, 0, //
                b.left + shift.dx, b.top + shift.dy, 0, 1, //
              ]),
            ),
        );
    });
    tile.dispose();
    return out;
  }

  /// Twirl, Pinch, Spherize and Ripple: a fine mesh over the layer box
  /// whose vertices stay put and sample where the distortion says.
  static ui.Image? _distort(
    ui.Image src,
    DistortFilter f,
    Rect rect,
    double res,
  ) {
    if (f.amount == 0) return null;
    final b = f.box;
    final c0 = b.center;
    final r0 = b.shortestSide / 2;
    Offset source(Offset p) {
      final v = p - c0;
      final d = v.distance / r0;
      switch (f.kind) {
        case DistortKind.twirl:
          if (d >= 1) return p;
          final t = f.amount * math.pi / 180 * (1 - d);
          final cs = math.cos(t), sn = math.sin(t);
          return c0 + Offset(v.dx * cs - v.dy * sn, v.dx * sn + v.dy * cs);
        case DistortKind.pinch:
          if (d >= 1 || d == 0) return p;
          // Photoshop-like: positive squeezes towards the centre.
          final k = math.pow(math.sin(math.pi / 2 * d), -f.amount).toDouble();
          return c0 + v * k.clamp(0.0, 1 / math.max(d, 1e-6));
        case DistortKind.spherize:
          if (d >= 1 || d == 0) return p;
          // A sphere seen from the front: magnified middle (positive) or
          // squeezed (negative).
          final sphere = math.asin(d) / (math.pi / 2);
          final k = 1 + f.amount * (sphere / d - 1);
          return c0 + v * k;
        case DistortKind.ripple:
          final a = f.amount * r0 * 2 * 0.1;
          final wl = math.max(2.0, f.size * r0 * 2);
          return p +
              Offset(
                a * math.sin(2 * math.pi * p.dy / wl),
                a * math.sin(2 * math.pi * p.dx / wl),
              );
      }
    }

    const n = 48;
    final pos = Float32List((n + 1) * (n + 1) * 2);
    final tex = Float32List((n + 1) * (n + 1) * 2);
    var k = 0;
    for (var i = 0; i <= n; i++) {
      for (var j = 0; j <= n; j++) {
        final p = Offset(
          rect.left + rect.width * j / n,
          rect.top + rect.height * i / n,
        );
        final s = source(p);
        pos[k] = (p.dx - rect.left) * res;
        pos[k + 1] = (p.dy - rect.top) * res;
        tex[k] = (s.dx - rect.left) * res;
        tex[k + 1] = (s.dy - rect.top) * res;
        k += 2;
      }
    }
    final idx = Uint16List(n * n * 6);
    var t = 0;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final a = i * (n + 1) + j, c = a + n + 1;
        idx
          ..[t++] = a
          ..[t++] = a + 1
          ..[t++] = c
          ..[t++] = a + 1
          ..[t++] = c + 1
          ..[t++] = c;
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: tex,
      indices: idx,
    );
    final out = _draw(src.width, src.height, (c) {
      c.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..shader = ImageShader(
            src,
            TileMode.decal,
            TileMode.decal,
            Float64List.fromList([
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              0, 0, 0, 1, //
            ]),
            filterQuality: FilterQuality.medium,
          ),
      );
    });
    vertices.dispose();
    return out;
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
  /// Large enough that the repeat is never noticed.
  static const size = 512;

  /// Gaussian tiles hold z / [gaussianSpan] (z standard normal), so tails
  /// reach 4 σ.
  static const gaussianSpan = 4.0;
  static final Map<(bool, bool, int), (ui.Image, ui.Image)> _signed = {};
  static final Map<int, ui.Image> _uniform = {};

  /// Positive and negative parts of signed noise in −1..1 (Gaussian: the
  /// standard normal / [gaussianSpan]), per channel or [mono].
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
          v[i] = (z / gaussianSpan).clamp(-1.0, 1.0);
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

/// Growable triangle vertex data for [ui.Vertices].
class _TriBuffer {
  _TriBuffer({this.colors = false});
  final bool colors;
  var _pos = Float32List(3000);
  var _tex = Float32List(0);
  var _col = Int32List(0);
  int count = 0;

  void add(double x, double y, [double tx = 0, double ty = 0, int c = 0]) {
    if (count * 2 + 2 > _pos.length) {
      _pos = Float32List(_pos.length * 2)..setAll(0, _pos);
      if (colors) {
        _tex = Float32List(_pos.length)..setAll(0, _tex);
        _col = Int32List(_pos.length ~/ 2)..setAll(0, _col);
      }
    }
    if (colors && _tex.length < _pos.length) {
      _tex = Float32List(_pos.length)..setAll(0, _tex);
      _col = Int32List(_pos.length ~/ 2)..setAll(0, _col);
    }
    _pos[count * 2] = x;
    _pos[count * 2 + 1] = y;
    if (colors) {
      _tex[count * 2] = tx;
      _tex[count * 2 + 1] = ty;
      _col[count] = c;
    }
    count++;
  }

  ui.Vertices build() => ui.Vertices.raw(
    ui.VertexMode.triangles,
    Float32List.sublistView(_pos, 0, count * 2),
    textureCoordinates: colors
        ? Float32List.sublistView(_tex, 0, count * 2)
        : null,
    colors: colors ? Int32List.sublistView(_col, 0, count) : null,
  );
}
