import 'dart:ui';

/// Blend modes a layer can use to composite onto the layers beneath it.
///
/// Kept as our own enum (instead of storing [BlendMode] directly) so the
/// project format stays stable even if the engine's enum changes.
enum PixBlendMode {
  normal(BlendMode.srcOver),
  multiply(BlendMode.multiply),
  screen(BlendMode.screen),
  overlay(BlendMode.overlay),
  darken(BlendMode.darken),
  lighten(BlendMode.lighten),
  colorDodge(BlendMode.colorDodge),
  colorBurn(BlendMode.colorBurn),
  hardLight(BlendMode.hardLight),
  softLight(BlendMode.softLight),
  difference(BlendMode.difference),
  exclusion(BlendMode.exclusion),
  hue(BlendMode.hue),
  saturation(BlendMode.saturation),
  color(BlendMode.color),
  luminosity(BlendMode.luminosity);

  const PixBlendMode(this.engine);

  final BlendMode engine;
}
