import 'package:flutter/material.dart';

import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/text_span_style.dart';
import '../widgets/rich_text_field.dart';
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

/// Fill color or gradient for text and shapes. Text can also be coloured
/// in parts: choose "part of text" and select the words.
class FillPanel extends StatefulWidget {
  const FillPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<FillPanel> createState() => _FillPanelState();
}

class _FillPanelState extends State<FillPanel> {
  TextRange? _range;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editor = widget.editor;
    final layer = widget.layer;
    final fill = _fillOf(layer);
    if (fill == null) return const SizedBox.shrink();
    final r = _range;
    final text = layer is TextLayer ? layer : null;

    void set(PixFill f, {bool live = false}) {
      Layer op(Layer x) {
        final out = _withFill(x, f);
        // A whole-text colour replaces per-part colours.
        return out is TextLayer
            ? out.copyWith(
                spans: TextSpans.clear(
                  out.spans,
                  0,
                  out.text.length,
                  font: false,
                ),
              )
            : out;
      }

      live
          ? editor.previewLayer(layer.id, op)
          : editor.updateLayer(layer.id, op, label: 'fill');
    }

    void setPart(Color c, {bool live = false}) {
      Layer op(Layer x) {
        final t = x as TextLayer;
        return t.copyWith(
          spans: TextSpans.apply(t.spans, r!.start, r.end, color: c),
        );
      }

      live
          ? editor.previewLayer(layer.id, op)
          : editor.updateLayer(layer.id, op, label: 'fill');
    }

    // The colour shown as selected in part mode: the first styled one.
    Color? partColor() {
      if (text == null || r == null) return null;
      for (final s in text.spans) {
        if (s.color != null && s.start < r.end && s.end > r.start) {
          return s.color;
        }
      }
      return null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (text != null)
          TextPartSelector(
            text: text.text,
            spans: text.spans,
            fontFamily: text.fontFamily,
            onChanged: (v) => setState(() => _range = v),
          ),
        PanelLabel(l.solid),
        ColorStrip(
          value: r != null
              ? partColor()
              : (fill.isGradient ? null : fill.primary),
          onChanged: (c, {required live}) {
            if (c == null) return;
            r != null
                ? setPart(c, live: live)
                : set(PixFill.color(c), live: live);
          },
        ),
        if (r == null) ...[
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
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextButton.icon(
                onPressed: () => editor.updateLayer(layer.id, (x) {
                  final t = x as TextLayer;
                  return t.copyWith(
                    spans: TextSpans.clear(
                      t.spans,
                      r.start,
                      r.end,
                      font: false,
                    ),
                  );
                }, label: 'fill'),
                icon: const Icon(Icons.format_color_reset_rounded),
                label: Text(l.resetStyle),
              ),
            ),
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
