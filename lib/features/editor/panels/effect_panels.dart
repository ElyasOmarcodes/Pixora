import 'package:flutter/material.dart';

import '../../../document/effects/effect_registry.dart';
import '../../../document/model/blend.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';
import 'bevel_panel.dart' show ContourRow, LightGlobe;
import '../../../document/render/bevel_engine.dart' show ContourPreset;

/// A control inside [EffectEditor].
sealed class FxControl {
  const FxControl();
}

class FxSlider extends FxControl {
  const FxSlider(this.key, this.label, {this.format});
  final String key;
  final String label;
  final String Function(double v)? format;
}

/// A blend-mode picker for an effect's `blend` param.
class FxBlend extends FxControl {
  const FxBlend(this.label, {this.key = 'blend'});
  final String key;
  final String label;
}

class FxColor extends FxControl {
  const FxColor(this.key, [this.label]);
  final String key;
  final String? label;
}

/// One of a few options (stored as its index).
class FxChoice extends FxControl {
  const FxChoice(this.key, this.options, {this.icons});
  final String key;
  final List<String> options;
  final List<IconData>? icons;
}

/// On / off (stored as 0 / 1).
class FxToggle extends FxControl {
  const FxToggle(this.key, this.label, {this.subtitle});
  final String key;
  final String label;
  final String? subtitle;
}

/// A "new random pattern" button for noise seeds.
class FxSeed extends FxControl {
  const FxSeed(this.label, {this.key = 'seed'});
  final String key;
  final String label;
}

/// Any widget, given the effect's values and a setter.
class FxCustom extends FxControl {
  const FxCustom(this.builder);
  final Widget Function(
    double Function(String key) valueOf,
    void Function(String key, Object value, {bool live}) set,
  )
  builder;
}

/// A section title between controls.
class FxLabel extends FxControl {
  const FxLabel(this.label);
  final String label;
}

/// Builds the widget for control [c] of an effect with definition [def].
/// [valueOf] reads a number, [colorOf] a colour; [set] writes a value
/// (live while dragging) and [commit] ends a drag.
Widget buildFxControl(
  BuildContext context,
  FxControl c,
  EffectDefinition def, {
  required double Function(String key) valueOf,
  required Color Function(String key) colorOf,
  required void Function(String key, Object value, {bool live}) set,
  required VoidCallback commit,
}) {
  switch (c) {
    case FxSlider s:
      final p = def.param(s.key)!;
      return PixSlider(
        label: s.label,
        value: valueOf(s.key).clamp(p.min, p.max),
        min: p.min,
        max: p.max,
        defaultValue: p.defaultNumber,
        format: s.format ?? (p.max <= 1 ? fxPercent : null),
        onChanged: (v) => set(s.key, v, live: true),
        onChangeEnd: (_) => commit(),
      );
    case FxBlend b:
      return BlendModeRow(
        label: b.label,
        value:
            PixBlendMode.values[valueOf(b.key)
                .round()
                .clamp(0, PixBlendMode.values.length - 1)],
        onChanged: (m) => set(b.key, m.index),
      );
    case FxColor col:
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (col.label != null) PanelLabel(col.label!),
          ColorStrip(
            value: colorOf(col.key),
            onChanged: (v, {required live}) {
              if (v == null) return;
              set(col.key, v.toARGB32(), live: live);
            },
          ),
        ],
      );
    case FxChoice ch:
      final v = valueOf(ch.key).round().clamp(0, ch.options.length - 1);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (var i = 0; i < ch.options.length; i++)
                ButtonSegment(
                  value: i,
                  icon: ch.icons == null ? null : Icon(ch.icons![i], size: 18),
                  label: Text(ch.options[i]),
                ),
            ],
            selected: {v},
            onSelectionChanged: (x) => set(ch.key, x.first),
          ),
        ),
      );
    case FxToggle t:
      return SwitchListTile.adaptive(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(t.label),
        subtitle: t.subtitle == null ? null : Text(t.subtitle!),
        value: valueOf(t.key) >= 1,
        onChanged: (v) => set(t.key, v ? 1 : 0),
      );
    case FxSeed sd:
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextButton.icon(
            onPressed: () => set(sd.key, (valueOf(sd.key).round() + 1) % 100),
            icon: const Icon(Icons.casino_rounded, size: 18),
            label: Text(sd.label),
          ),
        ),
      );
    case FxLabel lb:
      return PanelLabel(lb.label);
    case FxCustom cu:
      return cu.builder(valueOf, set);
  }
}

String fxPercent(double v) => '${(v * 100).round()}%';
String fxDegrees(double v) => '${v.round()}°';

/// On/off switch plus the controls of one effect type on a layer. The
/// effect is created with defaults when switched on and removed when off.
class EffectEditor extends StatelessWidget {
  const EffectEditor({
    super.key,
    required this.editor,
    required this.layer,
    required this.type,
    required this.title,
    required this.controls,
    this.header,
  });

  final EditorController editor;
  final Layer layer;
  final String type;
  final String title;
  final List<FxControl> controls;

