import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/layer_geometry.dart';
import '../../../document/render/document_renderer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import 'effect_panels.dart';
import 'panel_common.dart';

List<String> _ids(EditorController e, Layer layer) =>
    e.topLevelSelection.isEmpty ? [layer.id] : e.topLevelSelection;

/// Nudges the selection with arrow buttons: tap for one step, hold to keep
/// moving (accelerating). Step size is selectable.
class MovePanel extends StatefulWidget {
  const MovePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<MovePanel> createState() => _MovePanelState();
}

class _MovePanelState extends State<MovePanel> {
  static const _steps = [1.0, 5.0, 10.0, 50.0];
  double _step = 5;
  Timer? _timer;
  Offset _total = Offset.zero;
  int _ticks = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start(Offset dir) {
    HapticFeedback.selectionClick();
    _total = dir * _step;
    _ticks = 0;
    widget.editor.nudgeSelectionLive(_total);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      _ticks++;
      if (_ticks < 5) return; // short delay before repeating
      final boost = _ticks > 30 ? 3.0 : (_ticks > 15 ? 2.0 : 1.0);
      _total += dir * _step * boost;
      widget.editor.nudgeSelectionLive(_total);
    });
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    if (widget.editor.isPreviewing) widget.editor.commit('nudge');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final b = widget.editor.boundsOf(_ids(widget.editor, widget.layer));

    Widget arrow(IconData icon, Offset dir) => Listener(
      onPointerDown: (_) => _start(dir),
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 30, color: scheme.primary),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // D-pad (always physical directions, even in RTL).
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 190,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  arrow(Icons.keyboard_arrow_up_rounded, const Offset(0, -1)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      arrow(
                        Icons.keyboard_arrow_left_rounded,
                        const Offset(-1, 0),
                      ),
                      const SizedBox(width: 66),
                      arrow(
                        Icons.keyboard_arrow_right_rounded,
                        const Offset(1, 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  arrow(Icons.keyboard_arrow_down_rounded, const Offset(0, 1)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.step, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in _steps)
                      ChoiceChip(
                        label: Text('${s.round()} px'),
                        selected: _step == s,
                        onSelected: (_) => setState(() => _step = s),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'X ${b.left.round()}   Y ${b.top.round()}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts the selection at a spot on the canvas (3×3 grid), fits or fills
/// the canvas, and changes the stacking order.
class PositionPanel extends StatelessWidget {
  const PositionPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ids = _ids(editor, layer);
    final single = ids.length == 1;
    final i = editor.document.indexOf(layer.id);
    final top = editor.document.siblingsOf(layer.id).length - 1;

    Widget cell(Alignment a) => InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.selectionClick();
        editor.placeOnCanvas(ids, a);
      },
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: a,
        padding: const EdgeInsets.all(7),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  width: 150,
                  height: 150,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(PixTokens.radiusM),
                  ),
                  child: GridView.count(
                    crossAxisCount: 3,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final a in const [
                        Alignment.topLeft,
                        Alignment.topCenter,
                        Alignment.topRight,
                        Alignment.centerLeft,
                        Alignment.center,
                        Alignment.centerRight,
                        Alignment.bottomLeft,
                        Alignment.bottomCenter,
                        Alignment.bottomRight,
                      ])
                        cell(a),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.placeOnCanvas,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => editor.fitToCanvas(ids),
                      icon: const Icon(Icons.fit_screen_rounded),
                      label: Text(l.fitCanvas),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () => editor.fitToCanvas(ids, cover: true),
                      icon: const Icon(Icons.fullscreen_rounded),
                      label: Text(l.fillCanvas),
                    ),
                    if (single) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () => editor.resetTransform(layer.id),
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        label: Text(l.reset),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        PanelLabel(l.layerOrder),
        TileRow(
          children: [
            PanelTile(
              icon: Icons.flip_to_front_rounded,
              label: l.toFront,
              onTap: single && i < top
                  ? () => editor.arrange(layer.id, LayerArrange.front)
                  : null,
            ),
            PanelTile(
              icon: Icons.arrow_upward_rounded,
              label: l.forward,
              onTap: single && i < top
                  ? () => editor.arrange(layer.id, LayerArrange.forward)
                  : null,
            ),
            PanelTile(
              icon: Icons.arrow_downward_rounded,
              label: l.backward,
              onTap: single && i > 0
                  ? () => editor.arrange(layer.id, LayerArrange.backward)
                  : null,
            ),
            PanelTile(
              icon: Icons.flip_to_back_rounded,
              label: l.toBack,
              onTap: single && i > 0
                  ? () => editor.arrange(layer.id, LayerArrange.back)
                  : null,
            ),
          ],
        ),
        if (!single) ...[
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
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Size: uniform scale, separate stretch, and the natural size controls of
/// the layer type (font size / box width for text, width/height for
/// shapes).
class SizePanel extends StatefulWidget {
  const SizePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<SizePanel> createState() => _SizePanelState();
}

class _SizePanelState extends State<SizePanel> {
  /// Relative scale for groups / multi-selections (resets after a drag).
  double _relative = 100;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editor = widget.editor;
    final layer = widget.layer;
    final ids = _ids(editor, layer);
    void commit([_]) => editor.commit('size');
    final maxSide =
        math.max(editor.document.width, editor.document.height) * 1.5;

    if (ids.length > 1 || layer is GroupLayer) {
      final pivot = editor.boundsOf(ids).center;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixSlider(
            label: l.scale,
            value: _relative,
            min: 10,
            max: 300,
            defaultValue: 100,
            format: (v) => '${v.round()}%',
            onChanged: (v) {
              setState(() => _relative = v);
              editor.transformLayers(
                ids,
                Similarity(pivot: pivot, scale: v / 100),
                live: true,
              );
            },
            onChangeEnd: (_) {
              commit();
              setState(() => _relative = 100);
            },
          ),
          _FitRow(editor: editor, ids: ids),
        ],
      );
    }

    final t = layer.props.transform;
    final sx = t.scaleX.abs(), sy = t.scaleY.abs();
    void setScale({double? x, double? y}) => editor.updateProps(
      layer.id,
      (p) => p.copyWith(
        transform: p.transform.copyWith(
          scaleX: x == null ? null : x * p.transform.scaleX.sign,
          scaleY: y == null ? null : y * p.transform.scaleY.sign,
        ),
      ),
      live: true,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (layer is TextLayer) ...[
          PixSlider(
            label: l.fontSize,
            value: layer.fontSize,
            min: 8,
            max: 800,
            onChanged: (v) => editor.editSelected<TextLayer>(
              (x) => x.copyWith(fontSize: v.roundToDouble()),
              live: true,
            ),
            onChangeEnd: commit,
          ),
          PixSlider(
            label: l.boxWidth,
            value: layer.boxWidth ?? layerLocalSize(layer).width,
            min: layer.fontSize,
            max: maxSide,
            onChanged: (v) => editor.editSelected<TextLayer>(
              (x) => x.copyWith(boxWidth: v.roundToDouble()),
              live: true,
            ),
            onChangeEnd: commit,
          ),
        ],
        if (layer is ShapeLayer) ...[
          PixSlider(
            label: l.width,
            value: layer.width,
            min: 2,
            max: maxSide,
            onChanged: (v) => editor.editSelected<ShapeLayer>(
              (x) => x.copyWith(width: v.roundToDouble()),
              live: true,
            ),
            onChangeEnd: commit,
          ),
          PixSlider(
            label: l.height,
            value: layer.height,
            min: 2,
            max: maxSide,
            onChanged: (v) => editor.editSelected<ShapeLayer>(
              (x) => x.copyWith(height: v.roundToDouble()),
              live: true,
            ),
            onChangeEnd: commit,
          ),
        ],
        PixSlider(
          label: l.scale,
          value: (sx + sy) / 2 * 100,
          min: 5,
          max: 500,
          defaultValue: 100,
          format: (v) => '${v.round()}%',
          onChanged: (v) {
            // Keeps the stretch ratio.
            final k = v / 100 / math.max(0.0001, (sx + sy) / 2);
            setScale(x: sx * k, y: sy * k);
          },
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.stretchH,
          value: sx * 100,
          min: 5,
          max: 500,
          defaultValue: 100,
          format: (v) => '${v.round()}%',
          onChanged: (v) => setScale(x: v / 100),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.stretchV,
          value: sy * 100,
          min: 5,
          max: 500,
          defaultValue: 100,
          format: (v) => '${v.round()}%',
          onChanged: (v) => setScale(y: v / 100),
          onChangeEnd: commit,
        ),
        _FitRow(editor: editor, ids: ids),
      ],
    );
  }
}

