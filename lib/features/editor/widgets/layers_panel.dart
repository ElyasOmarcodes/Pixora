import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/layer_transform.dart';
import '../../../document/render/document_renderer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/checkerboard.dart';
import '../../home/widgets/text_prompt.dart';

/// The layer stack, topmost first. Drag to reorder, tap to select, toggle
/// visibility and lock inline, double-tap a name to rename.
class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.editor, this.onClose});

  final EditorController editor;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final layers = editor.document.layers.reversed.toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(18, 10, 6, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.layers,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.layerCount(layers.length),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (onClose != null)
                    IconButton(
                      tooltip: l.close,
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
            ),
            Expanded(
              child: layers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l.noLayers,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: layers.length,
                      proxyDecorator: (child, _, a) => Material(
                        color: Colors.transparent,
                        elevation: 8 * a.value,
                        borderRadius: BorderRadius.circular(PixTokens.radiusM),
                        child: child,
                      ),
                      onReorderItem: (oldIndex, newIndex) {
                        final n = layers.length;
                        // Displayed top-first; the document is bottom-first.
                        editor.moveLayerTo(
                          layers[oldIndex].id,
                          n - 1 - newIndex,
                        );
                      },
                      itemBuilder: (context, i) => _LayerRow(
                        key: ValueKey(layers[i].id),
                        index: i,
                        layer: layers[i],
                        editor: editor,
                        selected: layers[i].id == editor.selectedId,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.layer,
    required this.editor,
    required this.selected,
  });

  final int index;
  final Layer layer;
  final EditorController editor;
  final bool selected;

  IconData get _kindIcon => switch (layer) {
    TextLayer _ => Icons.title_rounded,
    ShapeLayer _ => Icons.category_rounded,
    RasterLayer _ => Icons.image_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pix = PixColors.of(context);
    final p = layer.props;
    final dim = !p.visible;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(PixTokens.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          onTap: () => editor.select(selected ? null : layer.id),
          onDoubleTap: () async {
            final name = await showTextPrompt(
              context,
              title: l.rename,
              label: l.layerName,
              initial: p.name,
            );
            if (name != null && name.trim().isNotEmpty) {
              editor.rename(layer.id, name.trim());
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: PixTokens.fast,
                  opacity: dim ? 0.4 : 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CheckerboardBox(
                            a: pix.checkerA,
                            b: pix.checkerB,
                            cell: 5,
                          ),
                          CustomPaint(
                            painter: _LayerThumbPainter(layer, editor),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedOpacity(
                    duration: PixTokens.fast,
                    opacity: dim ? 0.5 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              _kindIcon,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            if (layer is TextLayer) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  (layer as TextLayer).text.replaceAll(
                                    '\n',
                                    ' ',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: p.locked ? l.unlock : l.lock,
                  onPressed: () => editor.toggleLocked(layer.id),
                  icon: Icon(
                    p.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 20,
                    color: p.locked
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: p.visible ? l.hide : l.show,
                  onPressed: () => editor.toggleVisible(layer.id),
                  icon: Icon(
                    p.visible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 20,
                    color: p.visible
                        ? scheme.onSurfaceVariant
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
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

/// Draws one layer, un-transformed and fitted into the thumbnail box.
class _LayerThumbPainter extends CustomPainter {
  _LayerThumbPainter(this.layer, this.editor) : super(repaint: editor.assets);
  final Layer layer;
  final EditorController editor;

  @override
  void paint(Canvas canvas, Size size) {
    final t = layer.props.transform;
    final plain = layer.withProps(
      layer.props.copyWith(
        opacity: 1,
        visible: true,
        transform: LayerTransform(scaleX: t.scaleX.sign, scaleY: t.scaleY.sign),
      ),
    );
    final s = layerLocalSize(plain);
    if (s.isEmpty) return;
    final fit = math.min(
      (size.width - 6) / s.width,
      (size.height - 6) / s.height,
    );
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(fit);
    editor.renderer.paintLayer(canvas, plain);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerThumbPainter old) => old.layer != layer;
}