  /// Extra widgets shown above the sliders while the effect is on.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final def = EffectRegistry.instance[type]!;
    final id = layer.id;
    final effect = editor.effectOf(id, type);
    final on = effect != null && effect.enabled;

    double valueOf(String key) =>
        effect?.number(key, def.param(key)!.defaultNumber) ??
        def.param(key)!.defaultNumber;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          value: on,
          onChanged: (v) {
            if (v) {
              editor.updateProps(
                id,
                (p) => p.copyWith(
                  effects: [
                    for (final e in p.effects)
                      if (e.type != type) e,
                    def.create(),
                  ],
                ),
                label: 'effect',
              );
            } else {
              editor.removeEffectType(id, type);
            }
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !on
              ? const SizedBox(width: double.infinity)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?header,
                    for (final c in controls)
                      buildFxControl(
                        context,
                        c,
                        def,
                        valueOf: valueOf,
                        colorOf: (k) => effect.color(
                          k,
                          def.param(k)?.defaultColor ?? const Color(0xFF000000),
                        ),
                        set: (k, v, {live = false}) =>
                            editor.setEffectParam(id, type, k, v, live: live),
                        commit: () => editor.commit('effect'),
                      ),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Outer / inner segmented header shared by shadow and glow.
class _InOut extends StatefulWidget {
  const _InOut({required this.builder, this.initialInner = false});
  final Widget Function(BuildContext context, bool inner) builder;
  final bool initialInner;

  @override
  State<_InOut> createState() => _InOutState();
}

class _InOutState extends State<_InOut> {
  late bool _inner = widget.initialInner;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.flip_to_back_rounded, size: 18),
                label: Text(l.outer),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.flip_to_front_rounded, size: 18),
                label: Text(l.inner),
              ),
            ],
            selected: {_inner},
            onSelectionChanged: (s) => setState(() => _inner = s.first),
          ),
        ),
        widget.builder(context, _inner),
      ],
    );
  }
}

class ShadowPanel extends StatelessWidget {
  const ShadowPanel({
    super.key,
    required this.editor,
    required this.layer,
    this.initialInner = false,
  });
  final EditorController editor;
  final Layer layer;
  final bool initialInner;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _InOut(
      initialInner: initialInner,
      builder: (context, inner) => inner
          ? EffectEditor(
              key: const ValueKey('innerShadow'),
              editor: editor,
              layer: layer,
              type: 'innerShadow',
              title: l.innerShadow,
              controls: [
                FxBlend(l.blendMode),
                FxSlider('distance', l.distance),
                FxSlider('angle', l.angle, format: fxDegrees),
                FxSlider('spread', l.choke, format: (v) => '${v.round()}%'),
                FxSlider('blur', l.size),
                FxSlider('opacity', l.opacity),
                const FxColor('color'),
              ],
            )
          : EffectEditor(
              key: const ValueKey('shadow'),
              editor: editor,
              layer: layer,
              type: 'shadow',
              title: l.dropShadow,
              controls: [
                FxBlend(l.blendMode),
                FxSlider('dx', l.offsetX),
                FxSlider('dy', l.offsetY),
                FxSlider('spread', l.spread, format: (v) => '${v.round()}%'),
                FxSlider('blur', l.size),
                FxSlider('opacity', l.opacity),
                const FxColor('color'),
              ],
            ),
    );
  }
}

/// Photoshop's Outer / Inner Glow with every option: Structure (blend
/// mode, opacity, noise, colour or gradient), Elements (technique,
/// source, spread / choke, size) and Quality (contour, anti-aliased,
/// range, jitter).
class GlowPanel extends StatelessWidget {
  const GlowPanel({
    super.key,
    required this.editor,
    required this.layer,
    this.initialInner = false,
  });
  final EditorController editor;
  final Layer layer;
  final bool initialInner;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String px(double v) => '${v.round()} px';
    String pct(double v) => '${v.round()}%';
    return _InOut(
      initialInner: initialInner,
      builder: (context, inner) {
        final type = inner ? 'innerGlow' : 'glow';
        final e = editor.effectOf(layer.id, type);
        final gradient = (e?.number('fill', 0) ?? 0) >= 1;
        return EffectEditor(
          key: ValueKey(inner),
          editor: editor,
          layer: layer,
          type: type,
          title: inner ? l.innerGlow : l.outerGlow,
          controls: [
            FxLabel(l.bevelStructure),
            FxBlend(l.blendMode),
            FxSlider('opacity', l.opacity),
            FxSlider('noise', l.noise, format: pct),
            FxChoice(
              'fill',
              [l.color, l.gradient],
              icons: const [Icons.circle, Icons.gradient_rounded],
            ),
            const FxColor('color'),
            if (gradient) ...[
              const FxColor('color2'),
              FxSlider('jitter', l.jitter, format: pct),
            ],
            FxLabel(l.elements),
            FxChoice('technique', [l.softer, l.precise]),
            if (inner) FxChoice('source', [l.sourceEdge, l.sourceCenter]),
            FxSlider('spread', inner ? l.choke : l.spread, format: pct),
            FxSlider('size', l.size, format: px),
            FxLabel(l.glowQuality),
            FxCustom(
              (valueOf, set) => ContourRow(
                value:
                    ContourPreset.values[valueOf('contour')
                        .round()
                        .clamp(0, ContourPreset.values.length - 1)],
                onChanged: (c) => set('contour', c.index),
              ),
            ),
            FxToggle('antiAlias', l.antiAliased),
            FxSlider('range', l.contourRange, format: pct),
          ],
        );
      },
    );
  }
}

