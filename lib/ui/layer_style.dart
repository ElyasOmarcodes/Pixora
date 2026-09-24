import 'package:flutter/material.dart';

import '../document/model/layer.dart';
import '../l10n/app_localizations.dart';

/// Visual identity per layer kind: every place that shows a layer (panel
/// rows, thumbnails, badges, quick-edit menus) uses the same color and icon,
/// so users learn to recognise layer types at a glance.
abstract final class LayerStyle {
  static Color color(LayerKind k) => switch (k) {
    LayerKind.text => const Color(0xFF3D7BFF),
    LayerKind.raster => const Color(0xFF16B38A),
    LayerKind.shape => const Color(0xFFFF8A3D),
    LayerKind.group => const Color(0xFF9B6BFF),
    LayerKind.icon => const Color(0xFFE84393),
    LayerKind.path => const Color(0xFF0FB9B1),
    LayerKind.drawing => const Color(0xFFF43F5E),
  };

  static IconData icon(LayerKind k) => switch (k) {
    LayerKind.text => Icons.title_rounded,
    LayerKind.raster => Icons.image_rounded,
    LayerKind.shape => Icons.category_rounded,
    LayerKind.group => Icons.folder_rounded,
    LayerKind.icon => Icons.emoji_symbols_rounded,
    LayerKind.path => Icons.draw_rounded,
    LayerKind.drawing => Icons.brush_rounded,
  };

  static String label(AppLocalizations l, LayerKind k) => switch (k) {
    LayerKind.text => l.text,
    LayerKind.raster => l.image,
    LayerKind.shape => l.shape,
    LayerKind.group => l.group,
    LayerKind.icon => l.icon,
    LayerKind.path => l.vector,
    LayerKind.drawing => l.drawing,
  };
}

/// Width classes the layout adapts to (Material 3 window size classes).
enum ScreenClass {
  /// Phones in portrait.
  compact,

  /// Large phones in landscape, small tablets.
  medium,

  /// Tablets in landscape, small laptops.
  expanded,

  /// Desktops.
  large;

  static ScreenClass of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return compact;
    if (w < 840) return medium;
    if (w < 1200) return expanded;
    return large;
  }

  bool get isWide => index >= expanded.index;

  /// Width of the layers drawer / side panel for this class.
  double panelWidth(double screenWidth) => switch (this) {
    compact => (screenWidth * 0.88).clamp(280.0, 380.0),
    medium => 380,
    expanded => 340,
    large => 380,
  };
}
