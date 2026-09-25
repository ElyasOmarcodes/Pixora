import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../document/effects/effect_registry.dart';
import '../../document/model/effect.dart';
import '../../document/model/layer.dart';
import '../../l10n/app_localizations.dart';
import 'editor_scope.dart';
import 'panels/effect_panels.dart';
import 'panels/panel_common.dart';

/// Sections of the Layer effects page.
enum FxGroup { blur, noise, style, color }

/// One entry of the Layer effects page.
class FxEntry {
  const FxEntry(this.key, this.group, this.icon, {this.panel, this.inner});

  /// The effect type it adds (or, for stroke / adjust / filters, a name).
  final String key;
  final FxGroup group;
  final IconData icon;

  /// The panel that edits it; null for pixel filters (edited by id).
  final ToolPanel? panel;

  /// Opens [panel] on its Inner tab (shadow, glow).
  final bool? inner;

  bool get isFilter => panel == null;
}

const fxCatalog = <FxEntry>[
  FxEntry('gaussianBlur', FxGroup.blur, Icons.blur_on_rounded),
  FxEntry('boxBlur', FxGroup.blur, Icons.crop_square_rounded),
  FxEntry('motionBlur', FxGroup.blur, Icons.fast_forward_rounded),
  FxEntry('radialBlur', FxGroup.blur, Icons.cyclone_rounded),
  FxEntry('tiltShift', FxGroup.blur, Icons.vertical_align_center_rounded),
  FxEntry('addNoise', FxGroup.noise, Icons.grain_rounded),
  FxEntry('filmGrain', FxGroup.noise, Icons.movie_filter_rounded),
  FxEntry('saltPepper', FxGroup.noise, Icons.scatter_plot_rounded),
  FxEntry(
    'shadow',
    FxGroup.style,
    Icons.blur_circular_rounded,
    panel: ToolPanel.shadow,
    inner: false,
  ),
  FxEntry(
    'innerShadow',
    FxGroup.style,
    Icons.brightness_3_rounded,
    panel: ToolPanel.shadow,
    inner: true,
  ),
  FxEntry(
    'glow',
    FxGroup.style,
    Icons.flare_rounded,
    panel: ToolPanel.glow,
    inner: false,
  ),
  FxEntry(
    'innerGlow',
    FxGroup.style,
    Icons.wb_iridescent_rounded,
    panel: ToolPanel.glow,
    inner: true,
  ),
  FxEntry('satin', FxGroup.style, Icons.waves_rounded, panel: ToolPanel.satin),
  FxEntry(
    'bevel',
    FxGroup.style,
    Icons.view_in_ar_rounded,
    panel: ToolPanel.bevel,
  ),
  FxEntry(
    'stroke',
    FxGroup.style,
    Icons.border_style_rounded,
    panel: ToolPanel.stroke,
  ),
  FxEntry(
    'colorFill',
    FxGroup.style,
    Icons.format_color_fill_rounded,
    panel: ToolPanel.colorFill,
  ),
  FxEntry(
    'extrude',
    FxGroup.style,
    Icons.layers_rounded,
    panel: ToolPanel.extrude,
  ),
  FxEntry('adjust', FxGroup.color, Icons.tune_rounded, panel: ToolPanel.adjust),
  FxEntry(
    'filters',
    FxGroup.color,
    Icons.auto_awesome_rounded,
    panel: ToolPanel.filters,
  ),
];

String fxGroupLabel(AppLocalizations l, FxGroup g) => switch (g) {
  FxGroup.blur => l.blur,
  FxGroup.noise => l.noise,
  FxGroup.style => l.layerStyles,
  FxGroup.color => l.color,
};

/// Display name of an effect type (or catalogue key).
String fxLabel(AppLocalizations l, String key) => switch (key) {
  'gaussianBlur' => l.gaussianBlur,
  'boxBlur' => l.boxBlur,
  'motionBlur' => l.motionBlur,
  'radialBlur' => l.radialBlur,
  'tiltShift' => l.tiltShift,
  'addNoise' => l.addNoise,
  'filmGrain' => l.filmGrain,
  'saltPepper' => l.saltPepper,
  'shadow' => l.dropShadow,
  'innerShadow' => l.innerShadow,
  'glow' => l.outerGlow,
  'innerGlow' => l.innerGlow,
  'satin' => l.satin,
  'bevel' => l.bevelEmboss,
  'stroke' => l.stroke,
  'colorFill' => l.colorFill,
  'extrude' => l.extrude3d,
  'adjust' => l.adjust,
  'filters' => l.filters,
  _ => effectLabel(l, key),
};

IconData fxIcon(String type) {
  for (final e in fxCatalog) {
    if (e.key == type) return e.icon;
  }
  final cat = EffectRegistry.instance[type]?.category;
  return switch (cat) {
    EffectCategory.adjust => Icons.tune_rounded,
    EffectCategory.filter => Icons.auto_awesome_rounded,
    _ => Icons.auto_fix_high_rounded,
  };
}

