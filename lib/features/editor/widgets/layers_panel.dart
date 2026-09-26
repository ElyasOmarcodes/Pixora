import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/blend.dart';
import '../../../document/model/document.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/layer_transform.dart';
import '../../../document/render/document_renderer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/layer_style.dart';
import '../../../ui/widgets/checkerboard.dart';
import '../../../document/model/effect.dart';
import '../editor_scope.dart';
import '../effects_catalog.dart';
import 'layer_actions.dart';
import 'mask_thumb.dart';

/// One visible row of the layer tree.
class _Row {
  const _Row(this.layer, this.depth, this.parentId);
  final Layer layer;
  final int depth;
  final String? parentId;
}

enum _StateFilter { hidden, locked }

/// The layers panel: a Photoshop-style layer tree built for touch.
///
/// * Topmost layer first; groups fold open/closed; drag the handle to
///   reorder (also into and out of groups).
/// * Tap selects, Shift/Ctrl-click or the select mode adds to the
///   selection, long-press enters select mode.
/// * The selected row expands into an action strip: edit, quick edit,
///   duplicate, delete. Double-tap a name to rename it in place.
/// * Search by name/text and filter by kind, hidden or locked.
/// * Thumbnails are framed in their kind's color so types are recognisable
///   at a glance.
class LayersPanel extends StatefulWidget {
  const LayersPanel({
    super.key,
    required this.editor,
    required this.commands,
    this.onClose,
  });

  final EditorController editor;
  final LayerCommands commands;
  final VoidCallback? onClose;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

class _LayersPanelState extends State<LayersPanel> {
  final _search = TextEditingController();
  bool _searching = false;
  bool _selectMode = false;
  LayerKind? _kind;
  final Set<_StateFilter> _states = {};
  String? _renamingId;

  /// Layers whose effects list is folded (Photoshop shows it open).
  final Set<String> _fxFolded = {};

  EditorController get e => widget.editor;

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _kind != null || _states.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- rows

  List<_Row> _treeRows(PixDocument doc) {
    final rows = <_Row>[];
    void walk(List<Layer> list, int depth, String? parent) {
      for (final l in list.reversed) {
        rows.add(_Row(l, depth, parent));
        if (l is GroupLayer && l.expanded) walk(l.children, depth + 1, l.id);
      }
    }

    walk(doc.layers, 0, null);
    return rows;
  }

