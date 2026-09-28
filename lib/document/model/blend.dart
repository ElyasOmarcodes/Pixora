import 'dart:ui';

/// Photoshop-style groups the blend-mode picker is organised by.
enum BlendCategory { normal, darken, lighten, contrast, inversion, component }

/// Blend modes a layer can use to composite onto the layers beneath it —
/// all 27 of Photoshop's.
///
/// Kept as our own enum (instead of storing [BlendMode] directly) so the
/// project format stays stable. Effect params store the enum *index*, so
/// new modes are appended; [photoshopOrder] is the order shown to users.
///
/// Modes the GPU compositor does exactly use [engine]. The others (and
/// Soft Light, whose GPU formula differs from Photoshop's for dark
/// backdrops) are composited by a shader with Photoshop's formulas —
/// [shaderCode]; [engine] is then the closest built-in mode, used where a
/// shader can't run (layer-style parts).
enum PixBlendMode {
  normal(BlendMode.srcOver, BlendCategory.normal),

  darken(BlendMode.darken, BlendCategory.darken),
  multiply(BlendMode.multiply, BlendCategory.darken),
  colorBurn(BlendMode.colorBurn, BlendCategory.darken),

  lighten(BlendMode.lighten, BlendCategory.lighten),
  screen(BlendMode.screen, BlendCategory.lighten),
  colorDodge(BlendMode.colorDodge, BlendCategory.lighten),
  linearDodge(BlendMode.plus, BlendCategory.lighten),

  overlay(BlendMode.overlay, BlendCategory.contrast),
  softLight(BlendMode.softLight, BlendCategory.contrast, 11),
  hardLight(BlendMode.hardLight, BlendCategory.contrast),

  difference(BlendMode.difference, BlendCategory.inversion),
  exclusion(BlendMode.exclusion, BlendCategory.inversion),

  hue(BlendMode.hue, BlendCategory.component),
  saturation(BlendMode.saturation, BlendCategory.component),
  color(BlendMode.color, BlendCategory.component),
  luminosity(BlendMode.luminosity, BlendCategory.component),

  // Shader-composited modes (appended: effect params store indices).
  dissolve(BlendMode.srcOver, BlendCategory.normal, 12),
  linearBurn(BlendMode.multiply, BlendCategory.darken, 1),
  darkerColor(BlendMode.darken, BlendCategory.darken, 9),
  lighterColor(BlendMode.lighten, BlendCategory.lighten, 10),
  vividLight(BlendMode.hardLight, BlendCategory.contrast, 3),
  linearLight(BlendMode.hardLight, BlendCategory.contrast, 4),
  pinLight(BlendMode.hardLight, BlendCategory.contrast, 5),
  hardMix(BlendMode.hardLight, BlendCategory.contrast, 6),
  subtract(BlendMode.difference, BlendCategory.inversion, 7),
  divide(BlendMode.screen, BlendCategory.inversion, 8);

  const PixBlendMode(this.engine, this.category, [this.shaderCode]);

  final BlendMode engine;
  final BlendCategory category;

  /// The blend shader's mode number, for modes composited by shader.
  final int? shaderCode;

  /// Photoshop's menu order.
  static const photoshopOrder = [
    normal,
    dissolve,
    darken,
    multiply,
    colorBurn,
    linearBurn,
    darkerColor,
    lighten,
    screen,
    colorDodge,
    linearDodge,
    lighterColor,
    overlay,
    softLight,
    hardLight,
    vividLight,
    linearLight,
    pinLight,
    hardMix,
    difference,
    exclusion,
    subtract,
    divide,
    hue,
    saturation,
    color,
    luminosity,
  ];

  /// Modes a layer style part can use (composited by the GPU directly).
  static final engineOrder = [
    for (final m in photoshopOrder)
      if (m.shaderCode == null || m == softLight) m,
  ];

  /// Display name ("Linear Dodge (Add)", "Soft Light", …). Blend-mode names
  /// are kept in English on purpose: they are the industry vocabulary users
  /// search for in tutorials.
  String get label => switch (this) {
    linearDodge => 'Linear Dodge (Add)',
    _ =>
      name[0].toUpperCase() +
          name
              .substring(1)
              .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]}'),
  };
}