class _FitRow extends StatelessWidget {
  const _FitRow({required this.editor, required this.ids});
  final EditorController editor;
  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => editor.fitToCanvas(ids),
              icon: const Icon(Icons.fit_screen_rounded),
              label: Text(l.fitCanvas, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => editor.fitToCanvas(ids, cover: true),
              icon: const Icon(Icons.fullscreen_rounded),
              label: Text(l.fillCanvas, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2D rotation (angle, quick turns, flips) and 3D tilt.
class RotatePanel extends StatefulWidget {
  const RotatePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  State<RotatePanel> createState() => _RotatePanelState();
}

class _RotatePanelState extends State<RotatePanel> {
  bool _threeD = false;
  double _relative = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editor = widget.editor;
    final layer = widget.layer;
    final ids = _ids(editor, layer);
    final leaf = ids.length == 1 && layer is! GroupLayer;
    final deg = layer.props.transform.rotation * 180 / math.pi;
    final pivot = editor.boundsOf(ids).center;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leaf)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.rotate_right_rounded, size: 18),
                  label: Text(l.rotate2d),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.threed_rotation_rounded, size: 18),
                  label: Text(l.rotate3d),
                ),
              ],
              selected: {_threeD},
              onSelectionChanged: (s) => setState(() => _threeD = s.first),
            ),
          ),
        if (_threeD && leaf)
          TiltControls(editor: editor, layer: layer)
        else ...[
          if (leaf)
            PixSlider(
              label: l.angle,
              value: ((deg + 180) % 360) - 180,
              min: -180,
              max: 180,
              defaultValue: 0,
              format: fxDegrees,
              onChanged: (v) => editor.updateProps(
                layer.id,
                (p) => p.copyWith(
                  transform: p.transform.copyWith(
                    rotation: v.roundToDouble() * math.pi / 180,
                  ),
                ),
                live: true,
              ),
              onChangeEnd: (_) => editor.commit('rotate'),
            )
          else
            PixSlider(
              label: l.angle,
              value: _relative,
              min: -180,
              max: 180,
              defaultValue: 0,
              format: fxDegrees,
              onChanged: (v) {
                setState(() => _relative = v);
                editor.transformLayers(
                  ids,
                  Similarity(pivot: pivot, rotation: v * math.pi / 180),
                  live: true,
                );
              },
              onChangeEnd: (_) {
                editor.commit('rotate');
                setState(() => _relative = 0);
              },
            ),
          TileRow(
            children: [
              PanelTile(
                icon: Icons.rotate_90_degrees_ccw_rounded,
                label: '−90°',
                onTap: () => editor.rotateLayers(ids, -math.pi / 2),
              ),
              PanelTile(
                icon: Icons.rotate_90_degrees_cw_rounded,
                label: '+90°',
                onTap: () => editor.rotateLayers(ids, math.pi / 2),
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
              if (leaf)
                PanelTile(
                  icon: Icons.restart_alt_rounded,
                  label: l.reset,
                  onTap: () => editor.updateProps(
                    layer.id,
                    (p) => p.copyWith(
                      transform: p.transform.copyWith(
                        rotation: 0,
                        tiltX: 0,
                        tiltY: 0,
                      ),
                    ),
                    label: 'rotate',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