  List<_Row> _filteredRows(PixDocument doc) {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final l in doc.allLayers.reversed)
        if ((_kind == null || l.kind == _kind) &&
            (!_states.contains(_StateFilter.hidden) || !l.props.visible) &&
            (!_states.contains(_StateFilter.locked) || l.props.locked) &&
            (q.isEmpty ||
                l.props.name.toLowerCase().contains(q) ||
                (l is TextLayer && l.text.toLowerCase().contains(q))))
          _Row(l, 0, doc.parentOf(l.id)?.id),
    ];
  }

  void _onReorder(List<_Row> rows, int oldIndex, int newIndex) {
    final moved = rows[oldIndex];
    final rest = [...rows]..removeAt(oldIndex);
    if (newIndex >= rest.length) {
      // Dropped at the very bottom: bottom of the top level.
      e.moveLayer(moved.layer.id, parentId: null, index: 0);
      return;
    }
    // Dropped above `target` (display order is top-first): become its
    // sibling directly above it in paint order.
    final target = rest[newIndex];
    final doc = e.document;
    final siblings = doc
        .siblingsOf(target.layer.id)
        .where((l) => l.id != moved.layer.id)
        .toList();
    final ti = siblings.indexWhere((l) => l.id == target.layer.id);
    e.moveLayer(moved.layer.id, parentId: target.parentId, index: ti + 1);
  }

  // ---------------------------------------------------------- selection

  void _tap(Layer l, List<_Row> rows) {
    final k = HardwareKeyboard.instance;
    if (k.isShiftPressed && e.selectedId != null) {
      // Range select in display order.
      final ids = [for (final r in rows) r.layer.id];
      final a = ids.indexOf(e.selectedId!), b = ids.indexOf(l.id);
      if (a >= 0 && b >= 0) {
        e.selectMany(
          ids.sublist(math.min(a, b), math.max(a, b) + 1).reversed.toList(),
        );
        return;
      }
    }
    if (_selectMode || k.isControlPressed || k.isMetaPressed) {
      e.toggleSelect(l.id);
    } else {
      e.select(e.selectedIds.length == 1 && e.selectedId == l.id ? null : l.id);
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: e,
      builder: (context, _) {
        final doc = e.document;
        final rows = _filtering ? _filteredRows(doc) : _treeRows(doc);
        final count = doc.allLayers.length;
        return Column(
          children: [
            _header(context, l, theme, count),
            AnimatedSize(
              duration: PixTokens.medium,
              curve: PixTokens.emphasized,
              child: _selectMode && count > 0
                  ? _selectBar(l, theme, rows)
                  : const SizedBox(width: double.infinity),
            ),
            AnimatedSize(
              duration: PixTokens.medium,
              curve: PixTokens.emphasized,
              child: _searching
                  ? _searchBar(l)
                  : const SizedBox(width: double.infinity),
            ),
            if (_searching) _filterChips(l),
            Expanded(
              child: count == 0
                  ? _empty(l.noLayers, theme)
                  : rows.isEmpty
                  ? _empty(l.noMatches, theme)
                  : _list(rows),
            ),
            _ActionBar(
              editor: e,
              commands: widget.commands,
              onRename: (id) => setState(() => _renamingId = id),
            ),
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    int count,
  ) {
    final sel = e.selectedIds.length;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 4, 2),
      child: Row(
        children: [
          Icon(
            Icons.layers_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            l.layers,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AnimatedSwitcher(
              duration: PixTokens.fast,
              child: Text(
                sel > 1 ? l.selectedCount(sel) : l.layerCount(count),
                key: ValueKey(sel > 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: sel > 1
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: sel > 1 ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: l.searchLayers,
            isSelected: _searching,
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _search.clear();
                _kind = null;
                _states.clear();
              }
            }),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: l.selectMode,
            isSelected: _selectMode,
            onPressed: () => setState(() => _selectMode = !_selectMode),
            icon: const Icon(Icons.checklist_rounded),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: l.close,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }

  /// Select mode: a tri-state "all" box, the count, Select all / Unselect
  /// all and Done — the standard multi-select bar.
  Widget _selectBar(AppLocalizations l, ThemeData theme, List<_Row> rows) {
    final ids = [for (final r in rows) r.layer.id];
    final picked = ids.where(e.isSelected).length;
    final all = picked == ids.length && ids.isNotEmpty;
    void selectAll() => e.selectMany(ids.reversed.toList());
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(PixTokens.radiusM),
      ),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: all ? true : (picked == 0 ? false : null),
            onChanged: (_) => all ? e.deselect() : selectAll(),
          ),
          Expanded(
            child: Text(
              l.selectedCount(picked),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: all ? null : selectAll,
            child: Text(l.selectAll),
          ),
          TextButton(
            onPressed: picked == 0 ? null : e.deselect,
            child: Text(l.unselectAll),
          ),
          IconButton(
            tooltip: l.done,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _selectMode = false),
            icon: const Icon(Icons.check_rounded),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(AppLocalizations l) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: TextField(
      controller: _search,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        hintText: l.searchLayers,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => setState(_search.clear),
              ),
      ),
    ),
  );

  Widget _filterChips(AppLocalizations l) {
    Widget kindChip(LayerKind? k) {
      final selected = _kind == k;
      final color = k == null ? null : LayerStyle.color(k);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilterChip(
          showCheckmark: false,
          avatar: k == null
              ? null
              : Icon(LayerStyle.icon(k), size: 16, color: color),
          label: Text(k == null ? l.filterAll : LayerStyle.label(l, k)),
          selected: selected,
          selectedColor: color?.withValues(alpha: 0.18),
          onSelected: (_) => setState(() => _kind = k),
        ),
      );
    }

    Widget stateChip(_StateFilter f, IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FilterChip(
        showCheckmark: false,
        avatar: Icon(icon, size: 16),
        label: Text(label),
        selected: _states.contains(f),
        onSelected: (on) =>
            setState(() => on ? _states.add(f) : _states.remove(f)),
      ),
    );

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        children: [
          kindChip(null),
          for (final k in LayerKind.values) kindChip(k),
          stateChip(
            _StateFilter.hidden,
            Icons.visibility_off_rounded,
            l.hidden,
          ),
          stateChip(_StateFilter.locked, Icons.lock_rounded, l.locked),
        ],
      ),
    );
  }

  Widget _empty(String text, ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _list(List<_Row> rows) {
    Widget row(int i) {
      final r = rows[i];
      return _LayerRow(
        key: ValueKey(r.layer.id),
        index: i,
        row: r,
        editor: e,
        commands: widget.commands,
        selected: e.isSelected(r.layer.id),
        primary: e.selectedId == r.layer.id && !e.hasMultiSelection,
        selectMode: _selectMode,
        reorderable: !_filtering,
        breadcrumb: _filtering && r.parentId != null
            ? e.document.layerById(r.parentId)?.props.name
            : null,
        renaming: _renamingId == r.layer.id,
        fxOpen: !_fxFolded.contains(r.layer.id),
        onToggleFx: () => setState(() {
          if (!_fxFolded.remove(r.layer.id)) _fxFolded.add(r.layer.id);
        }),
        onTap: () => _tap(r.layer, rows),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          setState(() => _selectMode = true);
          if (!e.isSelected(r.layer.id)) e.toggleSelect(r.layer.id);
        },
        onStartRename: () => setState(() => _renamingId = r.layer.id),
        onEndRename: (name) {
          setState(() => _renamingId = null);
          if (name != null && name.trim().isNotEmpty) {
            e.rename(r.layer.id, name.trim());
          }
        },
      );
    }

    if (_filtering) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        itemCount: rows.length,
        itemBuilder: (_, i) => row(i),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: rows.length,
      proxyDecorator: (child, _, a) => Material(
        color: Colors.transparent,
        elevation: 10 * a.value,
        borderRadius: BorderRadius.circular(PixTokens.radiusM),
        child: child,
      ),
      onReorderItem: (o, n) => _onReorder(rows, o, n),
      itemBuilder: (_, i) => row(i),
    );
  }
}

