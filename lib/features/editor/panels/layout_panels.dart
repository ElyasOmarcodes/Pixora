import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/model/blend.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'panel_common.dart';

/// Opacity, blend mode (grouped like Photoshop) and clipping mask.
///
/// On desktop, hovering a blend mode previews it on the canvas; clicking
/// applies it.
class OpacityPanel extends StatelessWidget {
  const OpacityPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = layer.props.blendMode;
    final chips = <Widget>[];
    BlendCategory? lastCategory;
    for (final m in PixBlendMode.values) {
      if (lastCategory != null && m.category != lastCategory) {
        chips.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: VerticalDivider(width: 1, color: theme.dividerColor),
          ),
        );
      }
      lastCategory = m.category;
      chips.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: MouseRegion(
            onEnter: (_) {
              if (m != current) {
                editor.previewLayer(
                  layer.id,
                  (x) => x.update((p) => p.copyWith(blendMode: m)),
                );
              }
            },
            onExit: (_) => editor.cancelPreview(),
            child: ChoiceChip(
              label: Text(m.label, textDirection: TextDirection.ltr),
              selected: current == m,
              onSelected: (_) => editor.updateProps(
                layer.id,
                (p) => p.copyWith(blendMode: m),
                label: 'blend',
              ),
            ),
          ),
        ),
      );
    }

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
            children: chips,
          ),
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          secondary: const Icon(Icons.subdirectory_arrow_right_rounded),
          title: Text(l.clippingMask),
          value: layer.props.clip,
          onChanged: (_) => editor.toggleClip(layer.id),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Stacking order, flip/rotate and alignment. With several layers
/// selected, flip/rotate treat them as one unit and alignment lines them
/// up with each other.
class ArrangePanel extends StatelessWidget {
  const ArrangePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = layer.id;
    final ids = editor.topLevelSelection.isEmpty
        ? [id]
        : editor.topLevelSelection;
    final single = ids.length == 1;
    final i = editor.document.indexOf(id);
    final top = editor.document.siblingsOf(id).length - 1;
    VoidCallback? order(bool enabled, LayerArrange a) =>
        single && enabled ? () => editor.arrange(id, a) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(l.arrange),
        TileRow(
          children: [
            PanelTile(
              icon: Icons.flip_to_front_rounded,
              label: l.toFront,
              onTap: order(i < top, LayerArrange.front),
            ),
            PanelTile(
              icon: Icons.arrow_upward_rounded,
              label: l.forward,
              onTap: order(i < top, LayerArrange.forward),
            ),
            PanelTile(
              icon: Icons.arrow_downward_rounded,
              label: l.backward,
              onTap: order(i > 0, LayerArrange.backward),
            ),
            PanelTile(
              icon: Icons.flip_to_back_rounded,
              label: l.toBack,
              onTap: order(i > 0, LayerArrange.back),
            ),
            PanelTile(
              icon: Icons.flip_rounded,
              label: l.flipH,
              onTap: () => editor.flipLayers(ids, horizontal: true),
            ),
            PanelTile(
              iconWidget: const RotatedBox(
                quarterTurns: 1,
                child: Icon(Icons.flip_rounded),
              ),
              icon: null,
              label: l.flipV,
              onTap: () => editor.flipLayers(ids, horizontal: false),
            ),
            PanelTile(
              icon: Icons.rotate_90_degrees_cw_rounded,
              label: l.rotate,
              onTap: () => editor.rotateLayers(ids, math.pi / 2),
            ),
          ],
        ),
        PanelLabel(l.align),
        TileRow(
          children: [
            for (final (icon, label, a) in [
              (
                Icons.align_horizontal_left_rounded,
                l.alignLeft,
                LayerAlign.left,
              ),
              (
                Icons.align_horizontal_center_rounded,
                l.alignCenter,
                LayerAlign.centerH,
              ),
              (
                Icons.align_horizontal_right_rounded,
                l.alignRight,
                LayerAlign.right,
              ),
              (Icons.align_vertical_top_rounded, l.alignTop, LayerAlign.top),
              (
                Icons.align_vertical_center_rounded,
                l.alignMiddle,
                LayerAlign.centerV,
              ),
              (
                Icons.align_vertical_bottom_rounded,
                l.alignBottom,
                LayerAlign.bottom,
              ),
            ])
              PanelTile(
                icon: icon,
                label: label,
                onTap: () => editor.alignLayers(ids, a),
              ),
            if (single)
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
