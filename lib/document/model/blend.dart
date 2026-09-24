import 'dart:ui';

/// Photoshop-style groups the blend-mode picker is organised by.
enum BlendCategory { normal, darken, lighten, contrast, inversion, component }

/// Blend modes a layer can use to composite onto the layers beneath it,
/// in Photoshop's order.
///
/// Kept as our own enum (instead of storing [BlendMode] directly) so the
/// project format stays stable even if the engine's enum changes. Modes the
/// GPU compositor lacks natively (Linear Burn, Vivid/Linear/Pin Light, Hard
/// Mix, Subtract, Divide, Darker/Lighter Color) need shader-based
/// compositing and are on the roadmap; they slot in here when added.
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
  softLight(BlendMode.softLight, BlendCategory.contrast),
  hardLight(BlendMode.hardLight, BlendCategory.contrast),

  difference(BlendMode.difference, BlendCategory.inversion),
  exclusion(BlendMode.exclusion, BlendCategory.inversion),

  hue(BlendMode.hue, BlendCategory.component),
  saturation(BlendMode.saturation, BlendCategory.component),
  color(BlendMode.color, BlendCategory.component),
  luminosity(BlendMode.luminosity, BlendCategory.component);

  const PixBlendMode(this.engine, this.category);

  final BlendMode engine;
  final BlendCategory category;

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