// ======================================================================

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.row,
    required this.editor,
    required this.commands,
    required this.selected,
    required this.primary,
    required this.selectMode,
    required this.reorderable,
    required this.breadcrumb,
    required this.renaming,
    required this.fxOpen,
    required this.onToggleFx,
    required this.onTap,
    required this.onLongPress,
    required this.onStartRename,
    required this.onEndRename,
  });

  final int index;
  final bool fxOpen;
  final VoidCallback onToggleFx;
  final _Row row;
  final EditorController editor;
  final LayerCommands commands;
  final bool selected;
  final bool primary;
  final bool selectMode;
  final bool reorderable;
  final String? breadcrumb;
  final bool renaming;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onStartRename;
  final ValueChanged<String?> onEndRename;

  Layer get layer => row.layer;

  String _subtitle(AppLocalizations l) {
    final p = layer.props;
    final parts = <String>[
      ?breadcrumb,
      if (layer is TextLayer)
        (layer as TextLayer).text.replaceAll('\n', ' ')
      else if (layer is GroupLayer)
        l.layerCount((layer as GroupLayer).children.length)
      else
        LayerStyle.label(l, layer.kind),
      if (p.blendMode != PixBlendMode.normal) p.blendMode.label,
      if (p.opacity < 1) '${(p.opacity * 100).round()}%',
    ];
    return parts.join(' · ');
  }

  void _primaryEdit() {
    editor.select(layer.id);
    switch (layer) {
      case TextLayer t:
        commands.editText(t);
      case RasterLayer _:
        commands.openPanel(ToolPanel.adjust);
      case ShapeLayer _:
        commands.openPanel(ToolPanel.shapeStyle);
      case IconLayer i:
        commands.changeIcon(i);
      case PathLayer _:
        commands.openPanel(ToolPanel.pen);
      case DrawingLayer _:
        commands.openPanel(ToolPanel.brush);
      case GroupLayer g:
        editor.setExpanded(g.id, !g.expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = layer.props;
    final kindColor = LayerStyle.color(layer.kind);
    final dim = !p.visible;
    final effects = listedEffects(layer);
    final hasFx = effects.isNotEmpty || p.stroke != null;
    final linked = p.link != null && editor.isLinked(layer.id);

    final leading = selectMode
        ? Checkbox(
            value: selected,
            visualDensity: VisualDensity.compact,
            onChanged: (_) => editor.toggleSelect(layer.id),
          )
        : reorderable
        ? ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Icon(
                Icons.drag_indicator_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
          )
        : const SizedBox(width: 8);

    final title = renaming
        ? _RenameField(initial: p.name, onDone: onEndRename)
        : GestureDetector(
            onDoubleTap: onStartRename,
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          );

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          leading,
          SizedBox(width: row.depth * 14.0),
          if (layer is GroupLayer)
            _Chevron(
              expanded: (layer as GroupLayer).expanded,
              onTap: () =>
                  editor.setExpanded(layer.id, !(layer as GroupLayer).expanded),
            ),
          if (p.clip)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 18,
                color: kindColor,
              ),
            ),
          AnimatedOpacity(
            duration: PixTokens.fast,
            opacity: dim ? 0.4 : 1,
            child: _Thumb(layer: layer, editor: editor, color: kindColor),
          ),
          // Photoshop-style mask thumbnail: tap to edit the mask.
          if (p.hasMaskLayer) ...[
            Icon(Icons.link_rounded, size: 14, color: scheme.onSurfaceVariant),
            Tooltip(
              message: l.layerMask,
              child: GestureDetector(
                onTap: () {
                  editor.select(layer.id);
                  commands.openPanel(ToolPanel.mask);
                },
                child: MaskThumb(layer: layer, size: 38),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedOpacity(
              duration: PixTokens.fast,
              opacity: dim ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Linked layers: tap to select the whole linked set.
          if (linked)
            Tooltip(
              message: l.selectLinked,
              child: InkResponse(
                onTap: () => editor.selectLinked(layer.id),
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.link_rounded,
                    size: 18,
                    color: scheme.primary.withValues(alpha: dim ? 0.45 : 1),
                  ),
                ),
              ),
            ),
          if (hasFx) _FxBadge(open: fxOpen, dim: dim, onTap: onToggleFx),
          _MiniToggle(
            tooltip: p.locked ? l.unlock : l.lock,
            on: p.locked,
            onIcon: Icons.lock_rounded,
            offIcon: Icons.lock_open_rounded,
            activeColor: scheme.primary,
            onTap: () => editor.toggleLocked(layer.id),
          ),
          _MiniToggle(
            tooltip: p.visible ? l.hide : l.show,
            on: p.visible,
            onIcon: Icons.visibility_rounded,
            offIcon: Icons.visibility_off_rounded,
            onTap: () => editor.toggleVisible(layer.id),
            onLongPress: () => editor.soloVisible(layer.id),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: PixTokens.fast,
        curve: PixTokens.curve,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.11)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(PixTokens.radiusM),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Column(
              children: [
                body,
                AnimatedSize(
                  duration: PixTokens.medium,
                  curve: PixTokens.emphasized,
                  alignment: Alignment.topCenter,
                  child: hasFx && fxOpen
                      ? _FxList(
                          layer: layer,
                          effects: effects,
                          editor: editor,
                          commands: commands,
                          indent: row.depth * 14.0 + 40,
                        )
                      : const SizedBox(width: double.infinity),
                ),
                AnimatedSize(
                  duration: PixTokens.medium,
                  curve: PixTokens.emphasized,
                  child: primary && !selectMode
                      ? _RowActions(
                          layer: layer,
                          editor: editor,
                          commands: commands,
                          onEdit: _primaryEdit,
                          onRename: onStartRename,
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.layer,
    required this.editor,
    required this.commands,
    required this.onEdit,
    required this.onRename,
  });

  final Layer layer;
  final EditorController editor;
  final LayerCommands commands;
  final VoidCallback onEdit;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget btn(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) => Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: color ?? scheme.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: const Size(0, 44),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Row(
        children: [
          btn(
            layer is GroupLayer
                ? Icons.unfold_more_rounded
                : Icons.edit_rounded,
            l.edit,
            onEdit,
          ),
          Expanded(
            child: QuickEditButton(
              layer: layer,
              editor: editor,
              commands: commands,
              onRename: onRename,
              buttonBuilder: (toggle) => TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  minimumSize: const Size(0, 44),
                ),
                onPressed: toggle,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, size: 20),
                    const SizedBox(height: 2),
                    Text(
                      l.quickEdit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          btn(
            Icons.copy_all_rounded,
            l.duplicate,
            () => editor.duplicateLayer(layer.id),
          ),
          btn(
            Icons.delete_outline_rounded,
            l.delete,
            () => commands.deleteLayers([layer.id]),
            color: scheme.error,
          ),
        ],
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.expanded, required this.onTap});
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    onTap: onTap,
    radius: 18,
    child: AnimatedRotation(
      turns: expanded
          ? 0
          : (Directionality.of(context) == TextDirection.rtl ? 0.25 : -0.25),
      duration: PixTokens.fast,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.expand_more_rounded, size: 20),
      ),
    ),
  );
}

/// Photoshop's "fx" mark on a layer row; folds the effects list.
class _FxBadge extends StatelessWidget {
  const _FxBadge({required this.open, required this.dim, required this.onTap});
  final bool open;
  final bool dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l.effectsLabel,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'fx',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: scheme.primary.withValues(alpha: dim ? 0.45 : 1),
                ),
              ),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: PixTokens.fast,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The layer's effects under its row, like Photoshop: an "Effects" line
