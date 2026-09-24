import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../document/model/guides.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../editor_scope.dart';
import 'panel_common.dart';

/// Grid settings: visibility, columns × rows, rotation, look, and the
/// on-canvas line editing mode.
class GridPanel extends StatelessWidget {
  const GridPanel({super.key, required this.editor, required this.ui});
  final EditorController editor;
  final EditorUiState ui;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final guides = editor.document.guides;
    final g = guides.grid;
    void live(GridSpec Function(GridSpec g) f) =>
        editor.updateGuides((x) => x.copyWith(grid: f(x.grid)), live: true);
    void commit([_]) => editor.commit('guides');
    final editing = ui.mode == ToolMode.grid;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          secondary: const Icon(Icons.grid_4x4_rounded),
          title: Text(l.showGrid),
          value: g.visible,
          onChanged: (v) => editor.updateGuides(
            (x) => x.copyWith(grid: x.grid.copyWith(visible: v)),
          ),
        ),
        PixSlider(
          label: l.columns,
          value: g.columns.toDouble(),
          min: 1,
          max: 24,
          defaultValue: 3,
          onChanged: (v) => live(
            (x) =>
                x.copyWith(columns: v.round(), visible: true, resetLines: true),
          ),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.rows,
          value: g.rows.toDouble(),
          min: 1,
          max: 24,
          defaultValue: 3,
          onChanged: (v) => live(
            (x) => x.copyWith(rows: v.round(), visible: true, resetLines: true),
          ),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.rotation,
          value: g.rotation,
          min: -90,
          max: 90,
          defaultValue: 0,
          format: (v) => '${v.round()}°',
          onChanged: (v) =>
              live((x) => x.copyWith(rotation: v.roundToDouble())),
          onChangeEnd: commit,
        ),
        PixSlider(
          label: l.opacity,
          value: g.opacity,
          min: 0.05,
          max: 1,
          defaultValue: 0.6,
          format: (v) => '${(v * 100).round()}%',
          onChanged: (v) => live((x) => x.copyWith(opacity: v)),
          onChangeEnd: commit,
        ),
        ColorStrip(
          value: g.color,
          onChanged: (c, {required live}) {
            if (c == null) return;
            editor.updateGuides(
              (x) => x.copyWith(grid: x.grid.copyWith(color: c)),
              live: live,
            );
          },
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(l.editLines),
                selected: editing,
                onSelected: (on) {
                  ui.mode = on ? ToolMode.grid : ToolMode.move;
                  if (on && !g.visible) {
                    editor.updateGuides(
                      (x) => x.copyWith(grid: x.grid.copyWith(visible: true)),
                    );
                  }
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.view_column_rounded, size: 18),
                label: Text(l.evenSpacing),
                onPressed: g.isCustom
                    ? () => editor.updateGuides(
                        (x) =>
                            x.copyWith(grid: x.grid.copyWith(resetLines: true)),
                      )
                    : null,
              ),
              ActionChip(
                avatar: const Icon(Icons.clear_all_rounded, size: 18),
                label: Text(l.clearGuides),
                onPressed: guides.vertical.isEmpty && guides.horizontal.isEmpty
                    ? null
                    : () => editor.updateGuides(
                        (x) => x.copyWith(
                          vertical: const [],
                          horizontal: const [],
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (editing)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              l.gridEditHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// What moving layers snap to.
class SnapPanel extends StatelessWidget {
  const SnapPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        Widget tile(
          IconData icon,
          String label,
          bool value,
          ValueChanged<bool> set,
        ) => SwitchListTile.adaptive(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          secondary: Icon(icon),
          title: Text(label),
          value: value,
          onChanged: s.snapping ? set : null,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.join_inner_rounded),
              title: Text(
                l.snapping,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              value: s.snapping,
              onChanged: (v) => s.snapping = v,
            ),
            PanelLabel(l.snapTo),
            tile(
              Icons.crop_free_rounded,
              l.snapCanvas,
              s.snapCanvas,
              (v) => s.snapCanvas = v,
            ),
            tile(
              Icons.border_vertical_rounded,
              l.snapGuides,
              s.snapGuides,
              (v) => s.snapGuides = v,
            ),
            tile(
              Icons.auto_awesome_mosaic_rounded,
              l.snapLayers,
              s.snapLayers,
              (v) => s.snapLayers = v,
            ),
            tile(
              Icons.rotate_90_degrees_ccw_rounded,
              l.snapAngles,
              s.snapAngles,
              (v) => s.snapAngles = v,
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
