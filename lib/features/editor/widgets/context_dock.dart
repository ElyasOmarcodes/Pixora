import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pressable.dart';
import '../editor_scope.dart';
import 'layer_actions.dart';

/// One entry in the dock: either opens a panel or runs an action.
class DockItem {
  const DockItem(
    this.icon,
    this.label, {
    this.panel,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
  }) : divider = false;

  /// A thin separator between groups of related tools.
  const DockItem.divider()
    : icon = Icons.more_vert,
      label = '',
      panel = null,
      onTap = null,
      destructive = false,
      enabled = true,
      divider = true;

  final IconData icon;
  final String label;
  final ToolPanel? panel;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final bool divider;
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
    required this.onPickFont,
    required this.onResizeCanvas,
    required this.commands,
    this.vertical = false,
  });

  final LayerCommands commands;

  final EditorController editor;
  final EditorUiState ui;
  final VoidCallback onAddText;
  final VoidCallback onAddImage;
  final void Function(TextLayer layer) onEditText;
  final void Function(TextLayer layer) onPickFont;
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
    const div = DockItem.divider();
    if (editor.hasMultiSelection) {
      return [
        DockItem(
          Icons.create_new_folder_rounded,
          l.group,
          onTap: () => editor.groupSelected(name: l.group),
        ),
        DockItem(
          Icons.copy_all_rounded,
          l.duplicate,
          onTap: editor.duplicateSelected,
        ),
        DockItem(
          Icons.delete_outline_rounded,
          l.delete,
          onTap: () => commands.deleteLayers(editor.topLevelSelection),
          destructive: true,
        ),
        div,
        DockItem(Icons.open_with_rounded, l.move, panel: ToolPanel.move),
        DockItem(
          Icons.grid_view_rounded,
          l.position,
          panel: ToolPanel.position,
        ),
        DockItem(
          Icons.photo_size_select_large_rounded,
          l.size,
          panel: ToolPanel.size,
        ),
        DockItem(
          Icons.rotate_right_rounded,
          l.rotation,
          panel: ToolPanel.rotate,
        ),
        div,
        DockItem(
          Icons.call_merge_rounded,
          l.merge,
          onTap: () => commands.runAsync(editor.mergeSelected),
        ),
        DockItem(Icons.deselect_rounded, l.deselect, onTap: editor.deselect),
      ];
    }

    final id = layer.id;
    final index = editor.document.indexOf(id);
    final top = editor.document.siblingsOf(id).length - 1;
    // Shared by every layer type, in the same order everywhere.
    final basics = [
      DockItem(
        Icons.delete_outline_rounded,
        l.delete,
        onTap: () => commands.deleteLayers([id]),
        destructive: true,
      ),
      DockItem(
        Icons.copy_all_rounded,
        l.duplicate,
        onTap: () => editor.duplicateLayer(id),
      ),
      div,
      DockItem(
        Icons.flip_to_front_rounded,
        l.forward,
        enabled: index < top,
        onTap: () => editor.arrange(id, LayerArrange.forward),
      ),
      DockItem(
        Icons.flip_to_back_rounded,
        l.backward,
        enabled: index > 0,
        onTap: () => editor.arrange(id, LayerArrange.backward),
      ),
      DockItem(Icons.open_with_rounded, l.move, panel: ToolPanel.move),
      DockItem(Icons.grid_view_rounded, l.position, panel: ToolPanel.position),
      DockItem(
        Icons.photo_size_select_large_rounded,
        l.size,
        panel: ToolPanel.size,
      ),
    ];
    final look = [
      DockItem(Icons.opacity_rounded, l.opacity, panel: ToolPanel.opacity),
      DockItem(
        Icons.threed_rotation_rounded,
        l.rotation,
        panel: ToolPanel.rotate,
      ),
    ];
    final effects = [
      DockItem(Icons.blur_on_rounded, l.shadow, panel: ToolPanel.shadow),
      DockItem(Icons.flare_rounded, l.glow, panel: ToolPanel.glow),
      DockItem(Icons.texture_rounded, l.bevel, panel: ToolPanel.bevel),
      DockItem(Icons.view_in_ar_rounded, l.threeD, panel: ToolPanel.extrude),
    ];
    return switch (layer) {
      TextLayer t => [
        DockItem(Icons.edit_rounded, l.edit, onTap: () => onEditText(t)),
        ...basics,
        div,
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        ...look,
        div,
        DockItem(
          Icons.font_download_rounded,
          l.font,
          onTap: () => onPickFont(t),
        ),
        DockItem(
          Icons.text_format_rounded,
          l.style,
          panel: ToolPanel.textStyle,
        ),
        DockItem(Icons.looks_rounded, l.curve, panel: ToolPanel.curve),
        DockItem(
          Icons.format_shapes_rounded,
          l.background,
          panel: ToolPanel.textBackground,
        ),
        DockItem(
          Icons.format_line_spacing_rounded,
          l.spacing,
          panel: ToolPanel.spacing,
        ),
        div,
        DockItem(Icons.border_color_rounded, l.stroke, panel: ToolPanel.stroke),
        ...effects,
      ],
      ShapeLayer _ => [
        DockItem(Icons.category_rounded, l.shape, panel: ToolPanel.shapeStyle),
        ...basics,
        div,
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        ...look,
        div,
        DockItem(Icons.border_style_rounded, l.stroke, panel: ToolPanel.stroke),
        ...effects,
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
      ],
      RasterLayer r => [
        DockItem(
          Icons.find_replace_rounded,
          l.replaceImage,
          onTap: () => commands.replaceImage(r),
        ),
        ...basics,
        div,
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
        DockItem(
          Icons.auto_awesome_rounded,
          l.filters,
          panel: ToolPanel.filters,
        ),
        ...look,
        div,
        ...effects,
      ],
      IconLayer i => [
        DockItem(
          Icons.find_replace_rounded,
          l.changeIcon,
          onTap: () => commands.changeIcon(i),
        ),
        ...basics,
        div,
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        DockItem(Icons.style_rounded, l.style, panel: ToolPanel.iconStyle),
        ...look,
        div,
        DockItem(Icons.border_style_rounded, l.stroke, panel: ToolPanel.stroke),
        ...effects,
      ],
      PathLayer _ => [
        DockItem(Icons.draw_rounded, l.editPath, panel: ToolPanel.pen),
        ...basics,
        div,
        DockItem(Icons.line_style_rounded, l.lineStyle, panel: ToolPanel.line),
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        ...look,
        div,
        ...effects,
      ],
      DrawingLayer _ => [
        DockItem(Icons.brush_rounded, l.draw, panel: ToolPanel.brush),
        ...basics,
        div,
        DockItem(Icons.palette_rounded, l.color, panel: ToolPanel.fill),
        ...look,
        div,
        ...effects,
      ],
      GroupLayer g => [
        DockItem(
          Icons.folder_off_rounded,
          l.ungroup,
          onTap: () => editor.ungroup(g.id),
        ),
        ...basics,
        div,
        ...look,
        div,
        ...effects,
        DockItem(Icons.tune_rounded, l.adjust, panel: ToolPanel.adjust),
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
              if (item.divider)
                _DockDivider(vertical: vertical)
              else
                _DockButton(
                  item: item,
                  selected: item.panel != null && ui.panel == item.panel,
                  onTap: !item.enabled
                      ? null
                      : () {
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
            key: ValueKey(editor.hasMultiSelection ? 'multi' : layer?.kind),
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = onTap == null
        ? scheme.onSurface.withValues(alpha: 0.3)
        : item.destructive
        ? scheme.error
        : selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.78);
    return Pressable(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
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

class _DockDivider extends StatelessWidget {
  const _DockDivider({required this.vertical});
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).dividerColor;
    return vertical
        ? Divider(height: 12, indent: 18, endIndent: 18, color: c)
        : VerticalDivider(width: 12, indent: 18, endIndent: 26, color: c);
  }
}
