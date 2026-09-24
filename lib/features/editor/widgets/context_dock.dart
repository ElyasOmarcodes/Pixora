import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pressable.dart';
import '../editor_scope.dart';

/// One entry in the dock: either opens a panel or runs an action.
class DockItem {
  const DockItem(
    this.icon,
    this.label, {
    this.panel,
    this.onTap,
    this.destructive = false,
  });
  final IconData icon;
  final String label;
  final ToolPanel? panel;
  final VoidCallback? onTap;
  final bool destructive;
}

/// The contextual bottom toolbar.
///
/// It shows only what makes sense right now: creation tools when nothing is
/// selected, and the selected layer's tools otherwise (text tools for text,
/// adjustments for photos, …). Fewer, relevant buttons keep the editor calm.
class ContextDock extends StatelessWidget {
  const ContextDock({
    super.key,
    required this.editor,
    required this.ui,
    required this.onAddText,
    required this.onAddImage,
    required this.onEditText,
    required this.onResizeCanvas,
    this.vertical = false,
  });

  final EditorController editor;
  final EditorUiState ui;
  final VoidCallback onAddText;
  final VoidCallback onAddImage;
  final void Function(TextLayer layer) onEditText;
  final VoidCallback onResizeCanvas;
  final bool vertical;

  List<DockItem> _items(AppLocalizations l, Layer? layer) {
    if (layer == null) {
      return [
        DockItem(Icons.title_rounded, l.text, onTap: onAddText),
        DockItem(Icons.add_photo_alternate_rounded, l.image, onTap: onAddImage),
        DockItem(Icons.category_rounded, l.shape, panel: ToolPanel.addShape),
        DockItem(
          Icons.format_color_fill_rounded,
          l.background,
          panel: ToolPanel.background,
        ),
        DockItem(
          Icons.aspect_ratio_rounded,
          l.canvasSize,
          onTap: onResizeCanvas,
        ),
      ];
    }
    final common = [
      DockItem(Icons.blur_circular_rounded, l.shadow, panel: ToolPanel.shadow),
      DockItem(Icons.opacity_rounded, l.opacity, panel: ToolPanel.opacity),
      DockItem(Icons.open_with_rounded, l.arrange, panel: ToolPanel.arrange),
      DockItem(
        Icons.copy_all_rounded,
        l.duplicate,
        onTap: () => editor.duplicateLayer(layer.id),
      ),
      DockItem(
        Icons.delete_outline_rounded,
        l.delete,
        onTap: () => editor.deleteLayer(layer.id),
        destructive: true,
      ),
    ];
    return switch (layer) {
      TextLayer t => [
        DockItem(Icons.edit_rounded, l.edit, onTap: () => onEditText(t)),
        DockItem(Icons.font_download_rounded, l.font, panel: ToolPanel.font),
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        DockItem(Icons.border_color_rounded, l.stroke, panel: ToolPanel.stroke),
        ...common,
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
      ],
      ShapeLayer _ => [
        DockItem(Icons.category_rounded, l.shape, panel: ToolPanel.shapeStyle),
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        DockItem(Icons.border_style_rounded, l.stroke, panel: ToolPanel.stroke),
        ...common,
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
      ],
      RasterLayer _ => [
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
        DockItem(
          Icons.auto_awesome_rounded,
          l.filters,
          panel: ToolPanel.filters,
        ),
        ...common,
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([editor, ui]),
      builder: (context, _) {
        final layer = editor.selectedLayer;
        final items = _items(l, layer);
        final list = ListView(
          scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
          padding: vertical
              ? const EdgeInsets.symmetric(vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final item in items)
              _DockButton(
                item: item,
                selected: item.panel != null && ui.panel == item.panel,
                onTap: () {
                  if (item.panel != null) {
                    ui.togglePanel(item.panel!);
                  } else {
                    item.onTap?.call();
                  }
                },
              ),
          ],
        );
        return AnimatedSwitcher(
          duration: PixTokens.medium,
          switchInCurve: PixTokens.emphasized,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(a),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(layer?.kind),
            child: SizedBox(
              height: vertical ? null : 76,
              width: vertical ? 84 : null,
              child: list,
            ),
          ),
        );
      },
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final DockItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = item.destructive
        ? scheme.error
        : selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.78);
    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      scale: 0.9,
      semanticLabel: item.label,
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: PixTokens.fast,
              curve: PixTokens.curve,
              width: 46,
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(item.icon, color: color, size: 23),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
