import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/blend.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pressable.dart';

/// Typed edits on the selected layer, mapped onto preview/commit.
extension SelectedLayerEdits on EditorController {
  /// Edits the selected layer if it is a [T]. With [live] the change is a
  /// preview (call [commit] when the gesture ends).
  void editSelected<T extends Layer>(
    T Function(T l) f, {
    bool live = false,
    String label = 'edit',
  }) {
    final l = selectedLayer;
    if (l is! T) return;
    live
        ? previewLayer(l.id, (x) => f(x as T))
        : updateLayer(l.id, (x) => f(x as T), label: label);
  }
}

/// Square tile with an icon over a label; used in panel grids and rows.
class PanelTile extends StatelessWidget {
  const PanelTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.width = 76,
    this.iconWidget,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurface;
    return Pressable(
      onTap: onTap,
      scale: 0.92,
      haptic: true,
      child: AnimatedContainer(
        duration: PixTokens.fast,
        width: width,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget ??
                Icon(
                  icon,
                  color: onTap == null ? fg.withValues(alpha: 0.35) : fg,
                  size: 24,
                ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: onTap == null ? fg.withValues(alpha: 0.35) : fg,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of [PanelTile]s.
class TileRow extends StatelessWidget {
  const TileRow({super.key, required this.children, this.height = 78});
  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: children,
    ),
  );
}

/// Small caption above a group of controls inside a panel.
class PanelLabel extends StatelessWidget {
  const PanelLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

String effectLabel(AppLocalizations l, String type) => switch (type) {
  'brightness' => l.brightness,
  'contrast' => l.contrast,
  'saturation' => l.saturation,
  'hue' => l.hue,
  'warmth' => l.warmth,
  'tint' => l.tint,
  'fade' => l.fade,
  'blur' => l.blur,
  'mono' => l.filterMono,
  'sepia' => l.filterSepia,
  'invert' => l.filterInvert,
  'vintage' => l.filterVintage,
  'vivid' => l.filterVivid,
  'cool' => l.filterCool,
  'warm' => l.filterWarm,
  'noir' => l.filterNoir,
  'dramatic' => l.filterDramatic,
  'shadow' => l.shadow,
  'glow' => l.glow,
  _ => type,
};

String shapeLabel(AppLocalizations l, ShapeKind k) => switch (k) {
  ShapeKind.rectangle => l.shapeRectangle,
  ShapeKind.ellipse => l.shapeEllipse,
  ShapeKind.triangle => l.shapeTriangle,
  ShapeKind.star => l.shapeStar,
  ShapeKind.polygon => l.shapePolygon,
  ShapeKind.heart => l.shapeHeart,
  ShapeKind.line => l.shapeLine,
  ShapeKind.diamond => l.shapeDiamond,
  ShapeKind.parallelogram => l.shapeParallelogram,
  ShapeKind.trapezoid => l.shapeTrapezoid,
  ShapeKind.cross => l.shapeCross,
  ShapeKind.crescent => l.shapeCrescent,
  ShapeKind.speechBubble => l.shapeSpeechBubble,
  ShapeKind.blockArrow => l.shapeBlockArrow,
  ShapeKind.chevron => l.shapeChevron,
  ShapeKind.gear => l.shapeGear,
  ShapeKind.frame => l.shapeFrame,
};

/// "Blend mode ▾" row: a label and a menu of Photoshop's modes, grouped.
class BlendModeRow extends StatelessWidget {
  const BlendModeRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final PixBlendMode value;
  final ValueChanged<PixBlendMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          PopupMenuButton<PixBlendMode>(
            initialValue: value,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final m in PixBlendMode.values) ...[
                if (m.index > 0 &&
                    m.category != PixBlendMode.values[m.index - 1].category)
                  const PopupMenuDivider(),
                PopupMenuItem(
                  value: m,
                  height: 40,
                  child: Text(m.label, textDirection: TextDirection.ltr),
                ),
              ],
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(PixTokens.radiusM),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value.label,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
