import 'dart:ui';

import '../model/effect.dart';
import '../render/color_matrix.dart';

enum EffectCategory { adjust, filter, style }

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
  });
  final Offset offset;
  final double blur;
  final Color color;
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
  });

  final String type;
  final EffectCategory category;
  final List<EffectParam> params;
  final List<double>? Function(LayerEffect e)? colorMatrix;
  final double Function(LayerEffect e)? blurSigma;
  final ShadowSpec? Function(LayerEffect e)? shadow;

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
        ],
        shadow: (e) => ShadowSpec(
          offset: Offset(e.number('dx', 12), e.number('dy', 12)),
          blur: e.number('blur', 16),
          color: e
              .color('color', const Color(0xFF000000))
              .withValues(alpha: e.number('opacity', 0.55).clamp(0.0, 1.0)),
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
  }
}