/// Photoshop-style Bevel & Emboss.
/// Photoshop-style 3D extrusion: structure (depth, direction, taper,
/// twist), material (colour or the layer's own pixels, back shading) and
/// light (direction and height on a globe, intensity, ambient, gloss),
/// plus the perspective tilt.
class Extrude3DPanel extends StatelessWidget {
  const Extrude3DPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = editor.effectOf(layer.id, 'extrude');
    final layerMaterial = (e?.number('material', 0) ?? 0) >= 1;
    String px(double v) => '${v.round()} px';
    String pct(double v) => '${v.round()}%';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EffectEditor(
          editor: editor,
          layer: layer,
          type: 'extrude',
          title: l.extrude3d,
          controls: [
            FxLabel(l.bevelStructure),
            FxSlider('depth', l.depth, format: px),
            FxSlider('angle', l.direction, format: fxDegrees),
            FxSlider('scale', l.taper, format: pct),
            FxSlider('twist', l.twist, format: fxDegrees),
            FxLabel(l.material),
            FxChoice(
              'material',
              [l.color, l.layerTexture],
              icons: const [Icons.circle, Icons.texture_rounded],
            ),
            if (!layerMaterial) const FxColor('color'),
            FxSlider('shade', l.shading),
            FxLabel(l.light),
            FxCustom(
              (valueOf, set) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    LightGlobe(
                      angle: valueOf('lightAngle'),
                      altitude: valueOf('altitude'),
                      onChanged: (a, alt, {required live}) {
                        set('lightAngle', a, live: live);
                        set('altitude', alt, live: live);
                      },
                      onEnd: () => editor.commit('effect'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l.angle} ${valueOf('lightAngle').round()}°\n'
                        '${l.altitude} ${valueOf('altitude').round()}°',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            FxSlider('intensity', l.intensity, format: pct),
            FxSlider('ambient', l.ambientLight, format: pct),
            FxSlider('gloss', l.gloss, format: pct),
          ],
        ),
        if (layer is! GroupLayer) ...[
          const Divider(height: 12, indent: 20, endIndent: 20),
          TiltControls(editor: editor, layer: layer),
        ],
      ],
    );
  }
}

/// Colour fill (Photoshop's Color Overlay): fill, tint (keeps light and
/// shade) or multiply, with strength.
class ColorFillPanel extends StatelessWidget {
  const ColorFillPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = editor.effectOf(layer.id, 'colorFill');
    final mode = e?.number('mode', 0).round() ?? 0;
    return EffectEditor(
      editor: editor,
      layer: layer,
      type: 'colorFill',
      title: l.colorFill,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.format_color_fill_rounded, size: 18),
              label: Text(l.fillMode),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.gradient_rounded, size: 18),
              label: Text(l.tintMode),
            ),
            ButtonSegment(
              value: 2,
              icon: const Icon(Icons.layers_rounded, size: 18),
              label: Text(l.multiplyMode),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (v) =>
              editor.setEffectParam(layer.id, 'colorFill', 'mode', v.first),
        ),
      ),
      controls: [const FxColor('color'), FxSlider('amount', l.strength)],
    );
  }
}

/// 3D rotation (perspective tilt) sliders, shared by Rotate and 3D.
class TiltControls extends StatelessWidget {
  const TiltControls({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = layer.props.transform;
    void set({double? x, double? y, bool live = true}) => editor.updateProps(
      layer.id,
      (p) => p.copyWith(
        transform: p.transform.copyWith(tiltX: x, tiltY: y),
      ),
      live: live,
      label: 'rotate3d',
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(l.rotate3d),
        PixSlider(
          label: l.tiltX,
          value: t.tiltX,
          min: -70,
          max: 70,
          defaultValue: 0,
          format: fxDegrees,
          onChanged: (v) => set(x: v.roundToDouble()),
          onChangeEnd: (_) => editor.commit('rotate3d'),
        ),
        PixSlider(
          label: l.tiltY,
          value: t.tiltY,
          min: -70,
          max: 70,
          defaultValue: 0,
          format: fxDegrees,
          onChanged: (v) => set(y: v.roundToDouble()),
          onChangeEnd: (_) => editor.commit('rotate3d'),
        ),
        if (t.hasTilt)
          TextButton.icon(
            onPressed: () => set(x: 0, y: 0, live: false),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(l.reset),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
