import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/icons/icon_catalog.dart';
import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../document/render/shape_paths.dart';
import '../../../document/render/vector_paths.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/tools/pen_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../../../ui/widgets/pressable.dart';
import 'panel_common.dart';

// ------------------------------------------------------------- previews

/// Draws [path] fitted into the widget.
class _PathPreview extends CustomPainter {
  _PathPreview(this.path, this.color);
  final Path path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final b = path.getBounds();
    if (b.isEmpty && b.width == 0) return;
    final s = math.min(size.width / b.width, size.height / b.height);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s)
      ..translate(-b.center.dx, -b.center.dy);
    canvas
      ..drawPath(path, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_PathPreview old) =>
      old.path != path || old.color != color;
}

/// Draws a vector preset with its dashes and arrowheads, fitted.
class _VectorPreview extends CustomPainter {
  _VectorPreview(this.layer, this.color);
  final PathLayer layer;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final b = pathLayerPath(layer).getBounds();
    final extent = math.max(b.width, b.height);
    if (extent <= 0) return;
    // Aim for a ~2.5px line whatever the preset's size.
    final w = extent * 2.5 / size.width;
    final l = layer.copyWith(
      strokeWidth: w,
      strokeColor: color,
      fill: layer.fill == null ? null : PixFill.color(color),
    );
    final r = pathLayerRect(l);
    final s = math.min(size.width / r.width, size.height / r.height);
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(s)
      ..translate(-r.center.dx, -r.center.dy);
    paintPathLayer(canvas, l);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_VectorPreview old) =>
      old.layer != layer || old.color != color;
}

ShapeLayer _sample(ShapeKind k) => ShapeLayer(
  LayerProps(name: ''),
  shape: k,
  width: switch (k) {
    ShapeKind.blockArrow || ShapeKind.parallelogram => 120,
    ShapeKind.line => 100,
    _ => 100,
  },
  height: switch (k) {
    ShapeKind.blockArrow || ShapeKind.parallelogram => 70,
    ShapeKind.line => 10,
    _ => 100,
  },
  sides: k == ShapeKind.polygon ? 6 : (k == ShapeKind.gear ? 10 : 5),
  cornerRadius: k == ShapeKind.rectangle || k == ShapeKind.frame ? 14 : 0,
);

class ShapePreview extends StatelessWidget {
  const ShapePreview(this.kind, {super.key, required this.color});
  final ShapeKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PathPreview(buildShapePath(_sample(kind)), color),
    child: const SizedBox(width: 30, height: 30),
  );
}

// ------------------------------------------------------ shape menu (4)

enum _AddTab { shapes, vectors }

/// The Shape menu: Icons, Shapes, Pen and Vectors.
class AddShapePanel extends StatefulWidget {
  const AddShapePanel({
    super.key,
    required this.editor,
    required this.onAdded,
    required this.onIcons,
    required this.onPen,
  });
  final EditorController editor;
  final VoidCallback onAdded;
  final VoidCallback onIcons;
  final VoidCallback onPen;

  @override
  State<AddShapePanel> createState() => _AddShapePanelState();
}

class _AddShapePanelState extends State<AddShapePanel> {
  _AddTab _tab = _AddTab.shapes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;

