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
    required this.editLayer,
  });

  /// Edits the selected layer (text → text sheet, image → replace,
  /// shape → style panel).
  final VoidCallback editLayer;

  final VoidCallback back;
  final VoidCallback rename;

  /// Opens the save sheet (project / image).
  final VoidCallback save;
  final VoidCallback exportImage;
  final VoidCallback resizeCanvas;
  final VoidCallback exportProject;
}

enum _More { rulers, gridSettings, snapSettings, canvasSize, exportProject }

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
        return _CompactBar(bar: this, l: l);
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

  Widget _moreMenu(AppLocalizations l, {bool compact = false, Color? color}) =>
      PopupMenuButton<_More>(
        tooltip: l.more,
        icon: Icon(
          Icons.more_vert_rounded,
          color: color,
          size: compact ? 26 : null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
        ),
        onSelected: (a) => switch (a) {
          _More.rulers => settings.showRulers = !settings.showRulers,
          _More.gridSettings => _openPanel(ToolPanel.grid),
          _More.snapSettings => _openPanel(ToolPanel.snap),
          _More.canvasSize => actions.resizeCanvas(),
          _More.exportProject => actions.exportProject(),
        },
        itemBuilder: (_) => [
          if (compact)
            CheckedPopupMenuItem(
              value: _More.rulers,
              checked: settings.showRulers,
              child: Text(l.rulers),
            ),
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
  const _ZoomChip({required this.canvas, this.color});
  final CanvasViewController canvas;

  /// Text colour on a coloured bar (null = theme colours).
  final Color? color;

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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              color?.withValues(alpha: 0.18) ??
              theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${(canvas.zoom * 100).round()}%',
            textDirection: TextDirection.ltr,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone top bar in the spirit of PixelLab — a bold coloured bar with two
/// rows of big, evenly spaced icons — but softer: gradient, rounded bottom
/// corners, translucent pills for active tools, and a context pill that
/// shows the project name or quick actions for the selected layer.
class _CompactBar extends StatelessWidget {
  const _CompactBar({required this.bar, required this.l});
  final EditorTopBar bar;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final bg = dark ? scheme.primaryContainer : scheme.primary;
    final fg = dark ? scheme.onPrimaryContainer : scheme.onPrimary;
    final hsl = HSLColor.fromColor(bg);
    final bg2 = hsl
        .withHue((hsl.hue + 12) % 360)
        .withLightness((hsl.lightness * 0.85).clamp(0.0, 1.0))
        .toColor();
    final editor = bar.editor;
    final ui = bar.ui;
    final settings = bar.settings;
    final top = MediaQuery.paddingOf(context).top;

    Widget cell(Widget child, {int flex = 1}) => Expanded(
      flex: flex,
      child: Center(child: child),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark || fg.computeLuminance() > 0.5
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [bg, bg2],
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: bg.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: fg, size: 26),
          child: Padding(
            padding: EdgeInsets.fromLTRB(6, top + 2, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      cell(
                        _BarIcon(
                          icon: Icons.arrow_back_rounded,
                          matchDirection: true,
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          fg: fg,
                          onTap: bar.actions.back,
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.undo_rounded,
                          tooltip: l.undo,
                          fg: fg,
                          onTap: editor.canUndo ? editor.undo : null,
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.redo_rounded,
                          tooltip: l.redo,
                          fg: fg,
                          onTap: editor.canRedo ? editor.redo : null,
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.save_rounded,
                          tooltip: bar.saved ? l.allSaved : l.unsavedChanges,
                          fg: fg,
                          dot: !bar.saved,
                          onTap: bar.actions.save,
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.share_rounded,
                          tooltip: l.export,
                          fg: fg,
                          onTap: bar.actions.exportImage,
                        ),
                      ),
                      cell(bar._moreMenu(l, compact: true, color: fg)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      cell(_ContextPill(bar: bar, fg: fg, bg: bg), flex: 2),
                      cell(
                        _BarIcon(
                          icon: ui.mode == ToolMode.hand
                              ? Icons.pan_tool_rounded
                              : Icons.near_me_rounded,
                          tooltip: ui.mode == ToolMode.hand
                              ? l.handTool
                              : l.moveTool,
                          fg: fg,
                          active: ui.mode == ToolMode.hand,
                          onTap: () => ui.mode = ui.mode == ToolMode.hand
                              ? ToolMode.move
                              : ToolMode.hand,
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.grid_on_rounded,
                          tooltip: '${l.grid} · ${l.longPressSettings}',
                          fg: fg,
                          active: editor.document.guides.grid.visible,
                          dot: ui.mode == ToolMode.grid,
                          onTap: bar._toggleGrid,
                          onLongPress: () => bar._openPanel(ToolPanel.grid),
                        ),
                      ),
                      cell(
                        _BarIcon(
                          icon: Icons.join_inner_rounded,
                          tooltip: '${l.snapping} · ${l.longPressSettings}',
                          fg: fg,
                          active: settings.snapping,
                          onTap: () => settings.snapping = !settings.snapping,
                          onLongPress: () => bar._openPanel(ToolPanel.snap),
                        ),
                      ),
                      cell(_ZoomChip(canvas: bar.canvas, color: fg)),
                      cell(
                        _BarIcon(
                          icon: Icons.layers_rounded,
                          tooltip: l.layers,
                          fg: fg,
                          active: ui.showLayers,
                          onTap: () => ui.showLayers = !ui.showLayers,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Project name when nothing is selected (tap to rename); quick edit and
/// delete buttons when a layer is selected — like PixelLab.
class _ContextPill extends StatelessWidget {
  const _ContextPill({required this.bar, required this.fg, required this.bg});
  final EditorTopBar bar;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editor = bar.editor;
    final hasSel = editor.selectedId != null;
    Widget round(IconData icon, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: Material(
        color: fg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 21, color: bg),
          ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: PixTokens.fast,
      child: Container(
        key: ValueKey(hasSel),
        height: 46,
        constraints: const BoxConstraints(minWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(23),
        ),
        child: hasSel
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  round(Icons.edit_rounded, l.edit, bar.actions.editLayer),
                  const SizedBox(width: 6),
                  round(Icons.delete_rounded, l.delete, editor.deleteSelected),
                ],
              )
            : InkWell(
                borderRadius: BorderRadius.circular(23),
                onTap: bar.actions.rename,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      editor.document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.fg,
    required this.onTap,
    this.onLongPress,
    this.active = false,
    this.dot = false,
    this.matchDirection = false,
  });

  final IconData icon;
  final String tooltip;
  final Color fg;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;
  final bool dot;
  final bool matchDirection;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? fg : fg.withValues(alpha: 0.4);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Widget glyph = Icon(icon, color: color);
    if (matchDirection && rtl) {
      glyph = Transform.flip(flipX: true, child: glyph);
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        onLongPress: onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onLongPress!();
              },
        child: AnimatedContainer(
          duration: PixTokens.fast,
          width: 50,
          height: 44,
          decoration: BoxDecoration(
            color: active ? fg.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              glyph,
              if (dot)
                PositionedDirectional(
                  top: 8,
                  end: 10,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5A5F),
                      shape: BoxShape.circle,
                      border: Border.all(color: fg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
