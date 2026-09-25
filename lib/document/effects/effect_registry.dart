import 'dart:ui';

import '../model/blend.dart';
import '../model/effect.dart';
import '../render/color_matrix.dart';
import '../render/filter_engine.dart';

/// adjust / filter: colour; blur / noise: pixel filters (applied before
/// the mask, like smart filters); style: layer styles.
enum EffectCategory { adjust, filter, style, blur, noise }

enum EffectParamKind { number, color }

/// Describes one tweakable value of an effect (drives sliders in the UI and
/// the argument schema exposed to automation / the AI agent).
class EffectParam {
  const EffectParam.number(
    this.key, {
    required this.min,
    required this.max,
    required double defaultValue,
    this.step,
  }) : kind = EffectParamKind.number,
       defaultNumber = defaultValue,
       defaultColor = null;

  const EffectParam.color(this.key, {required Color defaultValue})
    : kind = EffectParamKind.color,
      defaultColor = defaultValue,
      defaultNumber = 0,
      min = 0,
      max = 0,
      step = null;

  final String key;
  final EffectParamKind kind;
  final double min;
  final double max;
  final double? step;
  final double defaultNumber;
  final Color? defaultColor;

  Object get defaultValue =>
      kind == EffectParamKind.color ? defaultColor!.toARGB32() : defaultNumber;
}

/// A drop shadow / glow drawn beneath the layer content.
class ShadowSpec {
  const ShadowSpec({
    required this.offset,
    required this.blur,
    required this.color,
    this.blend = PixBlendMode.normal,
  });
  final Offset offset;
  final double blur;
  final Color color;

  /// How the shadow composites with what is beneath it (Photoshop's
  /// Blend Mode inside Drop Shadow; Multiply is the classic choice).
  final PixBlendMode blend;
}

/// Bevel & emboss, Photoshop style: a light and a dark edge derived from
/// the layer's shape.
enum BevelStyle { inner, outer, emboss, pillow }

class BevelSpec {
  const BevelSpec({
    required this.style,
    required this.depth,
    required this.size,
    required this.soften,
    required this.angle,
    required this.highlight,
    required this.shadow,
  });
  final BevelStyle style;

  /// Offset of the lit / shaded edges, px.
  final double depth;

  /// Blur of the edges, px.
  final double size;

  /// Extra softening blur, px.
  final double soften;

  /// Light direction, radians (0 = from the right, clockwise).
  final double angle;
  final Color highlight;
  final Color shadow;
}

/// Photoshop's Satin: two blurred, offset copies of the shape, their
/// difference coloured and laid inside the shape.
class SatinSpec {
  const SatinSpec({
    required this.blend,
    required this.color,
    required this.opacity,
    required this.angle,
    required this.distance,
    required this.size,
    required this.invert,
  });

  factory SatinSpec.of(LayerEffect e) => SatinSpec(
    blend:
        PixBlendMode.values[e
            .number('blend', 2)
            .round()
            .clamp(0, PixBlendMode.values.length - 1)],
    color: e.color('color', const Color(0xFF000000)),
    opacity: e.number('opacity', 0.5).clamp(0.0, 1.0),
    angle: e.number('angle', 19),
    distance: e.number('distance', 11).clamp(0.0, 1000.0),
    size: e.number('size', 14).clamp(0.0, 1000.0),
    invert: e.number('invert', 1) >= 1,
  );

  final PixBlendMode blend;
  final Color color;
  final double opacity;

  /// Degrees, Photoshop convention (counter-clockwise from the right).
  final double angle;
  final double distance;
  final double size;
  final bool invert;

  /// Offset of the first copy (document space); the second goes the
  /// other way.
  Offset get offset =>
      Offset.fromDirection(-angle * 3.141592653589793 / 180, distance / 2);
}

/// 3D extrusion: the layer is repeated along [angle] for [depth] px,
/// shaded from [color] to a darker tone at the back.
class ExtrudeSpec {
  const ExtrudeSpec({
    required this.depth,
    required this.angle,
    required this.color,
    required this.shade,
  });
  final double depth;
  final double angle;
  final Color color;

  /// 0..1 darkening towards the back.
  final double shade;
}

/// The behaviour behind an effect type.
///
/// An effect can contribute any combination of: a color matrix (fast,
/// chained with other matrices), a blur, or shadows. More advanced
/// effects (shaders, pixel kernels, AI-powered filters) can be added later
/// by extending this class with new hooks without touching the model.
class EffectDefinition {
  const EffectDefinition({
    required this.type,
    required this.category,
    this.params = const [],
    this.colorMatrix,
    this.blurSigma,
    this.shadow,
    this.inner,
    this.bevel,
    this.extrude,
    this.filter,
  });

