import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/layer_style.dart';
import '../../../ui/widgets/pressable.dart';
import '../editor_scope.dart';

/// Things the layers UI asks the editor page to do (open a tool panel,
/// show the text sheet, pick a replacement image…).
class LayerCommands {
  const LayerCommands({
    required this.openPanel,
    required this.editText,
    required this.replaceImage,
    required this.runAsync,
  });

  final void Function(ToolPanel panel) openPanel;
  final void Function(TextLayer layer) editText;
  final void Function(RasterLayer layer) replaceImage;

  /// Runs a slow operation (merge, rasterize) with a progress indicator.
  final Future<void> Function(Future<void> Function() job) runAsync;
}

class QuickAction {
  const QuickAction(
    this.icon,
    this.label,
    this.run, {
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback run;
  final bool destructive;
}

/// The actions that make sense for [layer], most used first.
List<QuickAction> quickActionsFor(
  Layer layer,
  EditorController e,
  LayerCommands cmd,
  AppLocalizations l, {
  required VoidCallback onRename,
}) {
  final id = layer.id;
  final ids = [id];
  QuickAction panel(IconData i, String label, ToolPanel p) =>
      QuickAction(i, label, () {
        e.select(id);
        cmd.openPanel(p);
      });
  final center = QuickAction(Icons.center_focus_strong_rounded, l.center, () {
    e.alignLayers(ids, LayerAlign.centerH);
    e.alignLayers(ids, LayerAlign.centerV);
  });
  final rotate = QuickAction(
    Icons.rotate_90_degrees_cw_rounded,
    l.rotate,
    () => e.rotateLayers(ids, math.pi / 2),
  );
  final flipH = QuickAction(
    Icons.flip_rounded,
    l.flipH,
    () => e.flipLayers(ids, horizontal: true),
  );
  final duplicate = QuickAction(
    Icons.copy_all_rounded,
    l.duplicate,
    () => e.duplicateLayer(id),
  );
  final rename = QuickAction(
    Icons.drive_file_rename_outline_rounded,
    l.rename,
    onRename,
  );
  final clip = QuickAction(
    layer.props.clip
        ? Icons.layers_clear_rounded
        : Icons.subdirectory_arrow_right_rounded,
    l.clippingMask,
    () => e.toggleClip(id),
  );
  final rasterize = QuickAction(
    Icons.grain_rounded,
    l.rasterize,
    () => cmd.runAsync(() => e.rasterizeLayer(id)),
  );
  final delete = QuickAction(
    Icons.delete_outline_rounded,
    l.delete,
    () => e.deleteLayer(id),
    destructive: true,
  );
  final blend = panel(Icons.opacity_rounded, l.blendMode, ToolPanel.opacity);
  final shadow = panel(Icons.blur_circular_rounded, l.shadow, ToolPanel.shadow);
  final adjust = panel(Icons.tune_rounded, l.adjust, ToolPanel.adjust);

  return switch (layer) {
    TextLayer t => [
      QuickAction(Icons.edit_rounded, l.editText, () => cmd.editText(t)),
      panel(Icons.font_download_rounded, l.font, ToolPanel.font),
      panel(Icons.palette_rounded, l.color, ToolPanel.fill),
      panel(Icons.border_color_rounded, l.stroke, ToolPanel.stroke),
      shadow,
      blend,
      center,
      rotate,
      flipH,
      clip,
      duplicate,
      rename,
      rasterize,
      delete,
    ],
    RasterLayer r => [
      adjust,
      panel(Icons.auto_awesome_rounded, l.filters, ToolPanel.filters),
      QuickAction(
        Icons.find_replace_rounded,
        l.replaceImage,
        () => cmd.replaceImage(r),
      ),
      shadow,
      blend,
      center,
      rotate,
      flipH,
      QuickAction(
        Icons.flip_rounded,
        l.flipV,
        () => e.flipLayers(ids, horizontal: false),
      ),
      clip,
      duplicate,
      rename,
      delete,
    ],
    ShapeLayer _ => [
      panel(Icons.category_rounded, l.shape, ToolPanel.shapeStyle),
      panel(Icons.palette_rounded, l.color, ToolPanel.fill),
      panel(Icons.border_style_rounded, l.stroke, ToolPanel.stroke),
      shadow,
      blend,
      center,
      rotate,
      flipH,
      clip,
      duplicate,
      rename,
      rasterize,
      delete,
    ],
    GroupLayer g => [
      QuickAction(Icons.folder_off_rounded, l.ungroup, () => e.ungroup(g.id)),
      rename,
      blend,
      shadow,
      adjust,
      center,
      rotate,
      flipH,
      duplicate,
      QuickAction(
        Icons.call_merge_rounded,
        l.merge,
        () => cmd.runAsync(() => e.rasterizeLayer(id)),
      ),
      delete,
    ],
  };
}

/// A button that opens the quick-edit grid for [layer].
class QuickEditButton extends StatefulWidget {
  const QuickEditButton({
    super.key,
    required this.layer,
    required this.editor,
    required this.commands,
    required this.onRename,
    this.buttonBuilder,
  });

  final Layer layer;
  final EditorController editor;
  final LayerCommands commands;
  final VoidCallback onRename;

  /// Custom trigger; receives a callback that toggles the menu.
  final Widget Function(VoidCallback toggle)? buttonBuilder;

  @override
  State<QuickEditButton> createState() => _QuickEditButtonState();
}

class _QuickEditButtonState extends State<QuickEditButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final actions = quickActionsFor(
      widget.layer,
      widget.editor,
      widget.commands,
      l,
      onRename: widget.onRename,
    );
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PixTokens.radiusL),
          ),
        ),
        elevation: const WidgetStatePropertyAll(8),
      ),
      menuChildren: [
        QuickEditGrid(
          layer: widget.layer,
          actions: actions,
          onPicked: _controller.close,
        ),
      ],
      builder: (context, controller, _) {
        void toggle() {
          HapticFeedback.selectionClick();
          controller.isOpen ? controller.close() : controller.open();
        }

        return widget.buttonBuilder?.call(toggle) ??
            IconButton(
              tooltip: l.quickEdit,
              visualDensity: VisualDensity.compact,
              onPressed: toggle,
              icon: const Icon(Icons.more_horiz_rounded),
            );
      },
    );
  }
}

class QuickEditGrid extends StatelessWidget {
  const QuickEditGrid({
    super.key,
    required this.layer,
    required this.actions,
    required this.onPicked,
  });

  final Layer layer;
  final List<QuickAction> actions;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final kindColor = LayerStyle.color(layer.kind);
    return SizedBox(
      width: 252,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Icon(LayerStyle.icon(layer.kind), size: 18, color: kindColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    layer.props.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  LayerStyle.label(l, layer.kind),
                  style: theme.textTheme.labelSmall?.copyWith(color: kindColor),
                ),
              ],
            ),
          ),
          Wrap(
            children: [
              for (final a in actions)
                _QuickTile(
                  action: a,
                  onTap: () {
                    onPicked();
                    a.run();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.action, required this.onTap});
  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = action.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      haptic: true,
      semanticLabel: action.label,
      child: SizedBox(
        width: 84,
        height: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs [job] behind a small blocking progress overlay.
Future<void> runWithProgress(
  BuildContext context,
  Future<void> Function() job,
) async {
  final l = AppLocalizations.of(context);
  final nav = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(),
              ),
              const SizedBox(width: 18),
              Text(l.working),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    await job();
  } finally {
    nav.pop();
  }
}
