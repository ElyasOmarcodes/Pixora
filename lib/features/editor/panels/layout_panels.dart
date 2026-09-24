import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/model/blend.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

String blendLabel(PixBlendMode m) {
  final n = m.name;
  return n[0].toUpperCase() +
      n.substring(1).replaceAllMapped(RegExp('[A-Z]'), (x) => ' ${x[0]}');
}

class OpacityPanel extends StatelessWidget {
  const OpacityPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixSlider(
          label: l.opacity,
          value: layer.props.opacity,
          min: 0,
          max: 1,
          defaultValue: 1,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => editor.updateProps(
            layer.id,
            (p) => p.copyWith(opacity: v),
            live: true,
          ),
          onChangeEnd: (_) => editor.commit('opacity'),
        ),
        PanelLabel(l.blendMode),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final m in PixBlendMode.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(
                      blendLabel(m),
                      textDirection: TextDirection.ltr,
                    ),
                    selected: layer.props.blendMode == m,
                    onSelected: (_) => editor.updateProps(
                      layer.id,
                      (p) => p.copyWith(blendMode: m),
                      label: 'blend',
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class ArrangePanel extends StatelessWidget {
  const ArrangePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = layer.id;
    final i = editor.document.indexOf(id);
    final top = editor.document.layers.length - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(l.arrange),
        TileRow(
          children: [
            PanelTile(
              icon: Icons.flip_to_front_rounded,
              label: l.toFront,
              onTap: i < top
                  ? () => editor.arrange(id, LayerArrange.front)
                  : null,
            ),
            PanelTile(
              icon: Icons.arrow_upward_rounded,
              label: l.forward,
              onTap: i < top
                  ? () => editor.arrange(id, LayerArrange.forward)
                  : null,
            ),
            PanelTile(
              icon: Icons.arrow_downward_rounded,
              label: l.backward,
              onTap: i > 0
                  ? () => editor.arrange(id, LayerArrange.backward)
                  : null,
            ),
            PanelTile(
              icon: Icons.flip_to_back_rounded,
              label: l.toBack,
              onTap: i > 0 ? () => editor.arrange(id, LayerArrange.back) : null,
            ),
            PanelTile(
              icon: Icons.flip_rounded,
              label: l.flipH,
              onTap: () => editor.flip(id, horizontal: true),
            ),
            PanelTile(
              iconWidget: const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.flip_rounded),
              ),
              icon: null,
              label: l.flipV,
              onTap: () => editor.flip(id, horizontal: false),
            ),
            PanelTile(
              icon: Icons.rotate_90_degrees_cw_rounded,
              label: l.rotate,
              onTap: () => editor.updateProps(
                id,
                (p) => p.copyWith(
                  transform: p.transform.copyWith(
                    rotation: p.transform.rotation + math.pi / 2,
                  ),
                ),
                label: 'rotate',
              ),
            ),
          ],
        ),
        PanelLabel(l.align),
        TileRow(
          children: [
            PanelTile(
              icon: Icons.align_horizontal_left_rounded,
              label: l.alignLeft,
              onTap: () => editor.align(id, LayerAlign.left),
            ),
            PanelTile(
              icon: Icons.align_horizontal_center_rounded,
              label: l.alignCenter,
              onTap: () => editor.align(id, LayerAlign.centerH),
            ),
            PanelTile(
              icon: Icons.align_horizontal_right_rounded,
              label: l.alignRight,
              onTap: () => editor.align(id, LayerAlign.right),
            ),
            PanelTile(
              icon: Icons.align_vertical_top_rounded,
              label: l.alignTop,
              onTap: () => editor.align(id, LayerAlign.top),
            ),
            PanelTile(
              icon: Icons.align_vertical_center_rounded,
              label: l.alignMiddle,
              onTap: () => editor.align(id, LayerAlign.centerV),
            ),
            PanelTile(
              icon: Icons.align_vertical_bottom_rounded,
              label: l.alignBottom,
              onTap: () => editor.align(id, LayerAlign.bottom),
            ),
            PanelTile(
              icon: Icons.center_focus_strong_rounded,
              label: l.reset,
              onTap: () => editor.resetTransform(id),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Shape kind, proportions, corner radius and point count.
class ShapeStylePanel extends StatelessWidget {
  const ShapeStylePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final ShapeLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void edit(ShapeLayer Function(ShapeLayer s) f, {bool live = false}) =>
        editor.editSelected<ShapeLayer>(f, live: live, label: 'shape');
    void commit([_]) => editor.commit('shape');
    final maxSide =
        math.max(editor.document.width, editor.document.height) * 1.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TileRow(
          children: [
            for (final k in ShapeKind.values)
              PanelTile(
                icon: shapeIcon(k),
                label: shapeLabel(l, k),
                selected: layer.shape == k,
                onTap: () => edit((s) => s.copyWith(shape: k)),
              ),
          ],
        ),
        PixSlider(
          label: l.width,
          value: layer.width,
          min: 2,
          max: maxSide,
          onChanged: (v) =>
              edit((s) => s.copyWith(width: v.roundToDouble()), live: true),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.height,
          value: layer.height,
          min: 2,
          max: maxSide,
          onChanged: (v) =>
              edit((s) => s.copyWith(height: v.roundToDouble()), live: true),
          onChangeEnd: commit,
        ),
        if (layer.shape == ShapeKind.rectangle)
          PixSlider(
            label: l.corners,
            value: layer.cornerRadius,
            min: 0,
            max: math.min(layer.width, layer.height) / 2,
            defaultValue: 0,
            onChanged: (v) =>
                edit((s) => s.copyWith(cornerRadius: v), live: true),
            onChangeEnd: commit,
          ),
        if (layer.shape == ShapeKind.star || layer.shape == ShapeKind.polygon)
          PixSlider(
            label: l.points,
            value: layer.sides.toDouble(),
            min: 3,
            max: 16,
            onChanged: (v) =>
                edit((s) => s.copyWith(sides: v.round()), live: true),
            onChangeEnd: commit,
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