    Widget card(
      IconData icon,
      String label,
      bool selected,
      VoidCallback onTap, {
      List<Color>? gradient,
    }) => Expanded(
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        scale: 0.94,
        child: AnimatedContainer(
          duration: PixTokens.fast,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors:
                        gradient ??
                        [
                          scheme.primary,
                          Color.lerp(scheme.primary, scheme.tertiary, 0.6)!,
                        ],
                  )
                : null,
            color: selected ? null : scheme.onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(PixTokens.radiusM),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? scheme.onPrimary : scheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              card(Icons.emoji_symbols_rounded, l.icons, false, widget.onIcons),
              card(
                Icons.category_rounded,
                l.shapes,
                _tab == _AddTab.shapes,
                () => setState(() => _tab = _AddTab.shapes),
              ),
              card(Icons.draw_rounded, l.pen, false, widget.onPen),
              card(
                Icons.north_east_rounded,
                l.vectors,
                _tab == _AddTab.vectors,
                () => setState(() => _tab = _AddTab.vectors),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_tab == _AddTab.shapes)
          SizedBox(
            height: 176,
            child: GridView.count(
              scrollDirection: Axis.horizontal,
              crossAxisCount: 2,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
              children: [
                for (final k in ShapeKind.values)
                  _PresetTile(
                    label: shapeLabel(l, k),
                    preview: ShapePreview(k, color: color),
                    onTap: () {
                      widget.editor.addShape(k, name: l.shape, color: color);
                      widget.onAdded();
                    },
                  ),
              ],
            ),
          )
        else
          SizedBox(
            height: 176,
            child: GridView.count(
              scrollDirection: Axis.horizontal,
              crossAxisCount: 2,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.05,
              children: [
                for (final p in vectorPresets(100))
                  _PresetTile(
                    label: p.label(l),
                    preview: CustomPaint(
                      painter: _VectorPreview(p.layer, color),
                      child: const SizedBox(width: 44, height: 34),
                    ),
                    onTap: () {
                      final unit = math.min(
                        widget.editor.document.width,
                        widget.editor.document.height,
                      );
                      final preset = vectorPresets(unit * 0.3)
                          .firstWhere((x) => x.id == p.id);
                      widget.editor.addPath(
                        preset.layer.copyWith(
                          strokeColor: color,
                          strokeWidth: math.max(2, unit * 0.012),
                          fill: preset.layer.fill == null
                              ? null
                              : PixFill.color(color),
                        ),
                        name: l.vector,
                      );
                      widget.onAdded();
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

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.label,
    required this.preview,
    required this.onTap,
  });
  final String label;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      haptic: true,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            preview,
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------ vector presets

class VectorPreset {
  const VectorPreset(this.id, this.layer, this.label);
  final String id;
  final PathLayer layer;
  final String Function(AppLocalizations l) label;
}

/// Ready-made lines and arrows (size [s] = half length), all editable
/// with the pen afterwards.
List<VectorPreset> vectorPresets(double s) {
  PathNode n(double x, double y, {Offset? i, Offset? o}) => PathNode(
    Offset(x, y),
    inHandle: i,
    outHandle: o,
    type: i != null || o != null ? PathNodeType.smooth : PathNodeType.corner,
  );
  PathLayer line(
    List<PathNode> nodes, {
    ArrowHead start = ArrowHead.none,
    ArrowHead end = ArrowHead.none,
    DashStyle dash = DashStyle.solid,
    bool closed = false,
    bool fill = false,
  }) => PathLayer(
    LayerProps(name: 'Vector'),
    contours: [PathContour(nodes: nodes, closed: closed)],
    startHead: start,
    endHead: end,
    dash: dash,
    fill: fill ? PixFill.white : null,
  );
  final wave = <PathNode>[
    for (var i = 0; i <= 4; i++)
      n(
        -s + i * s / 2,
        i.isEven ? 0 : (i % 4 == 1 ? -s * 0.3 : s * 0.3),
        i: i == 0
            ? null
            : Offset(
                -s + i * s / 2 - s * 0.18,
                i.isEven ? 0 : (i % 4 == 1 ? -s * 0.3 : s * 0.3),
              ),
        o: i == 4
            ? null
            : Offset(
                -s + i * s / 2 + s * 0.18,
                i.isEven ? 0 : (i % 4 == 1 ? -s * 0.3 : s * 0.3),
              ),
      ),
  ];
  return [
    VectorPreset('line', line([n(-s, 0), n(s, 0)]), (l) => l.shapeLine),
    VectorPreset(
      'arrow',
      line([n(-s, 0), n(s, 0)], end: ArrowHead.triangle),
      (l) => l.vArrow,
    ),
    VectorPreset(
      'double',
      line(
        [n(-s, 0), n(s, 0)],
        start: ArrowHead.triangle,
        end: ArrowHead.triangle,
      ),
      (l) => l.vDoubleArrow,
    ),
    VectorPreset(
      'curved',
      line([
        n(-s, s * 0.35, o: Offset(-s * 0.55, -s * 0.55)),
        n(s, s * 0.35, i: Offset(s * 0.55, -s * 0.55)),
      ], end: ArrowHead.arrow),
      (l) => l.vCurvedArrow,
    ),
    VectorPreset(
      'elbow',
      line([
        n(-s, -s * 0.4),
        n(0, -s * 0.4),
        n(0, s * 0.4),
        n(s, s * 0.4),
      ], end: ArrowHead.triangle),
      (l) => l.vElbow,
    ),
    VectorPreset(
      'dashed',
      line([n(-s, 0), n(s, 0)], dash: DashStyle.dashed),
      (l) => l.vDashed,
    ),
    VectorPreset(
      'dotted',
      line([n(-s, 0), n(s, 0)], dash: DashStyle.dotted),
      (l) => l.vDotted,
    ),
    VectorPreset(
      'zigzag',
      line([
        for (var i = 0; i <= 6; i++)
          n(-s + i * s / 3, i.isEven ? s * 0.25 : -s * 0.25),
      ]),
      (l) => l.vZigzag,
    ),
    VectorPreset('wave', line(wave), (l) => l.vWave),
    VectorPreset(
      'blob',
      line(
        [
          n(
            0,
            -s * 0.8,
            i: Offset(-s * 0.5, -s * 0.8),
            o: Offset(s * 0.5, -s * 0.8),
          ),
          n(
            s * 0.8,
            0,
            i: Offset(s * 0.8, -s * 0.45),
            o: Offset(s * 0.8, s * 0.5),
          ),
          n(
            0,
            s * 0.8,
            i: Offset(s * 0.5, s * 0.8),
            o: Offset(-s * 0.55, s * 0.8),
          ),
          n(
            -s * 0.85,
            0,
            i: Offset(-s * 0.85, s * 0.45),
            o: Offset(-s * 0.85, -s * 0.5),
          ),
        ],
        closed: true,
        fill: true,
      ),
      (l) => l.vBlob,
    ),
  ];
}

// ------------------------------------------------------------- pen panel

/// Pen / bezier editing, PixelLab style: a shape counter (add, previous,
/// index, duplicate, next, delete), edit/transform modes and node tools.
class PenPanel extends StatelessWidget {
  const PenPanel({
    super.key,
    required this.state,
    required this.onDone,
    this.compact = false,
  });
  final PenState state;
  final VoidCallback onDone;

  /// Inside another panel (mask): no Done button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final contours = state.target?.contours ?? const <PathContour>[];
        final c = state.activeContour;
        final node = state.node;
        final hasNode = c != null && node != null && node < c.nodes.length;
        final nodeType = hasNode ? c.nodes[node].type : null;

        Widget round(
          IconData icon,
          String tip,
          VoidCallback? onTap, {
          bool filled = true,
        }) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Tooltip(
            message: tip,
            child: filled
                ? IconButton.filled(onPressed: onTap, icon: Icon(icon))
                : IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
          ),
        );

        Widget tool(
          IconData icon,
          String label,
          VoidCallback? onTap, {
          bool selected = false,
        }) => PanelTile(
          icon: icon,
          label: label,
          selected: selected,
          width: 82,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Shape counter.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  round(Icons.add_rounded, l.newShape, state.addContour),
                  round(
                    Icons.chevron_left_rounded,
                    l.previous,
                    contours.length > 1 ? state.previousContour : null,
                    filled: false,
                  ),
                  Container(
                    width: 64,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      contours.isEmpty
                          ? '0'
                          : '${state.active + 1} / ${contours.length}',
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  round(
                    Icons.chevron_right_rounded,
                    l.next,
                    contours.length > 1 ? state.nextContour : null,
                    filled: false,
                  ),
                  round(
                    Icons.copy_rounded,
                    l.duplicate,
                    c == null || c.nodes.isEmpty
                        ? null
                        : state.duplicateContour,
                    filled: false,
                  ),
                  round(
                    Icons.remove_rounded,
                    l.deleteShape,
                    contours.isEmpty ? null : state.deleteContour,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: SegmentedButton<PenMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PenMode.edit,
                    icon: const Icon(Icons.polyline_rounded, size: 18),
                    label: Text(l.editNodes),
                  ),
                  ButtonSegment(
                    value: PenMode.transform,
                    icon: const Icon(Icons.open_with_rounded, size: 18),
                    label: Text(l.transformShape),
                  ),
                ],
                selected: {state.mode},
                onSelectionChanged: (s) => state.mode = s.first,
              ),
            ),
            if (state.mode == PenMode.edit)
              TileRow(
                children: [
                  tool(
                    Icons.remove_circle_outline_rounded,
                    l.deleteNode,
                    hasNode ? state.deleteNode : null,
                  ),
                  tool(
                    Icons.add_circle_outline_rounded,
                    l.addNode,
                    c != null && c.nodes.length >= 2 ? state.insertNode : null,
                  ),
                  tool(
                    Icons.crop_square_rounded,
                    l.nodeCorner,
                    hasNode
                        ? () => state.setNodeType(PathNodeType.corner)
                        : null,
                    selected: nodeType == PathNodeType.corner,
                  ),
                  tool(
                    Icons.radio_button_unchecked_rounded,
                    l.nodeSmooth,
                    hasNode
                        ? () => state.setNodeType(PathNodeType.smooth)
                        : null,
                    selected: nodeType == PathNodeType.smooth,
                  ),
                  tool(
                    Icons.adjust_rounded,
                    l.nodeSymmetric,
                    hasNode
                        ? () => state.setNodeType(PathNodeType.symmetric)
                        : null,
                    selected: nodeType == PathNodeType.symmetric,
                  ),
                  tool(
                    Icons.show_chart_rounded,
                    l.straighten,
                    hasNode ? state.straightenNode : null,
                  ),
                  tool(
                    c?.closed ?? false
                        ? Icons.link_off_rounded
                        : Icons.link_rounded,
                    c?.closed ?? false ? l.openPath : l.closePath,
                    c != null && c.nodes.length >= 2
                        ? state.toggleClosed
                        : null,
                  ),
                  tool(
                    Icons.swap_horiz_rounded,
                    l.reverse,
                    c != null && c.nodes.length >= 2 ? state.reverse : null,
                  ),
                ],
              )
            else
              TileRow(
                children: [
                  tool(
                    Icons.rotate_left_rounded,
                    '−15°',
                    () => state.transformActive(rotation: -math.pi / 12),
                  ),
                  tool(
                    Icons.rotate_right_rounded,
                    '+15°',
                    () => state.transformActive(rotation: math.pi / 12),
                  ),
                  tool(
                    Icons.zoom_out_rounded,
                    '−10%',
                    () => state.transformActive(scale: 0.9),
                  ),
                  tool(
                    Icons.zoom_in_rounded,
                    '+10%',
                    () => state.transformActive(scale: 1.1),
                  ),
                  tool(
                    Icons.flip_rounded,
                    l.flipH,
                    () => state.flipActive(horizontal: true),
                  ),
                  PanelTile(
                    iconWidget: const RotatedBox(
                      quarterTurns: 1,
                      child: Icon(Icons.flip_rounded),
                    ),
                    icon: null,
                    width: 82,
                    label: l.flipV,
                    onTap: () => state.flipActive(horizontal: false),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Text(
                state.mode == PenMode.edit ? l.penHint : l.penTransformHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: onDone,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.done),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------ line panel

/// Stroke, dashes, caps, arrowheads and fill of a vector path.
class LinePanel extends StatelessWidget {
  const LinePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final PathLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    void edit(PathLayer Function(PathLayer p) f, {bool live = false}) =>
        editor.editSelected<PathLayer>(f, live: live, label: 'line');
    void commit([_]) => editor.commit('line');

    Widget heads(
      String title,
      ArrowHead value,
      void Function(ArrowHead) set, {
      bool start = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(title),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final h in ArrowHead.values)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: ChoiceChip(
                    label: _HeadGlyph(h, start: start),
                    selected: value == h,
                    onSelected: (_) => set(h),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixSlider(
          label: l.strokeWidth,
          value: layer.strokeWidth,
          min: 0,
          max: 120,
          onChanged: (v) => edit((p) => p.copyWith(strokeWidth: v), live: true),
          onChangeEnd: commit,
        ),
        ColorStrip(
          value: layer.strokeColor,
          onChanged: (c, {required live}) {
            if (c != null) edit((p) => p.copyWith(strokeColor: c), live: live);
          },
        ),
        PanelLabel(l.lineStyle),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (d, label) in [
                (DashStyle.solid, l.solid),
                (DashStyle.dashed, l.vDashed),
                (DashStyle.dotted, l.vDotted),
                (DashStyle.dashDot, l.dashDot),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: layer.dash == d,
                    onSelected: (_) => edit((p) => p.copyWith(dash: d)),
                  ),
                ),
              const SizedBox(width: 10),
              for (final (c, icon) in [
                (StrokeCap.round, Icons.circle),
                (StrokeCap.butt, Icons.stop),
                (StrokeCap.square, Icons.crop_square),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: ChoiceChip(
                    label: Icon(icon, size: 16),
                    selected: layer.cap == c,
                    onSelected: (_) => edit((p) => p.copyWith(cap: c)),
                  ),
                ),
            ],
          ),
        ),
        if (layer.dash != DashStyle.solid)
          PixSlider(
            label: l.dashLength,
            value: layer.dashScale,
            min: 0.3,
            max: 6,
            defaultValue: 1,
            format: (v) => '×${v.toStringAsFixed(1)}',
            onChanged: (v) => edit((p) => p.copyWith(dashScale: v), live: true),
            onChangeEnd: commit,
          ),
        heads(
          l.startHead,
          layer.startHead,
          (h) => edit((p) => p.copyWith(startHead: h)),
          start: true,
        ),
        heads(
          l.endHead,
          layer.endHead,
          (h) => edit((p) => p.copyWith(endHead: h)),
        ),
        if (layer.startHead != ArrowHead.none ||
            layer.endHead != ArrowHead.none)
          PixSlider(
            label: l.headSize,
            value: layer.headSize,
            min: 0.3,
            max: 4,
            defaultValue: 1,
            format: (v) => '×${v.toStringAsFixed(1)}',
            onChanged: (v) => edit((p) => p.copyWith(headSize: v), live: true),
            onChangeEnd: commit,
          ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.fillShape),
          value: layer.fill != null,
          onChanged: (on) => edit(
            (p) => on
                ? p.copyWith(
                    fill: PixFill.color(p.strokeColor.withValues(alpha: 0.4)),
                  )
                : p.copyWith(noFill: true),
          ),
        ),
        if (layer.fill != null)
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Text(l.evenOdd),
            value: layer.evenOdd,
            onChanged: (v) => edit((p) => p.copyWith(evenOdd: v)),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _HeadGlyph extends StatelessWidget {
  const _HeadGlyph(this.head, {this.start = false});
  final ArrowHead head;
  final bool start;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      size: const Size(34, 16),
      painter: _HeadPainter(head, color, start),
    );
  }
}

class _HeadPainter extends CustomPainter {
  _HeadPainter(this.head, this.color, this.start);
  final ArrowHead head;
  final Color color;
  final bool start;

  @override
  void paint(Canvas canvas, Size size) {
    final l = PathLayer(
      LayerProps(name: ''),
      contours: [
        PathContour(
          nodes: [
            PathNode(Offset(start ? 6 : 2, size.height / 2)),
            PathNode(Offset(size.width - (start ? 2 : 6), size.height / 2)),
          ],
        ),
      ],
      strokeWidth: 2,
      strokeColor: color,
      startHead: start ? head : ArrowHead.none,
      endHead: start ? ArrowHead.none : head,
      headSize: 1.1,
    );
    paintPathLayer(canvas, l);
  }

  @override
  bool shouldRepaint(_HeadPainter old) =>
      old.head != head || old.color != color || old.start != start;
}

// ------------------------------------------------------------ icon style

/// Style of an icon layer: outlined / rounded / sharp, filled, weight.
/// Other styles download from Google Fonts once and are then stored in
/// the project.
class IconStylePanel extends StatefulWidget {
  const IconStylePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final IconLayer layer;

  @override
  State<IconStylePanel> createState() => _IconStylePanelState();
}

class _IconStylePanelState extends State<IconStylePanel> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _apply({IconStyle? style, bool? filled, int? weight}) async {
    final l = widget.layer;
    final s = style ?? l.style, f = filled ?? l.filled, w = weight ?? l.weight;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final d = await IconCatalog.instance.pathFor(
      l.iconName,
      style: s,
      filled: f,
      weight: w,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = d == null;
    });
    if (d == null) return;
    widget.editor.replaceIcon(
      l.id,
      l.iconName,
      d,
      style: s,
      filled: f,
      weight: w,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final layer = widget.layer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SegmentedButton<IconStyle>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: IconStyle.outlined,
                label: Text(l.iconOutlined),
              ),
              ButtonSegment(
                value: IconStyle.rounded,
                label: Text(l.iconRounded),
              ),
              ButtonSegment(value: IconStyle.sharp, label: Text(l.iconSharp)),
            ],
            selected: {layer.style},
            onSelectionChanged: _busy ? null : (s) => _apply(style: s.first),
          ),
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(l.filled),
          value: layer.filled,
          onChanged: _busy ? null : (v) => _apply(filled: v),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final w in const [100, 200, 300, 400, 500, 600, 700])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: ChoiceChip(
                    label: Text('$w'),
                    selected: layer.weight == w,
                    onSelected: _busy ? null : (_) => _apply(weight: w),
                  ),
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              l.iconOffline,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ----------------------------------------------------------- shape style

/// Shape kind (with previews) and every option of the shape.
class ShapeStylePanel extends StatelessWidget {
  const ShapeStylePanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final ShapeLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    void edit(ShapeLayer Function(ShapeLayer s) f, {bool live = false}) =>
        editor.editSelected<ShapeLayer>(f, live: live, label: 'shape');
    void commit([_]) => editor.commit('shape');
    final k = layer.shape;
    final minSide = math.min(layer.width, layer.height);

