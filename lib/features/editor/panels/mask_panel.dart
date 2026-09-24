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
import '../../../document/render/document_renderer.dart';
import 'panel_common.dart';

/// Layer mask: hide or reveal parts of the layer with a brush, lasso or
/// pen polygon. While this panel is open the canvas paints the mask.
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

  /// Turns the pen outline(s) into mask strokes: hide what is inside, or
  /// keep only what is inside.
  void _applyPen({required bool hideInside}) {
    final soft = ui.maskBrush.softness;
    final shapes = [
      for (final c in maskPen.contours)
        if (c.nodes.length >= 3) c.copyWith(closed: true),
    ];
    if (shapes.isEmpty) return;
    final r = layerLocalRect(layer).inflate(100000);
    editor.addMaskStrokes(layer.id, [
      if (!hideInside)
        MaskStroke(
          mode: MaskMode.hide,
          shape: MaskShape.area,
          points: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
        ),
      for (final c in shapes)
        MaskStroke(
          mode: hideInside ? MaskMode.hide : MaskMode.show,
          shape: MaskShape.area,
          points: const [],
          contour: c,
          softness: soft,
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
    final brush = ui.maskBrush;
    final props = layer.props;
    return ListenableBuilder(
      listenable: brush,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: SegmentedButton<MaskMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: MaskMode.hide,
                  icon: const Icon(Icons.auto_fix_normal_rounded, size: 18),
                  label: Text(l.maskHide),
                ),
                ButtonSegment(
                  value: MaskMode.show,
                  icon: const Icon(Icons.brush_rounded, size: 18),
                  label: Text(l.maskShow),
                ),
              ],
              selected: {brush.mode},
              onSelectionChanged: (s) => brush.mode = s.first,
            ),
          ),
          TileRow(
            children: [
              for (final (k, icon, label) in [
                (MaskToolKind.brush, Icons.brush_rounded, l.brush),
                (MaskToolKind.lasso, Icons.gesture_rounded, l.lasso),
                (MaskToolKind.pen, Icons.polyline_rounded, l.pen),
              ])
                PanelTile(
                  icon: icon,
                  label: label,
                  selected: brush.kind == k,
                  onTap: () => brush.kind = k,
                ),
              PanelTile(
                icon: Icons.invert_colors_rounded,
                label: l.invert,
                onTap: () => editor.invertMask(layer.id),
              ),
              PanelTile(
                icon: props.maskEnabled
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                label: props.maskEnabled ? l.maskOn : l.maskOff,
                selected: !props.maskEnabled,
                onTap: props.mask.isEmpty
                    ? null
                    : () => editor.setMaskEnabled(layer.id, !props.maskEnabled),
              ),
              PanelTile(
                icon: Icons.layers_clear_rounded,
                label: l.clearMask,
                onTap: props.mask.isEmpty
                    ? null
                    : () async {
                        if (await showConfirmDialog(
                          context,
                          title: l.clearMaskConfirm,
                          message: l.undoHint,
                          confirmLabel: l.clearMask,
                        )) {
                          editor.clearMask(layer.id);
                        }
                      },
              ),
            ],
          ),
          if (brush.kind == MaskToolKind.brush)
            PixSlider(
              label: l.brushSize,
              value: brush.size,
              min: 4,
              max: 200,
              defaultValue: 24,
              onChanged: (v) => brush.size = v,
            ),
          PixSlider(
            label: l.softness,
            value: brush.softness,
            min: 0,
            max: 1,
            defaultValue: 0.2,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => brush.softness = v,
          ),
          if (brush.kind == MaskToolKind.pen) ...[
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
                            ? () => _applyPen(hideInside: true)
                            : null,
                        icon: const Icon(Icons.auto_fix_normal_rounded),
                        label: Text(
                          l.hideInside,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: maskPen.hasShape
                            ? () => _applyPen(hideInside: false)
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
            child: Text(
              switch (brush.kind) {
                MaskToolKind.brush => l.maskHintBrush,
                MaskToolKind.lasso => l.maskHintLasso,
                MaskToolKind.pen => l.maskHintPen,
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
