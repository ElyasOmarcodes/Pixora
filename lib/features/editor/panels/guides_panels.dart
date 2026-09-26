import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/units/units.dart';
import '../../../document/model/guides.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/confirm_dialog.dart';
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
                    : () async {
                        if (await showConfirmDialog(
                          context,
                          title: l.clearGuidesConfirm,
                          message: l.undoHint,
                          confirmLabel: l.clearGuides,
                        )) {
                          editor.updateGuides(
                            (x) => x.copyWith(
                              vertical: const [],
                              horizontal: const [],
                            ),
                          );
                        }
                      },
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

/// Rulers & guides settings, Photoshop style: show rulers, units, guide
/// colour, precise new guides and clearing.
class RulerPanel extends StatefulWidget {
  const RulerPanel({super.key, required this.editor});
  final EditorController editor;

  @override
  State<RulerPanel> createState() => _RulerPanelState();
}

class _RulerPanelState extends State<RulerPanel> {
  bool _vertical = true;
  final _value = TextEditingController();

  static const _guideColors = [
    Color(0xFF00C2FF),
    Color(0xFFFF2D95),
    Color(0xFF22C55E),
    Color(0xFFFFB020),
    Color(0xFF7C5CFF),
    Color(0xFFFF4D4D),
  ];

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _addGuide(AppSettings s) {
    final editor = widget.editor;
    final doc = editor.document;
    final v = double.tryParse(_value.text.replaceAll(',', '.'));
    if (v == null) return;
    final px = s.rulerUnit.toPx(
      v,
      doc.dpi,
      reference: _vertical ? doc.width : doc.height,
    );
    final limit = _vertical ? doc.width : doc.height;
    if (px < 0 || px > limit) return;
    editor.updateGuides(
      (g) => _vertical
          ? g.copyWith(vertical: [...g.vertical, px])
          : g.copyWith(horizontal: [...g.horizontal, px]),
    );
    _value.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = AppScope.of(context).settings;
    final editor = widget.editor;
    return ListenableBuilder(
      listenable: Listenable.merge([s, editor]),
      builder: (context, _) {
        final guides = editor.document.guides;
        final count = guides.vertical.length + guides.horizontal.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.straighten_rounded),
              title: Text(
                l.showRulers,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              value: s.showRulers,
              onChanged: (v) => s.showRulers = v,
            ),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: const Icon(Icons.width_normal_rounded),
              title: Text(l.rulerShowLayer),
              value: s.rulerLayer,
              onChanged: s.showRulers ? (v) => s.rulerLayer = v : null,
            ),
            PanelLabel(l.units),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final u in MeasureUnit.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                        label: Text(u.suffix),
                        selected: s.rulerUnit == u,
                        onSelected: (_) => s.rulerUnit = u,
                      ),
                    ),
                ],
              ),
            ),
            PanelLabel(l.guideColor),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final c in _guideColors)
                    GestureDetector(
                      onTap: () => s.guideColor = c,
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.guideColor.toARGB32() == c.toARGB32()
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            PanelLabel(l.newGuide),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: [
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.border_vertical_rounded),
                        tooltip: l.vertical,
                      ),
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.border_horizontal_rounded),
                        tooltip: l.horizontal,
                      ),
                    ],
                    selected: {_vertical},
                    onSelectionChanged: (v) =>
                        setState(() => _vertical = v.first),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l.position,
                        suffixText: s.rulerUnit.suffix,
                        filled: true,
                        fillColor: scheme.onSurface.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _addGuide(s),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: l.add,
                    onPressed: () => _addGuide(s),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final (i, x) in guides.vertical.indexed)
                      InputChip(
                        avatar: Icon(
                          Icons.border_vertical_rounded,
                          size: 18,
                          color: s.guideColor,
                        ),
                        label: Text(
                          '${s.rulerUnit.format(s.rulerUnit.fromPx(x, editor.document.dpi, reference: editor.document.width))} ${s.rulerUnit.suffix}',
                          textDirection: TextDirection.ltr,
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        onDeleted: () => editor.updateGuides(
                          (g) => g.copyWith(
                            vertical: [...g.vertical]..removeAt(i),
                          ),
                        ),
                      ),
                    for (final (i, y) in guides.horizontal.indexed)
                      InputChip(
                        avatar: Icon(
                          Icons.border_horizontal_rounded,
                          size: 18,
                          color: s.guideColor,
                        ),
                        label: Text(
                          '${s.rulerUnit.format(s.rulerUnit.fromPx(y, editor.document.dpi, reference: editor.document.height))} ${s.rulerUnit.suffix}',
                          textDirection: TextDirection.ltr,
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 18),
                        onDeleted: () => editor.updateGuides(
                          (g) => g.copyWith(
                            horizontal: [...g.horizontal]..removeAt(i),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.guidesCount(count),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: count == 0
                        ? null
                        : () async {
                            if (await showConfirmDialog(
                              context,
                              title: l.clearGuidesConfirm,
                              message: l.undoHint,
                              confirmLabel: l.clearGuides,
                            )) {
                              editor.updateGuides(
                                (x) => x.copyWith(
                                  vertical: const [],
                                  horizontal: const [],
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.clear_all_rounded),
                    label: Text(l.clearGuides),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Text(
                l.rulerHint,
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