/// that shows or hides them all, then one line per effect (eye to switch
/// it, tap to edit it).
class _FxList extends StatelessWidget {
  const _FxList({
    required this.layer,
    required this.effects,
    required this.editor,
    required this.commands,
    required this.indent,
  });

  final Layer layer;
  final List<LayerEffect> effects;
  final EditorController editor;
  final LayerCommands commands;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stroke = layer.props.stroke;
    final anyOn = effects.any((e) => e.enabled) || (stroke?.enabled ?? false);

    Widget line({
      required bool on,
      required VoidCallback onEye,
      required IconData icon,
      required String label,
      VoidCallback? onTap,
      bool header = false,
    }) {
      final fg = on ? scheme.onSurface : scheme.onSurfaceVariant;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              SizedBox(width: indent),
              InkResponse(
                onTap: onEye,
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    on
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                    color: on
                        ? scheme.onSurfaceVariant
                        : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: header ? scheme.primary : fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: header ? FontWeight.w800 : FontWeight.w500,
                    fontStyle: header ? FontStyle.italic : null,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          line(
            on: anyOn,
            header: true,
            icon: Icons.auto_fix_high_rounded,
            label: l.effectsLabel,
            onEye: () => editor.setAllEffectsEnabled(layer.id, !anyOn),
            onTap: () => commands.openEffects(layer),
          ),
          for (final e in effects.reversed)
            line(
              on: e.enabled,
              icon: fxIcon(e.type),
              label: fxLabel(l, e.type),
              onEye: () => editor.toggleEffect(layer.id, e.id),
              onTap: () => commands.editEffect(layer.id, e.type, e.id),
            ),
          if (stroke != null)
            line(
              on: stroke.enabled,
              icon: fxIcon('stroke'),
              label: l.stroke,
              onEye: () => editor.toggleStroke(layer.id),
              onTap: () => commands.editEffect(layer.id, 'stroke', null),
            ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.tooltip,
    required this.on,
    required this.onIcon,
    required this.offIcon,
    required this.onTap,
    this.onLongPress,
    this.activeColor,
  });

  final String tooltip;
  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedSwitcher(
            duration: PixTokens.fast,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              on ? onIcon : offIcon,
              key: ValueKey(on),
              size: 19,
              color: activeColor != null
                  ? (on ? activeColor : muted.withValues(alpha: 0.5))
                  : (on ? muted : muted.withValues(alpha: 0.45)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameField extends StatefulWidget {
  const _RenameField({required this.initial, required this.onDone});
  final String initial;
  final ValueChanged<String?> onDone;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_c.text);
    });
  }

