import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../editor/editor_controller.dart';
import '../../../editor/selection/pixel_selection.dart';
import '../../../editor/selection/selection_controller.dart';
import '../../../editor/tools/select_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../editor_scope.dart';
import 'panel_common.dart';

/// Photoshop's Select menu as one bottom panel: where to select (whole
/// canvas or one layer), the selection tools, how a new selection combines
/// with the current one, tool options, Modify (feather, expand, contract,
/// smooth…) and what to do with the selection (mask, copy / cut to a
/// layer, delete, fill, crop).
class SelectionPanel extends StatelessWidget {
  const SelectionPanel({
    super.key,
    required this.editor,
    required this.ui,
    required this.tool,
    required this.pen,
  });

  final EditorController editor;
  final EditorUiState ui;
  final SelectTool tool;
  final SelectionPenTarget pen;

  SelectionController get sel => ui.selection;

  /// The layer the actions work on: the target layer, else the selected one.
  String? get _layerId {
    final t = sel.targetId;
    if (t != null && editor.document.contains(t)) return t;
    return editor.selectedId;
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _amount(
    BuildContext context, {
    required String title,
    required double initial,
    required double max,
    required void Function(double v) apply,
  }) async {
    final l = AppLocalizations.of(context);
    var v = initial;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          content: PixSlider(
            label: '',
            value: v,
            min: 0,
            max: max,
            defaultValue: initial,
            format: (x) => '${x.round()} px',
            onChanged: (x) => setState(() => v = x),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.apply),
            ),
          ],
        ),
      ),
    );
    if (ok == true && v > 0) apply(v);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([sel, pen]),
      builder: (context, _) {
        final has = sel.hasSelection;
        final target = sel.targetId;
        final targetLayer = target == null
            ? null
            : editor.document.layerById(target);
        final picked = editor.selectedLayer;

        Widget toolTile(SelectToolKind k, IconData icon, String label) =>
            PanelTile(
              icon: icon,
              label: label,
              width: 74,
              selected: sel.tool == k,
              onTap: () {
                tool.polygon.clear();
                sel.tool = k;
              },
            );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 3,
              child: sel.busy
                  ? const LinearProgressIndicator(minHeight: 3)
                  : null,
            ),
            // Title, target and undo.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.highlight_alt_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.selection,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.undo,
                    visualDensity: VisualDensity.compact,
                    onPressed: sel.canUndo ? sel.undo : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                  IconButton(
                    tooltip: l.redo,
                    visualDensity: VisualDensity.compact,
                    onPressed: sel.canRedo ? sel.redo : null,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _Choice(
                      icon: Icons.crop_free_rounded,
                      label: l.wholeCanvas,
                      selected: target == null,
                      onTap: () => sel.targetId = null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Choice(
                      icon: Icons.layers_rounded,
                      label:
                          targetLayer?.props.name ??
                          (picked == null
                              ? l.thisLayer
                              : '${l.thisLayer}: ${picked.props.name}'),
                      selected: targetLayer != null,
                      onTap: picked == null && targetLayer == null
                          ? () => _toast(context, l.needLayerFirst)
                          : () => sel.targetId = picked?.id ?? targetLayer!.id,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TileRow(
              children: [
                toolTile(
                  SelectToolKind.rectangle,
                  Icons.crop_square_rounded,
                  l.selRectangle,
                ),
                toolTile(
                  SelectToolKind.ellipse,
                  Icons.circle_outlined,
                  l.selEllipse,
                ),
                toolTile(
                  SelectToolKind.lasso,
                  Icons.gesture_rounded,
                  l.selLasso,
                ),
                toolTile(
                  SelectToolKind.polygon,
                  Icons.pentagon_outlined,
                  l.selPolygon,
                ),
                toolTile(SelectToolKind.pen, Icons.draw_rounded, l.pen),
                toolTile(
                  SelectToolKind.magicWand,
                  Icons.auto_fix_high_rounded,
                  l.magicWand,
                ),
                toolTile(
                  SelectToolKind.colorRange,
                  Icons.colorize_rounded,
                  l.colorRange,
                ),
                toolTile(
                  SelectToolKind.luminance,
                  Icons.brightness_6_rounded,
                  l.luminance,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _ModeBar(sel: sel),
            _options(context, l),
            PanelLabel(l.useSelection),
            TileRow(
              children: [
                PanelTile(
                  icon: Icons.gradient_rounded,
                  label: l.layerMask,
                  onTap: has ? () => _mask(context, l) : null,
                ),
                PanelTile(
                  icon: Icons.copy_all_rounded,
                  label: l.copyToLayer,
                  onTap: has ? () => _copy(context, l, cut: false) : null,
                ),
                PanelTile(
                  icon: Icons.content_cut_rounded,
                  label: l.cutToLayer,
                  onTap: has ? () => _copy(context, l, cut: true) : null,
                ),
                PanelTile(
                  icon: Icons.delete_outline_rounded,
                  label: l.delete,
                  onTap: has ? () => _clear(context, l) : null,
                ),
                PanelTile(
                  icon: Icons.format_color_fill_rounded,
                  label: l.fillSelection,
                  onTap: has ? () => _fill(context, l) : null,
                ),
                PanelTile(
                  icon: Icons.crop_rounded,
                  label: l.cropToSelection,
                  onTap: has ? () => _crop() : null,
                ),
              ],
            ),
            PanelLabel(l.modify),
            TileRow(
              children: [
                PanelTile(
                  icon: Icons.select_all_rounded,
                  label: l.selectAll,
                  onTap: () => sel.selectAll(editor.document),
                ),
                PanelTile(
                  icon: Icons.deselect_rounded,
                  label: l.deselect,
                  onTap: has ? sel.deselect : null,
                ),
                PanelTile(
                  icon: Icons.flip_rounded,
                  label: l.invert,
                  onTap: () => sel.invert(editor.document),
                ),
                PanelTile(
                  icon: Icons.layers_rounded,
                  label: l.layerPixels,
                  onTap: _layerId == null
                      ? null
                      : () => sel.layerPixels(editor, _layerId!),
                ),
                PanelTile(
                  icon: Icons.blur_on_rounded,
                  label: l.feather,
                  onTap: has
                      ? () => _amount(
                          context,
                          title: l.feather,
                          initial: 10,
                          max: 200,
                          apply: (v) => sel.modify((s) => s.feathered(v)),
                        )
                      : null,
                ),
                PanelTile(
                  icon: Icons.open_in_full_rounded,
                  label: l.expandSel,
                  onTap: has
                      ? () => _amount(
                          context,
                          title: l.expandSel,
                          initial: 8,
                          max: 200,
                          apply: (v) => sel.modify((s) => s.expanded(v)),
                        )
                      : null,
                ),
                PanelTile(
                  icon: Icons.close_fullscreen_rounded,
                  label: l.contractSel,
                  onTap: has
                      ? () => _amount(
                          context,
                          title: l.contractSel,
                          initial: 8,
                          max: 200,
                          apply: (v) => sel.modify((s) => s.expanded(-v)),
                        )
                      : null,
                ),
                PanelTile(
                  icon: Icons.waves_rounded,
                  label: l.smoothSel,
                  onTap: has
                      ? () => _amount(
                          context,
                          title: l.smoothSel,
                          initial: 6,
                          max: 100,
                          apply: (v) => sel.modify((s) => s.smoothed(v)),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _hint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Row(
        children: [
          Icon(
            Icons.touch_app_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options(BuildContext context, AppLocalizations l) {
    switch (sel.tool) {
      case SelectToolKind.rectangle || SelectToolKind.ellipse:
        return _hint(context, l.hintSelDrag);
      case SelectToolKind.lasso:
        return _hint(context, l.hintSelLasso);
      case SelectToolKind.polygon:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hint(context, l.hintSelPolygon),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (tool.polygon.isNotEmpty) tool.polygon.removeLast();
                        sel.ants.value++;
                      },
                      icon: const Icon(Icons.undo_rounded),
                      label: Text(l.undoPoint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => tool.applyPolygon(editor, sel),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l.closeShape),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case SelectToolKind.pen:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hint(context, l.hintSelPen),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: FilledButton.icon(
                onPressed: pen.hasShape
                    ? () async {
                        final path = pen.toPath();
                        pen.clear();
                        ui.penState.reset();
                        ui.penState.target = pen;
                        await sel.addPath(editor, path);
                      }
                    : null,
                icon: const Icon(Icons.highlight_alt_rounded),
                label: Text(l.makeSelection),
              ),
            ),
          ],
        );
      case SelectToolKind.magicWand:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hint(context, l.hintSelWand),
            PixSlider(
              label: l.tolerance,
              value: sel.tolerance.toDouble(),
              min: 0,
              max: 255,
              defaultValue: 32,
              format: (v) => '${v.round()}',
              onChanged: (v) => sel.tolerance = v.round(),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(l.contiguous),
              value: sel.contiguous,
              onChanged: (v) => sel.contiguous = v,
            ),
          ],
        );
      case SelectToolKind.colorRange:
        final c = sel.rangeColor;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _hint(context, l.hintSelRange)),
                if (c != null)
                  Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsetsDirectional.only(end: 20, top: 6),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  ),
              ],
            ),
            PixSlider(
              label: l.fuzziness,
              value: sel.fuzziness.toDouble(),
              min: 1,
              max: 255,
              defaultValue: 60,
              format: (v) => '${v.round()}',
              onChanged: (v) => unawaited(sel.setFuzziness(editor, v.round())),
            ),
          ],
        );
      case SelectToolKind.luminance:
        void run() => unawaited(sel.luminance(editor));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (p, label, icon) in [
                    (
                      LuminancePreset.shadows,
                      l.shadowsRange,
                      Icons.brightness_3_rounded,
                    ),
                    (
                      LuminancePreset.midtones,
                      l.midtonesRange,
                      Icons.brightness_medium_rounded,
                    ),
                    (
                      LuminancePreset.highlights,
                      l.highlightsRange,
                      Icons.brightness_7_rounded,
                    ),
                  ])
                    ActionChip(
                      avatar: Icon(icon, size: 18),
                      label: Text(label),
                      onPressed: () {
                        sel.lumPreset(p);
                        run();
                      },
                    ),
                ],
              ),
            ),
            PixSlider(
              label: l.rangeFrom,
              value: sel.lumFrom,
              min: 0,
              max: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => sel.setLuminance(from: v),
              onChangeEnd: (_) => run(),
            ),
            PixSlider(
              label: l.rangeTo,
              value: sel.lumTo,
              min: 0,
              max: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => sel.setLuminance(to: v),
              onChangeEnd: (_) => run(),
            ),
            PixSlider(
              label: l.softness,
              value: sel.lumSoftness,
              min: 0,
              max: 0.5,
              defaultValue: 0.12,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => sel.setLuminance(softness: v),
              onChangeEnd: (_) => run(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: FilledButton.icon(
                onPressed: run,
                icon: const Icon(Icons.highlight_alt_rounded),
                label: Text(l.selectAction),
              ),
            ),
          ],
        );
    }
  }

  // ------------------------------------------------------------ actions

  PixelSelection? _need(BuildContext context, AppLocalizations l) {
    final s = sel.current;
    if (s == null) _toast(context, l.nothingSelected);
    return s;
  }

  Future<void> _mask(BuildContext context, AppLocalizations l) async {
    final s = _need(context, l);
    final id = _layerId;
    if (s == null) return;
    if (id == null) return _toast(context, l.needLayerFirst);
    if (await editor.maskFromSelection(id, s)) sel.deselect();
  }

  Future<void> _copy(
    BuildContext context,
    AppLocalizations l, {
    required bool cut,
  }) async {
    final s = _need(context, l);
    if (s == null) return;
    final source = cut ? _layerId : sel.targetId;
    if (cut && source == null) return _toast(context, l.needLayerFirst);
    await editor.copySelectionToLayer(
      s,
      sourceId: source,
      cut: cut,
      name: l.selection,
    );
  }

  Future<void> _clear(BuildContext context, AppLocalizations l) async {
    final s = _need(context, l);
    final id = _layerId;
    if (s == null) return;
    if (id == null) return _toast(context, l.needLayerFirst);
    await editor.clearSelection(id, s);
  }

  Future<void> _fill(BuildContext context, AppLocalizations l) async {
    final s = _need(context, l);
    if (s == null) return;
    final color = await showPixColorPicker(
      context,
      initial: Theme.of(context).colorScheme.primary,
    );
    if (color == null) return;
    await editor.fillSelection(s, color, name: l.fillSelection);
  }

  void _crop() {
    final s = sel.current;
    if (s == null) return;
    if (editor.cropToSelection(s)) sel.deselect();
  }
}

/// New / Add / Subtract / Intersect.
class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.sel});
  final SelectionController sel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (SelectionMode.replace, Icons.crop_din_rounded, l.selNew),
      (SelectionMode.add, Icons.add_box_outlined, l.selAdd),
      (
        SelectionMode.subtract,
        Icons.indeterminate_check_box_outlined,
        l.selSubtract,
      ),
      (SelectionMode.intersect, Icons.join_inner_rounded, l.selIntersect),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
        ),
        child: Row(
          children: [
            for (final (m, icon, label) in items)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => sel.mode = m,
                  child: AnimatedContainer(
                    duration: PixTokens.fast,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: sel.mode == m ? scheme.primary : null,
                      borderRadius: BorderRadius.circular(
                        PixTokens.radiusM - 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: sel.mode == m
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: sel.mode == m
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A wide target choice (whole canvas / layer).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PixTokens.radiusM),
      child: AnimatedContainer(
        duration: PixTokens.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
