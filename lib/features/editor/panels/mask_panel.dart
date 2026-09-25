import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../document/model/mask.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/tools/mask_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/confirm_dialog.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../editor_scope.dart';
import '../pen_targets.dart';
import 'vector_panels.dart';
import 'panel_common.dart';
import '../widgets/mask_thumb.dart';

/// Photoshop-style layer mask properties: paint in black, white or grey
/// with a brush or eraser, drag gradients, fill lasso or pen shapes,
/// hide/reveal all, invert, density and feather. While this panel is open
/// the canvas edits the mask.
class MaskPanel extends StatelessWidget {
  const MaskPanel({
    super.key,
    required this.editor,
    required this.ui,
    required this.layer,
    required this.maskPen,
  });
  final EditorController editor;
  final EditorUiState ui;
  final Layer layer;
  final MaskPenTarget maskPen;

  /// Turns the pen outline(s) into mask strokes: fill the inside with the
  /// current grey, or keep only what is inside.
  void _applyPen({required bool keepOnly}) {
    final b = ui.maskBrush;
    final shapes = [
      for (final c in maskPen.contours)
        if (c.nodes.length >= 3) c.copyWith(closed: true),
    ];
    if (shapes.isEmpty) return;
    final v = keepOnly ? 1.0 : b.level;
    editor.addMaskStrokes(layer.id, [
      if (keepOnly)
        MaskStroke(
          mode: MaskMode.hide,
          shape: MaskShape.fill,
          points: const [],
        ),
      for (final c in shapes)
        MaskStroke(
          mode: v < 0.5 ? MaskMode.hide : MaskMode.show,
          shape: MaskShape.area,
          points: const [],
          contour: c,
          softness: b.softness,
          level: v == 0 || v == 1 ? null : v,
          opacity: keepOnly ? 1 : b.opacity,
        ),
    ]);
    maskPen.clear();
    ui.penState.reset();
    ui.penState.target = maskPen;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brush = ui.maskBrush;
    final props = layer.props;

    // No mask yet: Photoshop's "Add layer mask".
    if (!props.hasMaskLayer) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.addLayerMask,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.addLayerMaskHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BigChoice(
                    swatch: Colors.white,
                    label: l.revealAll,
                    onTap: () => editor.addLayerMask(layer.id),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigChoice(
                    swatch: Colors.black,
                    label: l.hideAll,
                    onTap: () => editor.addLayerMask(layer.id, hideAll: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: brush,
      builder: (context, _) {
        final k = brush.kind;
        Widget tool(MaskToolKind kind, IconData icon, String label) =>
            PanelTile(
              icon: icon,
              label: label,
              selected: k == kind,
              width: 72,
              onTap: () => brush.kind = kind,
            );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: mask preview, title and mask actions.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  MaskThumb(layer: layer, size: 44, selected: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.layerMask,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          props.maskEnabled ? l.maskOn : l.maskOff,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: props.maskEnabled
                                ? scheme.primary
                                : scheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: props.maskEnabled ? l.maskOff : l.maskOn,
                    onPressed: () =>
                        editor.setMaskEnabled(layer.id, !props.maskEnabled),
                    icon: Icon(
                      props.maskEnabled
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: l.showMask,
                    isSelected: brush.overlay,
                    onPressed: () => brush.overlay = !brush.overlay,
                    icon: const Icon(Icons.layers_outlined),
                    selectedIcon: Icon(
                      Icons.layers_rounded,
                      color: scheme.error,
                    ),
                  ),
                  IconButton(
                    tooltip: l.invert,
                    onPressed: () => editor.invertMask(layer.id),
                    icon: const Icon(Icons.invert_colors_rounded),
                  ),
                  IconButton(
                    tooltip: l.deleteMask,
                    onPressed: () async {
                      if (await showConfirmDialog(
                        context,
                        title: l.deleteMaskConfirm,
                        message: l.undoHint,
                        confirmLabel: l.deleteMask,
                      )) {
                        editor.clearMask(layer.id);
                      }
                    },
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
            ),
            TileRow(
              children: [
                tool(MaskToolKind.brush, Icons.brush_rounded, l.brush),
                tool(
                  MaskToolKind.eraser,
                  Icons.auto_fix_normal_rounded,
                  l.eraser,
                ),
                tool(MaskToolKind.gradient, Icons.gradient_rounded, l.gradient),
                tool(MaskToolKind.lasso, Icons.gesture_rounded, l.lasso),
                tool(MaskToolKind.pen, Icons.polyline_rounded, l.pen),
                PanelTile(
                  iconWidget: const _Swatch(Colors.black, size: 22),
                  icon: null,
                  width: 72,
                  label: l.hideAll,
                  onTap: () => editor.fillMask(layer.id, 0),
                ),
                PanelTile(
                  iconWidget: const _Swatch(Colors.white, size: 22),
                  icon: null,
                  width: 72,
                  label: l.revealAll,
                  onTap: () => editor.fillMask(layer.id, 1),
                ),
              ],
            ),
            // Paint colour: black / grey / white, like Photoshop's
            // foreground colour on a mask (X swaps).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Row(
                children: [
                  _Swatch(
                    Color.lerp(Colors.black, Colors.white, brush.paintLevel)!,
                    size: 34,
                    ring: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: l.swapColors,
                    visualDensity: VisualDensity.compact,
                    onPressed: brush.swap,
                    icon: const Icon(Icons.swap_horiz_rounded),
                  ),
                  const SizedBox(width: 4),
                  for (final (v, c) in const [
                    (0.0, Colors.black),
                    (0.5, Color(0xFF808080)),
                    (1.0, Colors.white),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: InkResponse(
                        onTap: () => brush.level = v,
                        radius: 22,
                        child: _Swatch(
                          c,
                          size: 28,
                          ring: (brush.level - v).abs() < 0.01
                              ? scheme.primary
                              : null,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      k == MaskToolKind.eraser ? l.eraserHint : l.maskColorHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PixSlider(
              label: l.grey,
              value: brush.level,
              min: 0,
              max: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => brush.level = v,
            ),
            if (k == MaskToolKind.gradient)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SegmentedButton<MaskShape>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: MaskShape.linear,
                      icon: const Icon(Icons.linear_scale_rounded, size: 18),
                      label: Text(l.linear),
                    ),
                    ButtonSegment(
                      value: MaskShape.radial,
                      icon: const Icon(Icons.radio_button_checked, size: 18),
                      label: Text(l.radial),
                    ),
                  ],
                  selected: {brush.gradient},
                  onSelectionChanged: (s) => brush.gradient = s.first,
                ),
              ),
            if (k == MaskToolKind.brush || k == MaskToolKind.eraser)
              PixSlider(
                label: l.brushSize,
                value: brush.size,
                min: 2,
                max: 300,
                defaultValue: 24,
                onChanged: (v) => brush.size = v,
              ),
            if (k != MaskToolKind.gradient)
              PixSlider(
                label: l.softness,
                value: brush.softness,
                min: 0,
                max: 1,
                defaultValue: 0.2,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => brush.softness = v,
              ),
            PixSlider(
              label: l.opacity,
              value: brush.opacity,
              min: 0.01,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => brush.opacity = v,
            ),
            if (k == MaskToolKind.pen) ...[
              PenPanel(state: ui.penState, onDone: () {}, compact: true),
              ListenableBuilder(
                listenable: maskPen,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: maskPen.hasShape
                              ? () => _applyPen(keepOnly: false)
                              : null,
                          icon: const Icon(Icons.format_color_fill_rounded),
                          label: Text(
                            l.fillInside,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: maskPen.hasShape
                              ? () => _applyPen(keepOnly: true)
                              : null,
                          icon: const Icon(Icons.crop_free_rounded),
                          label: Text(
                            l.keepInside,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton.filledTonal(
                        tooltip: l.cancel,
                        onPressed: maskPen.contours.isEmpty
                            ? null
                            : () {
                                maskPen.clear();
                                ui.penState.reset();
                                ui.penState.target = maskPen;
                              },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Mask properties (Photoshop's Density and Feather).
            PanelLabel(l.properties),
            PixSlider(
              label: l.density,
              value: props.maskDensity,
              min: 0,
              max: 1,
              defaultValue: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => editor.setMaskDensity(layer.id, v, live: true),
              onChangeEnd: (_) => editor.commit('mask_density'),
            ),
            PixSlider(
              label: l.feather,
              value: props.maskFeather,
              min: 0,
              max: 250,
              defaultValue: 0,
              format: (v) => '${v.round()} px',
              onChanged: (v) => editor.setMaskFeather(layer.id, v, live: true),
              onChangeEnd: (_) => editor.commit('mask_feather'),
            ),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(l.maskHidesEffects),
              subtitle: Text(l.maskHidesEffectsHint),
              value: props.maskHidesEffects,
              onChanged: (v) => editor.updateProps(
                layer.id,
                (p) => p.copyWith(maskHidesEffects: v),
                label: 'mask_hides_effects',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                switch (k) {
                  MaskToolKind.brush => l.maskHintBrush,
                  MaskToolKind.eraser => l.maskHintBrush,
                  MaskToolKind.gradient => l.maskHintGradient,
                  MaskToolKind.lasso => l.maskHintLasso,
                  MaskToolKind.pen => l.maskHintPen,
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, {this.size = 28, this.ring});
  final Color color;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(
        color: ring ?? Theme.of(context).colorScheme.outlineVariant,
        width: ring == null ? 1 : 2.5,
      ),
    ),
  );
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.swatch,
    required this.label,
    required this.onTap,
  });
  final Color swatch;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