/// Where an existing effect of [type] is edited (null: by id, in the
/// pixel-filter panel), and on which tab.
(ToolPanel?, bool) panelForEffect(String type) {
  for (final e in fxCatalog) {
    if (e.key == type) return (e.panel, e.inner ?? false);
  }
  return switch (EffectRegistry.instance[type]?.category) {
    EffectCategory.adjust => (ToolPanel.adjust, false),
    EffectCategory.filter => (ToolPanel.filters, false),
    _ => (null, false),
  };
}

/// Starting values sized to the layer, so the first look is clear on
/// big photos and small stickers alike (distances in layer pixels).
Map<String, Object> suggestedParams(String type, Layer layer, Size size) {
  final side = math.max(1.0, math.max(size.width, size.height));
  double px(double f, double min, double max) =>
      (side * f).clamp(min, max).roundToDouble();
  return switch (type) {
    'gaussianBlur' => {'radius': px(0.012, 2, 250)},
    'boxBlur' => {'radius': px(0.012, 2, 500)},
    'motionBlur' => {'distance': px(0.06, 8, 1000)},
    'tiltShift' => {'blur': px(0.015, 3, 100)},
    'filmGrain' => {'size': (side / 900).clamp(1.0, 8.0)},
    'saltPepper' => {'size': (side / 900).clamp(1.0, 8.0).roundToDouble()},
    'glow' || 'innerGlow' => {'size': px(0.03, 5, 250)},
    _ => const {},
  };
}

/// Stronger settings for the thumbnails on the Layer effects page.
Map<String, Object> previewParams(String type, Size size) {
  final side = math.max(1.0, math.max(size.width, size.height));
  return switch (type) {
    'gaussianBlur' => {'radius': side * 0.03},
    'boxBlur' => {'radius': side * 0.03},
    'motionBlur' => {'distance': side * 0.16, 'angle': 20},
    'radialBlur' => {'amount': 30},
    'tiltShift' => {'blur': side * 0.03, 'focus': 0.08},
    'addNoise' => {'amount': 80},
    'filmGrain' => {'amount': 90, 'size': side / 60},
    'saltPepper' => {'density': 16, 'size': side / 60},
    'shadow' => {'dx': side * 0.05, 'dy': side * 0.05, 'blur': side * 0.05},
    'innerShadow' => {'distance': side * 0.05, 'blur': side * 0.06},
    // Photoshop's pale Screen glow vanishes on light thumbnails.
    'glow' => {
      'size': side * 0.1,
      'color': 0xFFFFB300,
      'blend': 0,
      'opacity': 1,
    },
    'innerGlow' => {
      'size': side * 0.12,
      'color': 0xFFFFF59D,
      'blend': 0,
      'opacity': 1,
    },
    'satin' => {'distance': side * 0.1, 'size': side * 0.08},
    'bevel' => {'size': side * 0.05},
    'extrude' => {'depth': side * 0.06},
    _ => const {},
  };
}

/// Controls of a pixel filter's panel.
List<FxControl> filterControls(AppLocalizations l, String type) {
  String px(double v) => '${v.toStringAsFixed(v < 10 ? 1 : 0)} px';
  String pct(double v) => '${v.round()}%';
  String frac(double v) => '${(v * 100).round()}%';
  return switch (type) {
    'gaussianBlur' => [FxSlider('radius', l.radius, format: px)],
    'boxBlur' => [FxSlider('radius', l.radius, format: px)],
    'motionBlur' => [
      FxSlider('angle', l.angle, format: fxDegrees),
      FxSlider('distance', l.distance, format: px),
    ],
    'radialBlur' => [
      FxChoice(
        'method',
        [l.spin, l.zoom],
        icons: const [Icons.rotate_right_rounded, Icons.zoom_out_map_rounded],
      ),
      FxSlider('amount', l.amount, format: (v) => '${v.round()}'),
      FxSlider('cx', l.centerX, format: frac),
      FxSlider('cy', l.centerY, format: frac),
    ],
    'tiltShift' => [
      FxSlider('blur', l.blur, format: px),
      FxSlider('cy', l.position, format: frac),
      FxSlider('angle', l.angle, format: fxDegrees),
      FxSlider('focus', l.focusArea, format: frac),
      FxSlider('transition', l.transition, format: frac),
    ],
    'addNoise' => [
      FxSlider('amount', l.amount, format: pct),
      FxChoice('distribution', [l.uniform, l.gaussian]),
      FxToggle('mono', l.monochromatic),
      FxSeed(l.randomize),
    ],
    'filmGrain' => [
      FxSlider('amount', l.amount, format: pct),
      FxSlider('size', l.size, format: px),
      FxSlider('roughness', l.roughness, format: pct),
      FxSeed(l.randomize),
    ],
    'saltPepper' => [
      FxSlider('density', l.density, format: pct),
      FxSlider('size', l.size, format: px),
      FxSeed(l.randomize),
    ],
    _ => const [],
  };
}

/// Every effect on [layer] the user can switch or edit, in Photoshop's
/// order for the layers list: filters (smart filters), then styles.
List<LayerEffect> listedEffects(Layer layer) => [
  for (final e in layer.props.effects)
    if (EffectRegistry.instance[e.type] != null) e,
];
