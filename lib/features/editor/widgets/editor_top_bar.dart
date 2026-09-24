import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/settings/app_settings.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../editor_scope.dart';
import 'canvas_view.dart';

/// Callbacks the top bar needs from the editor page.
class TopBarActions {
  const TopBarActions({
    required this.back,
    required this.rename,
    required this.save,
    required this.exportImage,
    required this.resizeCanvas,
    required this.exportProject,
  });

  final VoidCallback back;
  final VoidCallback rename;

  /// Opens the save sheet (project / image).
  final VoidCallback save;
  final VoidCallback exportImage;
  final VoidCallback resizeCanvas;
  final VoidCallback exportProject;
}

enum _More { gridSettings, snapSettings, canvasSize, exportProject }

/// The editor's top bar.
///
/// Phones get two rows like PixelLab — row one: back, title, save, export,
/// more; row two: the everyday canvas tools (undo/redo, move/hand, grid,
/// snap, rulers, zoom, layers). Wide screens get a single Photoshop-style
/// row with the same tools plus zoom buttons.
///
/// Grid and snap are toggles; long-press them (or use ⋮) for settings.
class EditorTopBar extends StatelessWidget {
  const EditorTopBar({
    super.key,
    required this.editor,
    required this.ui,
    required this.settings,
    required this.canvas,
    required this.actions,
    required this.wide,
    required this.saved,
  });

  final EditorController editor;
  final EditorUiState ui;
  final AppSettings settings;
  final CanvasViewController canvas;
  final TopBarActions actions;
  final bool wide;
  final bool saved;

  void _toggleGrid() {
    final visible = !editor.document.guides.grid.visible;
    editor.updateGuides(
      (g) => g.copyWith(grid: g.grid.copyWith(visible: visible)),
    );
    if (visible) {
      ui.panel = ToolPanel.grid;
    } else {
      if (ui.panel == ToolPanel.grid) ui.panel = null;
      if (ui.mode == ToolMode.grid) ui.mode = ToolMode.move;
    }
  }