  void _finish(String? v) {
    if (_done) return;
    _done = true;
    widget.onDone(v);
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
    },
    child: TextField(
      controller: _c,
      focusNode: _focus,
      autofocus: true,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      onSubmitted: _finish,
    ),
  );
}

/// Layer thumbnail framed in the layer kind's color, with a kind badge.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.layer,
    required this.editor,
    required this.color,
  });
  final Layer layer;
  final EditorController editor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: color, width: 2),
            ),
            padding: const EdgeInsets.all(2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CheckerboardBox(a: pix.checkerA, b: pix.checkerB, cell: 5),
                  CustomPaint(painter: _LayerThumbPainter(layer, editor)),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            end: -4,
            bottom: -4,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: Icon(
                LayerStyle.icon(layer.kind),
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws one layer fitted into the thumbnail box (leaves un-transformed,
/// groups as they appear on the canvas).
class _LayerThumbPainter extends CustomPainter {
  _LayerThumbPainter(this.layer, this.editor) : super(repaint: editor.assets);
  final Layer layer;
  final EditorController editor;

  @override
  void paint(Canvas canvas, Size size) {
    final Layer plain;
    final Rect box;
    if (layer is GroupLayer) {
      plain = layer.update(
        (p) => p.copyWith(opacity: 1, visible: true, clip: false),
      );
      box = layerLocalRect(plain);
    } else {
      final t = layer.props.transform;
      plain = layer.withProps(
        layer.props.copyWith(
          opacity: 1,
          visible: true,
          clip: false,
          transform: LayerTransform(
            scaleX: t.scaleX.sign,
            scaleY: t.scaleY.sign,
          ),
        ),
      );
      box = layerLocalRect(plain);
    }
    if (box.isEmpty) return;
    final fit = math.min(
      (size.width - 4) / box.width,
      (size.height - 4) / box.height,
    );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(fit)
      ..translate(-box.center.dx, -box.center.dy);
    editor.viewRenderer(fit * 2).paintLayer(canvas, plain);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerThumbPainter old) => old.layer != layer;
}

// ======================================================================

/// Bottom bar of the layers panel: the structural commands.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.editor,
    required this.commands,
    required this.onRename,
  });
  final EditorController editor;
  final LayerCommands commands;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = editor;
    final sel = e.topLevelSelection;
    final primary = e.selectedLayer;
    final multi = sel.length > 1;
    final canMergeDown =
        primary != null && !multi && e.document.indexOf(primary.id) > 0;

    Widget action(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      bool active = false,
    }) => IconButton(
      tooltip: tip,
      isSelected: active,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Photoshop's link button: link the selection, or unlink it.
              action(
                e.selectionIsLinked
                    ? Icons.link_off_rounded
                    : Icons.link_rounded,
                e.selectionIsLinked ? l.unlinkLayers : l.linkLayers,
                (multi || e.selectionIsLinked) ? e.toggleLinkSelection : null,
                active: e.selectionIsLinked,
              ),
              action(
                Icons.create_new_folder_rounded,
                sel.isEmpty ? l.newGroup : l.group,
                () => e.groupSelected(name: l.group),
              ),
              action(
                Icons.call_merge_rounded,
                multi ? l.merge : l.mergeDown,
                multi || canMergeDown
                    ? () => commands.runAsync(() async {
                        if (multi) {
                          await e.mergeSelected();
                        } else {
                          await e.mergeDown(primary!.id);
                        }
                      })
                    : null,
              ),
              action(
                Icons.subdirectory_arrow_right_rounded,
                l.clippingMask,
                primary != null && !multi
                    ? () => e.toggleClip(primary.id)
                    : null,
                active: primary?.props.clip ?? false,
              ),
              action(
                Icons.vignette_rounded,
                primary?.props.hasMaskLayer ?? false
                    ? l.layerMask
                    : l.addLayerMask,
                primary != null && !multi
                    ? () => commands.openPanel(ToolPanel.mask)
                    : null,
                active: primary?.props.hasMaskLayer ?? false,
              ),
              action(
                Icons.copy_all_rounded,
                l.duplicate,
                sel.isEmpty ? null : e.duplicateSelected,
              ),
              action(
                Icons.delete_outline_rounded,
                l.delete,
                sel.isEmpty
                    ? null
                    : () => commands.deleteLayers(e.topLevelSelection),
              ),
              _MoreMenu(editor: e, commands: commands, onRename: onRename),
            ],
          ),
        ),
      ),
    );
  }
}

