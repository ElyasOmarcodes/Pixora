import 'package:flutter/material.dart';

import '../../../document/effects/effect_registry.dart';
import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'canvas_panels.dart';
import 'panel_common.dart';

PixFill? _fillOf(Layer l) => switch (l) {
  TextLayer t => t.fill,
  ShapeLayer s => s.fill,
  RasterLayer _ || GroupLayer _ => null,
};

Layer _withFill(Layer l, PixFill f) => switch (l) {
  TextLayer t => t.copyWith(fill: f),
  ShapeLayer s => s.copyWith(fill: f),
  RasterLayer _ || GroupLayer _ => l,
};

/// Fill color or gradient for text and shapes.
class FillPanel extends StatelessWidget {
  const FillPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fill = _fillOf(layer);
    if (fill == null) return const SizedBox.shrink();
    void set(PixFill f, {bool live = false}) => live
        ? editor.previewLayer(layer.id, (x) => _withFill(x, f))
        : editor.updateLayer(layer.id, (x) => _withFill(x, f), label: 'fill');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(l.solid),
        ColorStrip(
          value: fill.isGradient ? null : fill.primary,
          onChanged: (c, {required live}) {
            if (c != null) set(PixFill.color(c), live: live);
          },
        ),
        PanelLabel(l.gradient),
        GradientStrip(selected: fill, onSelected: set),
        if (fill.isGradient && fill.kind == FillKind.linear)
          PixSlider(
            label: l.angle,
            value: fill.angle,
            min: 0,
            max: 360,
            defaultValue: 135,
            format: (v) => '${v.round()}°',
            onChanged: (v) => set(fill.copyWith(angle: v), live: true),
            onChangeEnd: (_) => editor.commit('fill'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Outline width and color for text and shapes.
class StrokePanel extends StatelessWidget {
  const StrokePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (width, color) = switch (layer) {
      TextLayer t => (t.strokeWidth, t.strokeColor),
      ShapeLayer s => (s.strokeWidth, s.strokeColor),
      RasterLayer _ || GroupLayer _ => (0.0, Colors.black),
    };
    Layer apply(Layer x, {double? w, Color? c}) => switch (x) {
      TextLayer t => t.copyWith(strokeWidth: w, strokeColor: c),
      ShapeLayer s => s.copyWith(strokeWidth: w, strokeColor: c),
      RasterLayer _ || GroupLayer _ => x,
    };
    final maxWidth = layer is TextLayer
        ? (layer as TextLayer).fontSize * 0.4
        : 80.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixSlider(
          label: l.strokeWidth,
          value: width,
          min: 0,
          max: maxWidth.clamp(10, 200),
          defaultValue: 0,
          onChanged: (v) =>
              editor.previewLayer(layer.id, (x) => apply(x, w: v)),
          onChangeEnd: (_) => editor.commit('stroke'),
        ),
        ColorStrip(
          value: color,
          onChanged: (c, {required live}) {
            if (c == null) return;
            // Picking a color with no stroke yet gives it a visible width.
            final w = width == 0 ? (maxWidth * 0.12).clamp(2.0, 20.0) : null;
            live
                ? editor.previewLayer(layer.id, (x) => apply(x, c: c, w: w))
                : editor.updateLayer(
                    layer.id,
                    (x) => apply(x, c: c, w: w),
                    label: 'stroke',
                  );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Drop shadow and glow layer styles.
class ShadowPanel extends StatefulWidget {
  const ShadowPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<ShadowPanel> createState() => _ShadowPanelState();
}

class _ShadowPanelState extends State<ShadowPanel> {
  String _type = 'shadow';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editor = widget.editor;
    final id = widget.layer.id;
    final def = EffectRegistry.instance[_type]!;
    final effect = editor.effectOf(id, _type);
    final enabled = effect != null;

    double valueOf(String key) =>
        effect?.number(key, def.param(key)!.defaultNumber) ??
        def.param(key)!.defaultNumber;

    Widget slider(String key, String label) {
      final p = def.param(key)!;
      return PixSlider(
        label: label,
        value: valueOf(key),
        min: p.min,
        max: p.max,
        defaultValue: p.defaultNumber,
        format: p.max <= 1 ? (v) => '${(v * 100).round()}%' : null,
        onChanged: (v) => editor.setEffectParam(id, _type, key, v, live: true),
        onChangeEnd: (_) => editor.commit('effect'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'shadow', label: Text(l.shadow)),
                  ButtonSegment(value: 'glow', label: Text(l.glow)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const Spacer(),
              Switch.adaptive(
                value: enabled,
                onChanged: (on) => on
                    ? editor.updateProps(
                        id,
                        (p) =>
                            p.copyWith(effects: [...p.effects, def.create()]),
                        label: 'effect',
                      )
                    : editor.removeEffectType(id, _type),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: !enabled
              ? const SizedBox(width: double.infinity)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_type == 'shadow') ...[
                      slider('dx', l.offsetX),
                      slider('dy', l.offsetY),
                    ],
                    slider('blur', l.blur),
                    slider('opacity', l.intensity),
                    ColorStrip(
                      value: effect.color(
                        'color',
                        def.param('color')!.defaultColor!,
                      ),
                      onChanged: (c, {required live}) {
                        if (c == null) return;
                        editor.setEffectParam(
                          id,
                          _type,
                          'color',
                          c.toARGB32(),
                          live: live,
                        );
                      },
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