  void _openPanel(ToolPanel p) {
    HapticFeedback.mediumImpact();
    ui.showLayers = false;
    ui.panel = p;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([editor, ui, settings, canvas]),
      builder: (context, _) {
        final tools = _tools(context, l);
        final title = _Title(
          editor: editor,
          saved: saved,
          onTap: actions.rename,
        );
        final trailing = [
          _SaveButton(saved: saved, onPressed: actions.save),
          if (!wide) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: l.layers,
              isSelected: ui.showLayers,
              onPressed: () => ui.showLayers = !ui.showLayers,
              icon: const Icon(Icons.layers_outlined),
              selectedIcon: const Icon(Icons.layers_rounded),
            ),
          ],
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: actions.exportImage,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: Text(l.export),
          ),
          _moreMenu(l, compact: !wide),
        ];
        if (wide) {
          return SizedBox(
            height: 60,
            child: Row(
              children: [
                _back(context),
                SizedBox(width: 200, child: title),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: tools),
                  ),
                ),
                ...trailing,
                const SizedBox(width: 6),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  _back(context),
                  Expanded(child: title),
                  ...trailing,
                ],
              ),
            ),
            // Every tool fits on screen: buttons share the width evenly.
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    for (final t in tools)
                      t is _Divider
                          ? t
                          : Expanded(flex: t is _ZoomChip ? 2 : 1, child: t),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],
        );
      },
    );
  }

  Widget _back(BuildContext context) => IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: actions.back,
    icon: const BackButtonIcon(),
  );

  List<Widget> _tools(BuildContext context, AppLocalizations l) {
    final grid = editor.document.guides.grid;
    return [
      _ToolButton(
        icon: Icons.undo_rounded,
        tooltip: l.undo,
        onTap: editor.canUndo ? editor.undo : null,
      ),
      _ToolButton(
        icon: Icons.redo_rounded,
        tooltip: l.redo,
        onTap: editor.canRedo ? editor.redo : null,
      ),
      const _Divider(),
      _ToolButton(
        icon: Icons.near_me_rounded,
        tooltip: l.moveTool,
        active: ui.mode == ToolMode.move,
        onTap: () => ui.mode = ToolMode.move,
      ),
      _ToolButton(
        icon: Icons.pan_tool_rounded,
        tooltip: l.handTool,
        active: ui.mode == ToolMode.hand,
        onTap: () =>
            ui.mode = ui.mode == ToolMode.hand ? ToolMode.move : ToolMode.hand,
      ),
      const _Divider(),
      _ToolButton(
        icon: Icons.grid_4x4_rounded,
        tooltip: '${l.grid} · ${l.longPressSettings}',
        active: grid.visible,
        badge: ui.mode == ToolMode.grid,
        onTap: _toggleGrid,
        onLongPress: () => _openPanel(ToolPanel.grid),
      ),
      _ToolButton(
        icon: Icons.join_inner_rounded,
        tooltip: '${l.snapping} · ${l.longPressSettings}',
        active: settings.snapping,
        onTap: () => settings.snapping = !settings.snapping,
        onLongPress: () => _openPanel(ToolPanel.snap),
      ),
      _ToolButton(
        icon: Icons.straighten_rounded,
        tooltip: l.rulers,
        active: settings.showRulers,
        onTap: () => settings.showRulers = !settings.showRulers,
      ),
      const _Divider(),
      if (wide)
        _ToolButton(
          icon: Icons.zoom_out_rounded,
          tooltip: l.zoomOut,
          onTap: () => canvas.zoomBy(1 / 1.25),
        ),
      _ZoomChip(canvas: canvas),
      if (wide)
        _ToolButton(
          icon: Icons.zoom_in_rounded,
          tooltip: l.zoomIn,
          onTap: () => canvas.zoomBy(1.25),
        ),
      if (wide)
        _ToolButton(
          icon: Icons.fit_screen_rounded,
          tooltip: l.fitToScreen,
          onTap: canvas.fit,
        ),
    ];
  }

  Widget _moreMenu(AppLocalizations l, {bool compact = false}) =>
      PopupMenuButton<_More>(
        tooltip: l.more,
        padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
        icon: const Icon(Icons.more_vert_rounded),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
        ),
        onSelected: (a) => switch (a) {
          _More.gridSettings => _openPanel(ToolPanel.grid),
          _More.snapSettings => _openPanel(ToolPanel.snap),
          _More.canvasSize => actions.resizeCanvas(),
          _More.exportProject => actions.exportProject(),
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _More.gridSettings,
            child: ListTile(
              leading: const Icon(Icons.grid_on_rounded),
              title: Text(l.gridSettings),
            ),
          ),
          PopupMenuItem(
            value: _More.snapSettings,
            child: ListTile(
              leading: const Icon(Icons.join_inner_rounded),
              title: Text(l.snapSettings),
            ),
          ),
          PopupMenuItem(
            value: _More.canvasSize,
            child: ListTile(
              leading: const Icon(Icons.aspect_ratio_rounded),
              title: Text(l.canvasSize),
            ),
          ),
          PopupMenuItem(
            value: _More.exportProject,
            child: ListTile(
              leading: const Icon(Icons.inventory_2_rounded),
              title: Text(l.exportProject),
            ),
          ),
        ],
      );
}

class _Title extends StatelessWidget {
  const _Title({
    required this.editor,
    required this.saved,
    required this.onTap,
  });
  final EditorController editor;
  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(PixTokens.radiusS),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              editor.document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${editor.document.width.round()} × ${editor.document.height.round()}',
              textDirection: TextDirection.ltr,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Save button with an "unsaved changes" dot.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onPressed});
  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: saved ? l.allSaved : l.unsavedChanges,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.save_rounded),
          PositionedDirectional(
            end: -3,
            top: -3,
            child: AnimatedScale(
              scale: saved ? 0 : 1,
              duration: PixTokens.fast,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.secondaryContainer,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.onLongPress,
    this.active = false,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;

  /// Small dot under the icon (e.g. grid editing mode on).
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final fg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.3)
        : active
        ? scheme.onPrimary
        : scheme.onSurface.withValues(alpha: 0.8);
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Material(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            onLongPress: onLongPress,
            child: SizedBox(
              width: 44,
              height: 40,
              // Stretched by an Expanded parent on phones.
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, size: 21, color: fg),
                  if (badge)
                    Positioned(
                      bottom: 4,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: fg,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
    child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
  );
}

/// Shows the zoom level; tap for presets.
class _ZoomChip extends StatelessWidget {
  const _ZoomChip({required this.canvas});
  final CanvasViewController canvas;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopupMenuButton<double>(
      tooltip: l.zoom,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PixTokens.radiusM),
      ),
      onSelected: (v) => v == 0 ? canvas.fit() : canvas.zoomTo(v),
      itemBuilder: (_) => [
        PopupMenuItem(value: 0, child: Text(l.fitToScreen)),
        for (final z in const [0.25, 0.5, 1.0, 2.0, 4.0])
          PopupMenuItem(
            value: z,
            child: Text(
              '${(z * 100).round()}%',
              textDirection: TextDirection.ltr,
            ),
          ),
      ],
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${(canvas.zoom * 100).round()}%',
          textDirection: TextDirection.ltr,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
