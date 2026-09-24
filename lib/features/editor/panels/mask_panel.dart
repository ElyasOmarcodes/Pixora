import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../document/model/mask.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/tools/mask_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../editor_scope.dart';
import 'panel_common.dart';

/// Layer mask: hide or reveal parts of the layer with a brush, lasso or
/// pen polygon. While this panel is open the canvas paints the mask.
class MaskPanel extends StatelessWidget {
  const MaskPanel({
    super.key,
    required this.editor,
    required this.ui,
    required this.layer,
  });
  final EditorController editor;
  final EditorUiState ui;
  final Layer layer;

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
                    : () => editor.clearMask(layer.id),
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
          if (brush.kind == MaskToolKind.pen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: brush.penPoints.length >= 3
                          ? () => MaskTool.applyPen(editor, brush)
                          : null,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l.applyShape),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: l.undo,
                    onPressed: brush.penPoints.isEmpty
                        ? null
                        : brush.undoPenPoint,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: l.cancel,
                    onPressed: brush.penPoints.isEmpty ? null : brush.clearPen,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
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
