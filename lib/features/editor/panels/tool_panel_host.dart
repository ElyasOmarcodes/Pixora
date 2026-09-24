import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../editor_scope.dart';
import 'adjust_panels.dart';
import 'canvas_panels.dart';
import 'effect_panels.dart';
import 'guides_panels.dart';
import 'layout_panels.dart';
import 'brush_panel.dart';
import 'mask_panel.dart';
import 'style_panels.dart';
import 'text_panels.dart';
import 'transform_panels.dart';
import 'vector_panels.dart';
import '../pen_targets.dart';

/// Page-level actions panels need.
class PanelHooks {
  const PanelHooks({
    required this.addIcon,
    required this.startPen,
    required this.startBrush,
    required this.maskPen,
  });
  final VoidCallback addIcon;
  final VoidCallback startPen;
  final VoidCallback startBrush;
  final MaskPenTarget maskPen;
}

/// Shows the open [ToolPanel] with a soft size/fade transition. Panels that
/// don't fit the current selection close themselves.
class ToolPanelHost extends StatelessWidget {
  const ToolPanelHost({
    super.key,
    required this.editor,
    required this.ui,
    required this.hooks,
    this.maxHeight = 320,
  });

  final EditorController editor;
  final EditorUiState ui;
  final double maxHeight;

  /// Actions panels hand back to the editor page.
  final PanelHooks hooks;

  Widget? _panelFor(ToolPanel? p, Layer? layer) {
    switch (p) {
      case null:
        return null;
      case ToolPanel.addShape:
        return AddShapePanel(
          editor: editor,
          onAdded: () => ui.panel = editor.selectedLayer is PathLayer
              ? ToolPanel.line
              : ToolPanel.shapeStyle,
          onIcons: hooks.addIcon,
          onPen: hooks.startPen,
          onBrush: hooks.startBrush,
        );
      case ToolPanel.background:
        return BackgroundPanel(editor: editor);
      case ToolPanel.grid:
        return GridPanel(editor: editor, ui: ui);
      case ToolPanel.snap:
        return const SnapPanel();
      case ToolPanel.rulers:
        return RulerPanel(editor: editor);
      default:
        break;
    }
    if (layer == null) return null;
    return switch (p) {
      ToolPanel.textStyle when layer is TextLayer => TextStylePanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.curve when layer is TextLayer => CurvePanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.textBackground when layer is TextLayer => TextBackgroundPanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.spacing when layer is TextLayer => SpacingPanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.move => MovePanel(editor: editor, layer: layer),
      ToolPanel.position => PositionPanel(editor: editor, layer: layer),
      ToolPanel.size => SizePanel(editor: editor, layer: layer),
      ToolPanel.rotate => RotatePanel(editor: editor, layer: layer),
      ToolPanel.mask => MaskPanel(
        editor: editor,
        ui: ui,
        layer: layer,
        maskPen: hooks.maskPen,
      ),
      ToolPanel.pen when layer is PathLayer => PenPanel(
        state: ui.penState,
        onDone: () => ui.panel = ToolPanel.line,
      ),
      ToolPanel.brush when layer is DrawingLayer => BrushPanel(
        settings: ui.brushSettings,
        onDone: () => ui.panel = null,
      ),
      ToolPanel.line when layer is PathLayer => LinePanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.iconStyle when layer is IconLayer => IconStylePanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.glow => GlowPanel(editor: editor, layer: layer),
      ToolPanel.bevel => BevelPanel(editor: editor, layer: layer),
      ToolPanel.extrude => Extrude3DPanel(editor: editor, layer: layer),
      ToolPanel.fill
          when layer is TextLayer ||
              layer is ShapeLayer ||
              layer is IconLayer ||
              layer is PathLayer ||
              layer is DrawingLayer =>
        FillPanel(editor: editor, layer: layer),
      ToolPanel.stroke
          when layer is TextLayer ||
              layer is ShapeLayer ||
              layer is IconLayer =>
        StrokePanel(editor: editor, layer: layer),
      ToolPanel.shadow => ShadowPanel(editor: editor, layer: layer),
      ToolPanel.adjust => AdjustPanel(editor: editor, layer: layer),
      ToolPanel.filters => FiltersPanel(editor: editor, layer: layer),
      ToolPanel.opacity => OpacityPanel(editor: editor, layer: layer),
      ToolPanel.arrange => ArrangePanel(editor: editor, layer: layer),
      ToolPanel.shapeStyle when layer is ShapeLayer => ShapeStylePanel(
        editor: editor,
        layer: layer,
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([editor, ui]),
      builder: (context, _) {
        final panel = _panelFor(ui.panel, editor.selectedLayer);
        return AnimatedSize(
          duration: PixTokens.medium,
          curve: PixTokens.emphasized,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: PixTokens.fast,
            switchInCurve: PixTokens.curve,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: panel == null
                ? const SizedBox(width: double.infinity, key: ValueKey('none'))
                : Column(
                    key: ValueKey(ui.panel),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PanelHeader(onClose: () => ui.panel = null),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        child: SingleChildScrollView(child: panel),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Grab handle + close button on top of every panel. Tap the handle,
/// swipe it down or tap ✕ to close the panel.
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 150) onClose();
      },
      child: SizedBox(
        width: double.infinity,
        height: 34,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            PositionedDirectional(
              end: 8,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
