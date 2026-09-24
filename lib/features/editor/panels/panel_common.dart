import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
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
};

IconData shapeIcon(ShapeKind k) => switch (k) {
  ShapeKind.rectangle => Icons.crop_square_rounded,
  ShapeKind.ellipse => Icons.circle_outlined,
  ShapeKind.triangle => Icons.change_history_rounded,
  ShapeKind.star => Icons.star_outline_rounded,
  ShapeKind.polygon => Icons.hexagon_outlined,
  ShapeKind.heart => Icons.favorite_outline_rounded,
  ShapeKind.line => Icons.horizontal_rule_rounded,
};
