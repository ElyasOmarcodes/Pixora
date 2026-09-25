import 'package:flutter/material.dart';

import '../../../document/effects/effect_registry.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

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

class FxColor extends FxControl {
  const FxColor(this.key, [this.label]);
  final String key;
  final String? label;
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
                      switch (c) {
                        FxSlider s => PixSlider(
                          label: s.label,
                          value: valueOf(s.key),
                          min: def.param(s.key)!.min,
                          max: def.param(s.key)!.max,
                          defaultValue: def.param(s.key)!.defaultNumber,
                          format:
                              s.format ??
                              (def.param(s.key)!.max <= 1 ? fxPercent : null),
                          onChanged: (v) => editor.setEffectParam(
                            id,
                            type,
                            s.key,
                            v,
                            live: true,
                          ),
                          onChangeEnd: (_) => editor.commit('effect'),
                        ),
                        FxColor col => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (col.label != null) PanelLabel(col.label!),
                            ColorStrip(
                              value: effect.color(
                                col.key,
                                def.param(col.key)!.defaultColor!,
                              ),
                              onChanged: (c, {required live}) {
                                if (c == null) return;
                                editor.setEffectParam(
                                  id,
                                  type,
                                  col.key,
                                  c.toARGB32(),
                                  live: live,
                                );
                              },
                            ),
                          ],
                        ),
                      },
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
  const _InOut({required this.builder});
  final Widget Function(BuildContext context, bool inner) builder;

  @override
  State<_InOut> createState() => _InOutState();
}

class _InOutState extends State<_InOut> {
  bool _inner = false;

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
  const ShadowPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _InOut(
      builder: (context, inner) => inner
          ? EffectEditor(
              key: const ValueKey('innerShadow'),
              editor: editor,
              layer: layer,
              type: 'innerShadow',
              title: l.innerShadow,
              controls: [
                FxSlider('distance', l.distance),
                FxSlider('angle', l.angle, format: fxDegrees),
                FxSlider('blur', l.blur),
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
                FxSlider('dx', l.offsetX),
                FxSlider('dy', l.offsetY),
                FxSlider('blur', l.blur),
                FxSlider('opacity', l.opacity),
                const FxColor('color'),
              ],
            ),
    );
  }
}

class GlowPanel extends StatelessWidget {
  const GlowPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _InOut(
      builder: (context, inner) => EffectEditor(
        key: ValueKey(inner),
        editor: editor,
        layer: layer,
        type: inner ? 'innerGlow' : 'glow',
        title: inner ? l.innerGlow : l.outerGlow,
        controls: [
          FxSlider('blur', l.size),
          FxSlider('opacity', l.intensity),
          const FxColor('color'),
        ],
      ),
    );
  }
}

/// Photoshop-style Bevel & Emboss.
class BevelPanel extends StatelessWidget {
  const BevelPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final effect = editor.effectOf(layer.id, 'bevel');
    final style = (effect?.number('style', 0) ?? 0).round();
    return EffectEditor(
      editor: editor,
      layer: layer,
      type: 'bevel',
      title: l.bevelEmboss,
      header: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final (i, label) in [
              (0, l.innerBevel),
              (1, l.outerBevel),
              (2, l.emboss),
              (3, l.pillowEmboss),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: ChoiceChip(
                  label: Text(label),
                  selected: style == i,
                  onSelected: (_) =>
                      editor.setEffectParam(layer.id, 'bevel', 'style', i),
                ),
              ),
          ],
        ),
      ),
      controls: [
        FxSlider('depth', l.depth),
        FxSlider('size', l.size),
        FxSlider('soften', l.soften),
        FxSlider('angle', l.lightAngle, format: fxDegrees),
        FxSlider('highlightOpacity', l.highlight),
        FxColor('highlight', l.highlightColor),
        FxSlider('shadowOpacity', l.shade),
        FxColor('shadowColor', l.shadeColor),
      ],
    );
  }
}

/// 3D: extrusion depth and colour plus perspective tilt.
class Extrude3DPanel extends StatelessWidget {
  const Extrude3DPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EffectEditor(
          editor: editor,
          layer: layer,
          type: 'extrude',
          title: l.extrude3d,
          controls: [
            FxSlider('depth', l.depth),
            FxSlider('angle', l.direction, format: fxDegrees),
            FxSlider('shade', l.shading),
            const FxColor('color'),
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