  final String type;
  final EffectCategory category;
  final List<EffectParam> params;
  final List<double>? Function(LayerEffect e)? colorMatrix;
  final double Function(LayerEffect e)? blurSigma;
  final ShadowSpec? Function(LayerEffect e)? shadow;

  /// Shadow / glow drawn *inside* the layer's shape.
  final ShadowSpec? Function(LayerEffect e)? inner;
  final BevelSpec? Function(LayerEffect e)? bevel;
  final ExtrudeSpec? Function(LayerEffect e)? extrude;

  /// A pixel filter over the layer's own pixels ([box]: the layer's local
  /// box, for filters with a centre).
  final PixFilter? Function(LayerEffect e, Rect box)? filter;

  EffectParam? param(String key) {
    for (final p in params) {
      if (p.key == key) return p;
    }
    return null;
  }

  LayerEffect create([Map<String, Object> overrides = const {}]) => LayerEffect(
    type: type,
    params: {for (final p in params) p.key: p.defaultValue, ...overrides},
  );
}

/// Central catalogue of effect types. Register new ones at startup.
class EffectRegistry {
  EffectRegistry._();

  static final EffectRegistry instance = EffectRegistry._()..registerBuiltIns();

  final Map<String, EffectDefinition> _defs = {};

  Iterable<EffectDefinition> get all => _defs.values;

  Iterable<EffectDefinition> inCategory(EffectCategory c) =>
      _defs.values.where((d) => d.category == c);

  EffectDefinition? operator [](String type) => _defs[type];

  void register(EffectDefinition def) => _defs[def.type] = def;