    String label(String key) => switch (key) {
      'sweep' => l.pSweep,
      'start' => l.pStart,
      'inner' => k == ShapeKind.star ? l.pSharpness : l.pInner,
      'apex' => l.pApex,
      'round' => l.corners,
      'skew' => l.pSkew,
      'top' => l.pTop,
      'thickness' => l.pThickness,
      'offset' => l.pOffset,
      'tailPos' => l.pTailPos,
      'tail' => l.pTail,
      'shaft' => l.pShaft,
      'head' => l.headSize,
      'heads' => l.pHeads,
      'depth' => l.depth,
      'hole' => l.pHole,
      _ => key,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in ShapeKind.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: SizedBox(
                    width: 70,
                    child: _PresetTile(
                      label: shapeLabel(l, s),
                      preview: ShapePreview(
                        s,
                        color: s == k
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      onTap: () => edit((x) => x.copyWith(shape: s)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (k == ShapeKind.star ||
            k == ShapeKind.polygon ||
            k == ShapeKind.gear)
          PixSlider(
            label: k == ShapeKind.star
                ? l.points
                : (k == ShapeKind.gear ? l.pTeeth : l.pSides),
            value: layer.sides.toDouble(),
            min: k == ShapeKind.gear ? 4 : 3,
            max: k == ShapeKind.gear ? 40 : 24,
            onChanged: (v) =>
                edit((x) => x.copyWith(sides: v.round()), live: true),
            onChangeEnd: commit,
          ),
        if (k == ShapeKind.rectangle || k == ShapeKind.frame)
          PixSlider(
            label: l.corners,
            value: layer.cornerRadius,
            min: 0,
            max: minSide / 2,
            defaultValue: 0,
            onChanged: (v) =>
                edit((x) => x.copyWith(cornerRadius: v), live: true),
            onChangeEnd: commit,
          ),
        for (final p in shapeParams(k))
          PixSlider(
            label: label(p.key),
            value: layer.param(p.key, p.defaultValue),
            min: p.min,
            max: p.max,
            defaultValue: p.defaultValue,
            format: switch (p.unit) {
              ShapeParamUnit.degrees => (v) => '${v.round()}°',
              ShapeParamUnit.count => (v) => '${v.round()}',
              ShapeParamUnit.ratio => (v) => '${(v * 100).round()}%',
            },
            onChanged: (v) => edit(
              (x) => x.withParam(p.key, p.step != null ? v.roundToDouble() : v),
              live: true,
            ),
            onChangeEnd: commit,
          ),
        PixSlider(
          label: l.width,
          value: layer.width,
          min: 2,
          max: math.max(editor.document.width, editor.document.height) * 1.5,
          onChanged: (v) =>
              edit((x) => x.copyWith(width: v.roundToDouble()), live: true),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.height,
          value: layer.height,
          min: 2,
          max: math.max(editor.document.width, editor.document.height) * 1.5,
          onChanged: (v) =>
              edit((x) => x.copyWith(height: v.roundToDouble()), live: true),
          onChangeEnd: commit,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
