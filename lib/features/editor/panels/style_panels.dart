import 'package:flutter/material.dart';

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