enum _More {
  selectAll,
  deselect,
  link,
  selectLinked,
  rename,
  showOnly,
  moveOut,
  ungroup,
  rasterize,
  mergeVisible,
  flatten,
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.editor,
    required this.commands,
    required this.onRename,
  });
  final EditorController editor;
  final LayerCommands commands;
  final ValueChanged<String> onRename;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final e = editor;
    final primary = e.selectedLayer;
    final inGroup = primary != null && e.document.parentOf(primary.id) != null;
    PopupMenuItem<_More> item(
      _More v,
      IconData icon,
      String label, {
      bool enabled = true,
    }) => PopupMenuItem(
      value: v,
      enabled: enabled,
      child: ListTile(leading: Icon(icon), title: Text(label), dense: true),
    );
    return PopupMenuButton<_More>(
      tooltip: l.more,
      icon: const Icon(Icons.more_vert_rounded),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PixTokens.radiusM),
      ),
      onSelected: (v) {
        switch (v) {
          case _More.selectAll:
            e.selectAll();
          case _More.deselect:
            e.deselect();
          case _More.link:
            e.toggleLinkSelection();
          case _More.selectLinked:
            e.selectLinked(primary!.id);
          case _More.rename:
            onRename(primary!.id);
          case _More.showOnly:
            e.soloVisible(primary!.id);
          case _More.moveOut:
            final parent = e.document.parentOf(primary!.id)!;
            final grand = e.document.parentOf(parent.id)?.id;
            e.moveLayer(
              primary.id,
              parentId: grand,
              index: e.document.indexOf(parent.id) + 1,
            );
          case _More.ungroup:
            e.ungroup(primary!.id);
          case _More.rasterize:
            commands.runAsync(() => e.rasterizeLayer(primary!.id));
          case _More.mergeVisible:
            commands.runAsync(() => e.mergeVisible(name: l.merge));
          case _More.flatten:
            commands.runAsync(() => e.flatten(name: l.flatten));
        }
      },
      itemBuilder: (_) => [
        item(_More.selectAll, Icons.select_all_rounded, l.selectAll),
        item(
          _More.deselect,
          Icons.deselect_rounded,
          l.deselect,
          enabled: e.selectedIds.isNotEmpty,
        ),
        const PopupMenuDivider(),
        item(
          _More.link,
          e.selectionIsLinked ? Icons.link_off_rounded : Icons.link_rounded,
          e.selectionIsLinked ? l.unlinkLayers : l.linkLayers,
          enabled: e.topLevelSelection.length > 1 || e.selectionIsLinked,
        ),
        item(
          _More.selectLinked,
          Icons.select_all_rounded,
          l.selectLinked,
          enabled: primary != null && e.isLinked(primary.id),
        ),
        const PopupMenuDivider(),
        item(
          _More.rename,
          Icons.drive_file_rename_outline_rounded,
          l.rename,
          enabled: primary != null,
        ),
        item(
          _More.showOnly,
          Icons.visibility_rounded,
          l.showOnly,
          enabled: primary != null,
        ),
        item(
          _More.moveOut,
          Icons.drive_file_move_rtl_rounded,
          l.moveOut,
          enabled: inGroup,
        ),
        item(
          _More.ungroup,
          Icons.folder_off_rounded,
          l.ungroup,
          enabled: primary is GroupLayer,
        ),
        item(
          _More.rasterize,
          Icons.grain_rounded,
          l.rasterize,
          enabled: primary != null && primary is! RasterLayer,
        ),
        const PopupMenuDivider(),
        item(
          _More.mergeVisible,
          Icons.layers_rounded,
          l.mergeVisible,
          enabled: e.document.layers.length > 1,
        ),
        item(
          _More.flatten,
          Icons.crop_din_rounded,
          l.flatten,
          enabled: e.document.layers.isNotEmpty,
        ),
      ],
    );
  }
}
