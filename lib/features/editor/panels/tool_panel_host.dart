import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../editor_scope.dart';
import 'adjust_panels.dart';
import 'canvas_panels.dart';
import 'layout_panels.dart';
import 'style_panels.dart';
import 'text_panels.dart';

/// Shows the open [ToolPanel] with a soft size/fade transition. Panels that
/// don't fit the current selection close themselves.
class ToolPanelHost extends StatelessWidget {
  const ToolPanelHost({
    super.key,
    required this.editor,
    required this.ui,
    this.maxHeight = 320,
  });

  final EditorController editor;
  final EditorUiState ui;
  final double maxHeight;

  Widget? _panelFor(ToolPanel? p, Layer? layer) {
    switch (p) {
      case null:
        return null;
      case ToolPanel.addShape:
        return AddShapePanel(
          editor: editor,
          onAdded: () => ui.panel = ToolPanel.shapeStyle,
        );
      case ToolPanel.background:
        return BackgroundPanel(editor: editor);
      default:
        break;
    }
    if (layer == null) return null;
    return switch (p) {
      ToolPanel.font when layer is TextLayer => FontPanel(
        editor: editor,
        layer: layer,
      ),
      ToolPanel.fill when layer is TextLayer || layer is ShapeLayer =>
        FillPanel(editor: editor, layer: layer),
      ToolPanel.stroke when layer is TextLayer || layer is ShapeLayer =>
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
                : ConstrainedBox(
                    key: ValueKey(ui.panel),
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 6),
                      child: panel,
                    ),
                  ),
          ),
        );
      },
    );
  }
}