  void registerBuiltIns() {
    double n(LayerEffect e, String k) => e.number(k, 0);

    register(
      EffectDefinition(
        type: 'brightness',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -1, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.brightness(n(e, 'value') * 0.5),
      ),
    );
    register(
      EffectDefinition(
        type: 'contrast',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -1, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.contrast(n(e, 'value') * 0.6),
      ),
    );
    register(
      EffectDefinition(
        type: 'saturation',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -1, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.saturation(n(e, 'value')),
      ),
    );
    register(
      EffectDefinition(
        type: 'hue',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -180, max: 180, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.hue(n(e, 'value')),
      ),
    );
    register(
      EffectDefinition(
        type: 'warmth',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -1, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.warmth(n(e, 'value')),
      ),
    );
    register(
      EffectDefinition(
        type: 'tint',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: -1, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.tint(n(e, 'value')),
      ),
    );
    register(
      EffectDefinition(
        type: 'fade',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: 0, max: 1, defaultValue: 0),
        ],
        colorMatrix: (e) => ColorMatrix.fade(n(e, 'value')),
      ),
    );
    register(
      EffectDefinition(
        type: 'blur',
        category: EffectCategory.adjust,
        params: const [
          EffectParam.number('value', min: 0, max: 60, defaultValue: 0),
        ],
        blurSigma: (e) => n(e, 'value'),
      ),
    );

    // Colour fill (Photoshop's Color Overlay): mode 0 = fill with the
    // colour, 1 = tint (colourise, keeps light and shade), 2 = multiply.
    register(
      EffectDefinition(
        type: 'colorFill',
        category: EffectCategory.style,
        params: const [
          EffectParam.color('color', defaultValue: Color(0xFFFF4D6D)),
          EffectParam.number('amount', min: 0, max: 1, defaultValue: 1),
          EffectParam.number('mode', min: 0, max: 2, defaultValue: 0, step: 1),
        ],
        colorMatrix: (e) => ColorMatrix.colorFill(
          e.color('color', const Color(0xFFFF4D6D)),
          e.number('amount', 1),
          e.number('mode', 0).round(),
        ),
      ),
    );

    // Filters: one-knob looks built from matrices, `amount` 0..1.
    EffectDefinition look(String type, List<double> m) => EffectDefinition(
      type: type,
      category: EffectCategory.filter,
      params: const [
        EffectParam.number('amount', min: 0, max: 1, defaultValue: 1),
      ],
      colorMatrix: (e) => ColorMatrix.mixWithIdentity(m, e.number('amount', 1)),
    );

    register(look('mono', ColorMatrix.grayscale));
    register(look('sepia', ColorMatrix.sepia));
    register(look('invert', ColorMatrix.invert));
    register(
      look(
        'vintage',
        ColorMatrix.concat(
          ColorMatrix.concat(
            ColorMatrix.sepia.toList(),
            ColorMatrix.mixWithIdentity(ColorMatrix.fade(1), 0.8),
          ),
          ColorMatrix.contrast(-0.1),
        ),
      ),
    );
    register(
      look(
        'vivid',
        ColorMatrix.concat(
          ColorMatrix.saturation(0.45),
          ColorMatrix.contrast(0.12),
        ),
      ),
    );
    register(
      look(
        'cool',
        ColorMatrix.concat(
          ColorMatrix.warmth(-0.8),
          ColorMatrix.saturation(0.05),
        ),
      ),
    );
    register(
      look(
        'warm',
        ColorMatrix.concat(
          ColorMatrix.warmth(0.8),
          ColorMatrix.saturation(0.1),
        ),
      ),
    );
    register(
      look(
        'noir',
        ColorMatrix.concat(
          ColorMatrix.grayscale.toList(),
          ColorMatrix.contrast(0.35),
        ),
      ),
    );
    register(
      look(
        'dramatic',
        ColorMatrix.concat(
          ColorMatrix.contrast(0.3),
          ColorMatrix.saturation(-0.25),
        ),
      ),
    );

    // Layer styles.
    register(
      EffectDefinition(
        type: 'shadow',
        category: EffectCategory.style,
        params: const [
          EffectParam.number('dx', min: -200, max: 200, defaultValue: 12),
          EffectParam.number('dy', min: -200, max: 200, defaultValue: 12),
          EffectParam.number('blur', min: 0, max: 100, defaultValue: 16),
          EffectParam.number('opacity', min: 0, max: 1, defaultValue: 0.55),
          EffectParam.color('color', defaultValue: Color(0xFF000000)),
          EffectParam.number(
            'blend',
            min: 0,
            max: 16,
            defaultValue: 0,
            step: 1,
          ),
        ],
        shadow: (e) => ShadowSpec(
          offset: Offset(e.number('dx', 12), e.number('dy', 12)),
          blur: e.number('blur', 16),
          color: e
              .color('color', const Color(0xFF000000))
              .withValues(alpha: e.number('opacity', 0.55).clamp(0.0, 1.0)),
          blend:
              PixBlendMode.values[e
                  .number('blend', 0)
                  .round()
                  .clamp(0, PixBlendMode.values.length - 1)],
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'glow',
        category: EffectCategory.style,
        params: const [
          EffectParam.number('blur', min: 0, max: 100, defaultValue: 24),
          EffectParam.number('opacity', min: 0, max: 1, defaultValue: 0.9),
          EffectParam.color('color', defaultValue: Color(0xFF7C9CFF)),
        ],
        shadow: (e) => ShadowSpec(
          offset: Offset.zero,
          blur: e.number('blur', 24),
          color: e
              .color('color', const Color(0xFF7C9CFF))
              .withValues(alpha: e.number('opacity', 0.9).clamp(0.0, 1.0)),
        ),
      ),
    );

    Color withOpacity(
      LayerEffect e,
      String key,
      Color c,
      String opKey,
      double op,
    ) => e.color(key, c).withValues(alpha: e.number(opKey, op).clamp(0.0, 1.0));
    Offset polar(double dist, double deg) =>
        Offset.fromDirection(deg * 3.141592653589793 / 180, dist);

    register(
      EffectDefinition(
        type: 'innerShadow',
        category: EffectCategory.style,
        params: const [
          EffectParam.number('distance', min: 0, max: 100, defaultValue: 8),
          EffectParam.number('angle', min: 0, max: 360, defaultValue: 45),
          EffectParam.number('blur', min: 0, max: 100, defaultValue: 10),
          EffectParam.number('opacity', min: 0, max: 1, defaultValue: 0.6),
          EffectParam.color('color', defaultValue: Color(0xFF000000)),
          EffectParam.number(
            'blend',
            min: 0,
            max: 16,
            defaultValue: 0,
            step: 1,
          ),
        ],
        inner: (e) => ShadowSpec(
          blend:
              PixBlendMode.values[e
                  .number('blend', 0)
                  .round()
                  .clamp(0, PixBlendMode.values.length - 1)],
          offset: polar(e.number('distance', 8), e.number('angle', 45)),
          blur: e.number('blur', 10),
          color: withOpacity(
            e,
            'color',
            const Color(0xFF000000),
            'opacity',
            0.6,
          ),
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'innerGlow',
        category: EffectCategory.style,
        params: const [
          EffectParam.number('blur', min: 0, max: 100, defaultValue: 18),
          EffectParam.number('opacity', min: 0, max: 1, defaultValue: 0.9),
          EffectParam.color('color', defaultValue: Color(0xFFFFF3A0)),
        ],
        inner: (e) => ShadowSpec(
          offset: Offset.zero,
          blur: e.number('blur', 18),
          color: withOpacity(
            e,
            'color',
            const Color(0xFFFFF3A0),
            'opacity',
            0.9,
          ),
        ),
      ),
    );
    // Bevel & Emboss: drawn by the renderer's bevel engine (a Photoshop
    // height-map bevel); these are its settings and defaults.
    register(
      const EffectDefinition(
        type: 'bevel',
        category: EffectCategory.style,
        params: [
          EffectParam.number('v', min: 2, max: 2, defaultValue: 2, step: 1),
          EffectParam.number('style', min: 0, max: 4, defaultValue: 0, step: 1),
          EffectParam.number(
            'technique',
            min: 0,
            max: 2,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number('depth', min: 1, max: 1000, defaultValue: 100),
          EffectParam.number(
            'direction',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number('size', min: 0, max: 250, defaultValue: 5),
          EffectParam.number('soften', min: 0, max: 16, defaultValue: 0),
          EffectParam.number('angle', min: -180, max: 180, defaultValue: 120),
          EffectParam.number('altitude', min: 0, max: 90, defaultValue: 30),
          EffectParam.number(
            'gloss',
            min: 0,
            max: 11,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number(
            'antiAlias',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number(
            'highlightMode',
            min: 0,
            max: 16,
            defaultValue: 5,
            step: 1,
          ),
          EffectParam.color('highlight', defaultValue: Color(0xFFFFFFFF)),
          EffectParam.number(
            'highlightOpacity',
            min: 0,
            max: 1,
            defaultValue: 0.75,
          ),
          EffectParam.number(
            'shadowMode',
            min: 0,
            max: 16,
            defaultValue: 2,
            step: 1,
          ),
          EffectParam.color('shadowColor', defaultValue: Color(0xFF000000)),
          EffectParam.number(
            'shadowOpacity',
            min: 0,
            max: 1,
            defaultValue: 0.75,
          ),
          EffectParam.number(
            'contourOn',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number(
            'contour',
            min: 0,
            max: 11,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number(
            'contourRange',
            min: 1,
            max: 100,
            defaultValue: 50,
          ),
          EffectParam.number(
            'textureOn',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number(
            'textureScale',
            min: 1,
            max: 1000,
            defaultValue: 100,
          ),
          EffectParam.number(
            'textureDepth',
            min: -1000,
            max: 1000,
            defaultValue: 100,
          ),
          EffectParam.number(
            'textureInvert',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
        ],
      ),
    );
    // Satin (layer style, drawn by the renderer): Photoshop's defaults.
    register(
      const EffectDefinition(
        type: 'satin',
        category: EffectCategory.style,
        params: [
          EffectParam.number(
            'blend',
            min: 0,
            max: 16,
            defaultValue: 2,
            step: 1,
          ),
          EffectParam.color('color', defaultValue: Color(0xFF000000)),
          EffectParam.number('opacity', min: 0, max: 1, defaultValue: 0.5),
          EffectParam.number('angle', min: -180, max: 180, defaultValue: 19),
          EffectParam.number('distance', min: 0, max: 250, defaultValue: 11),
          EffectParam.number('size', min: 0, max: 250, defaultValue: 14),
          EffectParam.number(
            'invert',
            min: 0,
            max: 1,
            defaultValue: 1,
            step: 1,
          ),
        ],
      ),
    );

    // Pixel filters (Filter ▸ Blur / Noise), stackable like smart filters.
    register(
      EffectDefinition(
        type: 'gaussianBlur',
        category: EffectCategory.blur,
        params: const [
          EffectParam.number('radius', min: 0, max: 250, defaultValue: 5),
        ],
        filter: (e, _) => GaussianBlurFilter(e.number('radius', 5)),
      ),
    );
    register(
      EffectDefinition(
        type: 'boxBlur',
        category: EffectCategory.blur,
        params: const [
          EffectParam.number('radius', min: 0, max: 500, defaultValue: 5),
        ],
        filter: (e, _) => BoxBlurFilter(e.number('radius', 5)),
      ),
    );
    register(
      EffectDefinition(
        type: 'motionBlur',
        category: EffectCategory.blur,
        params: const [
          EffectParam.number('angle', min: -90, max: 90, defaultValue: 0),
          EffectParam.number('distance', min: 1, max: 1000, defaultValue: 20),
        ],
        filter: (e, _) =>
            MotionBlurFilter(e.number('angle', 0), e.number('distance', 20)),
      ),
    );
    register(
      EffectDefinition(
        type: 'radialBlur',
        category: EffectCategory.blur,
        params: const [
          EffectParam.number('amount', min: 1, max: 100, defaultValue: 10),
          EffectParam.number(
            'method',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number('cx', min: 0, max: 1, defaultValue: 0.5),
          EffectParam.number('cy', min: 0, max: 1, defaultValue: 0.5),
        ],
        filter: (e, box) => RadialBlurFilter(
          amount: e.number('amount', 10),
          zoom: e.number('method', 0) >= 1,
          center: Offset(e.number('cx', 0.5), e.number('cy', 0.5)),
          box: box,
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'tiltShift',
        category: EffectCategory.blur,
        params: const [
          EffectParam.number('blur', min: 0, max: 100, defaultValue: 15),
          EffectParam.number('angle', min: -90, max: 90, defaultValue: 0),
          EffectParam.number('cy', min: 0, max: 1, defaultValue: 0.5),
          EffectParam.number('focus', min: 0, max: 0.5, defaultValue: 0.12),
          EffectParam.number(
            'transition',
            min: 0,
            max: 0.5,
            defaultValue: 0.18,
          ),
        ],
        filter: (e, box) => TiltShiftFilter(
          blur: e.number('blur', 15),
          angle: e.number('angle', 0),
          center: Offset(0.5, e.number('cy', 0.5)),
          focus: e.number('focus', 0.12),
          transition: e.number('transition', 0.18),
          box: box,
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'addNoise',
        category: EffectCategory.noise,
        params: const [
          EffectParam.number('amount', min: 0, max: 400, defaultValue: 12),
          EffectParam.number(
            'distribution',
            min: 0,
            max: 1,
            defaultValue: 0,
            step: 1,
          ),
          EffectParam.number('mono', min: 0, max: 1, defaultValue: 0, step: 1),
          EffectParam.number('seed', min: 0, max: 99, defaultValue: 0, step: 1),
        ],
        filter: (e, _) => AddNoiseFilter(
          amount: e.number('amount', 12) / 100,
          gaussian: e.number('distribution', 0) >= 1,
          mono: e.number('mono', 0) >= 1,
          seed: e.number('seed', 0).round(),
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'filmGrain',
        category: EffectCategory.noise,
        params: const [
          EffectParam.number('amount', min: 0, max: 100, defaultValue: 25),
          EffectParam.number('size', min: 1, max: 8, defaultValue: 1.5),
          EffectParam.number('roughness', min: 0, max: 100, defaultValue: 50),
          EffectParam.number('seed', min: 0, max: 99, defaultValue: 0, step: 1),
        ],
        filter: (e, _) => FilmGrainFilter(
          amount: e.number('amount', 25) / 100,
          size: e.number('size', 1.5),
          roughness: e.number('roughness', 50) / 100,
          seed: e.number('seed', 0).round(),
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'saltPepper',
        category: EffectCategory.noise,
        params: const [
          EffectParam.number('density', min: 0, max: 50, defaultValue: 4),
          EffectParam.number('size', min: 1, max: 8, defaultValue: 1),
          EffectParam.number('seed', min: 0, max: 99, defaultValue: 0, step: 1),
        ],
        filter: (e, _) => SaltPepperFilter(
          density: e.number('density', 4) / 100,
          size: e.number('size', 1),
          seed: e.number('seed', 0).round(),
        ),
      ),
    );
    register(
      EffectDefinition(
        type: 'extrude',
        category: EffectCategory.style,
        params: const [
          EffectParam.number('depth', min: 1, max: 200, defaultValue: 24),
          EffectParam.number('angle', min: 0, max: 360, defaultValue: 45),
          EffectParam.color('color', defaultValue: Color(0xFF1E3A8A)),
          EffectParam.number('shade', min: 0, max: 1, defaultValue: 0.5),
        ],
        extrude: (e) => ExtrudeSpec(
          depth: e.number('depth', 24),
          angle: e.number('angle', 45) * 3.141592653589793 / 180,
          color: e.color('color', const Color(0xFF1E3A8A)),
          shade: e.number('shade', 0.5).clamp(0.0, 1.0),
        ),
      ),
    );
  }
}
