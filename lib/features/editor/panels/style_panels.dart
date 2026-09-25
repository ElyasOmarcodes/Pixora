import 'package:flutter/material.dart';

import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/layer_stroke.dart';
import '../../../document/model/text_span_style.dart';
import '../widgets/rich_text_field.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/fill_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../../../document/render/document_renderer.dart';
import '../../../document/render/text_layout.dart';
import 'panel_common.dart';

PixFill? _fillOf(Layer l) => switch (l) {
  TextLayer t => t.fill,
  ShapeLayer s => s.fill,
  IconLayer i => i.fill,
  PathLayer p => p.fill ?? PixFill.color(p.strokeColor),
  DrawingLayer d => PixFill.color(
    d.strokes
        .lastWhere(
          (s) => !s.eraser,
          orElse: () => BrushStroke(points: const []),
        )
        .color,
  ),
  RasterLayer _ || GroupLayer _ => null,
};

Layer _withFill(Layer l, PixFill f) => switch (l) {
  TextLayer t => t.copyWith(fill: f),
  ShapeLayer s => s.copyWith(fill: f),
  IconLayer i => i.copyWith(fill: f),
  // Open lines take the colour as their stroke.
  PathLayer p =>
    p.fill == null ? p.copyWith(strokeColor: f.primary) : p.copyWith(fill: f),
  // Recolours every brush stroke of a drawing.
  DrawingLayer d => d.copyWith(
    strokes: [for (final s in d.strokes) s.recolored(f.primary)],
  ),
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
        if (r == null)
          FillPicker(
            value: fill,
            // The box the gradient is laid out in (text: the glyph box).
            aspect: () {
              final b = layer is TextLayer
                  ? Offset.zero & TextLayoutCache.instance.fill(layer).size
                  : layerLocalRect(layer);
              return b.height <= 0 ? 1.0 : b.width / b.height;
            }(),
            onChanged: (f, {required live}) {
              if (f != null) set(f, live: live);
            },
          ),
        if (r != null) ...[
          PanelLabel(l.solid),
          ColorStrip(
            value: partColor(),
            onChanged: (c, {required live}) {
              if (c != null) setPart(c, live: live);
            },
          ),
        ],
        if (r != null)
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
/// Photoshop's Stroke: size, position (outside / centre / inside), a
/// colour, gradient or pattern fill, opacity and its own blend mode. It
/// follows the layer's pixels and is not faded by Fill opacity.
class StrokePanel extends StatelessWidget {
  const StrokePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  /// The layer's stroke; older projects' simple strokes are shown as the
  /// same-looking style stroke (text: outside, half width; shapes and
  /// icons: centred).
  static LayerStroke? strokeOf(Layer l) {
    if (l.props.stroke != null) return l.props.stroke;
    final (w, c, textLike) = switch (l) {
      TextLayer t => (t.strokeWidth, t.strokeColor, true),
      ShapeLayer s => (s.strokeWidth, s.strokeColor, false),
      IconLayer i => (i.strokeWidth, i.strokeColor, false),
      _ => (0.0, const Color(0xFF000000), false),
    };
    if (w <= 0) return null;
    return LayerStroke(
      size: textLike ? w / 2 : w,
      position: textLike ? StrokePosition.outside : StrokePosition.center,
      fill: PixFill.color(c),
    );
  }

  /// [s] as the layer's stroke; the old simple stroke is dropped.
  static Layer withStroke(Layer x, LayerStroke? s) {
    final plain = switch (x) {
      TextLayer t => t.copyWith(strokeWidth: 0),
      ShapeLayer sh => sh.copyWith(strokeWidth: 0),
      IconLayer i => i.copyWith(strokeWidth: 0),
      _ => x,
    };
    return plain.update(
      (p) => p.copyWith(stroke: s, clearStroke: s == null || s.size <= 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = strokeOf(layer);
    final maxSize = layer is TextLayer
        ? ((layer as TextLayer).fontSize * 0.4).clamp(20.0, 200.0)
        : 100.0;
    final defaultSize = (maxSize * 0.1).clamp(2.0, 12.0);
    final s =
        current ??
        LayerStroke(size: 0, fill: PixFill.color(const Color(0xFF000000)));

    void set(LayerStroke next, {bool live = false}) {
      live
          ? editor.previewLayer(layer.id, (x) => withStroke(x, next))
          : editor.updateLayer(
              layer.id,
              (x) => withStroke(x, next),
              label: 'stroke',
            );
    }

    // Choosing a colour, position… with no stroke yet makes it visible.
    LayerStroke visible(LayerStroke x) =>
        x.size > 0 ? x : x.copyWith(size: defaultSize);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PixSlider(
          label: l.size,
          value: s.size.clamp(0, maxSize).toDouble(),
          min: 0,
          max: maxSize.toDouble(),
          defaultValue: 0,
          onChanged: (v) => set(s.copyWith(size: v), live: true),
          onChangeEnd: (_) => editor.commit('stroke'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SegmentedButton<StrokePosition>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: StrokePosition.outside,
                icon: const Icon(Icons.crop_din_rounded, size: 18),
                label: Text(l.strokeOutside, maxLines: 1),
              ),
              ButtonSegment(
                value: StrokePosition.center,
                icon: const Icon(Icons.border_outer_rounded, size: 18),
                label: Text(l.strokeCenter, maxLines: 1),
              ),
              ButtonSegment(
                value: StrokePosition.inside,
                icon: const Icon(Icons.border_inner_rounded, size: 18),
                label: Text(l.strokeInside, maxLines: 1),
              ),
            ],
            selected: {s.position},
            onSelectionChanged: (v) =>
                set(visible(s.copyWith(position: v.first))),
          ),
        ),
        FillPicker(
          value: s.fill,
          aspect:
              layerLocalSize(layer).width /
              layerLocalSize(layer).height.clamp(1, double.infinity),
          onChanged: (f, {required live}) {
            if (f == null) return;
            set(visible(s.copyWith(fill: f)), live: live);
          },
        ),
        PixSlider(
          label: l.opacity,
          value: s.opacity,
          min: 0,
          max: 1,
          defaultValue: 1,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => set(visible(s.copyWith(opacity: v)), live: true),
          onChangeEnd: (_) => editor.commit('stroke'),
        ),
        BlendModeRow(
          label: l.blendMode,
          value: s.blend,
          onChanged: (m) => set(visible(s.copyWith(blend: m))),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
