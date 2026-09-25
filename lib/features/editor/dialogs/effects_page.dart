import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/effects/effect_registry.dart';
import '../../../document/model/effect.dart';
import '../../../document/model/fill.dart';
import '../../../document/model/layer.dart';
import '../../../document/model/layer_stroke.dart';
import '../../../document/model/layer_transform.dart';
import '../../../document/render/document_renderer.dart';
import '../../../document/render/mask_jobs.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/checkerboard.dart';
import '../../../ui/widgets/pressable.dart';
import '../editor_scope.dart';
import '../effects_catalog.dart';
import '../panels/style_panels.dart';

/// What to open after the Layer effects page closes.
class EffectsPageResult {
  const EffectsPageResult(this.panel, {this.effectId, this.inner = false});
  final ToolPanel panel;
  final String? effectId;
  final bool inner;
}

/// Full-page catalogue of layer effects, Photoshop style: pixel filters
/// (Blur, Noise — stackable, applied before the mask like smart filters),
/// layer styles and colour. Thumbnails show the layer itself with each
/// effect. Picking one adds it and returns the panel that edits it.
Future<EffectsPageResult?> showEffectsPage(
  BuildContext context, {
  required EditorController editor,
  required String layerId,
}) => Navigator.of(context).push<EffectsPageResult>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _EffectsPage(editor: editor, layerId: layerId),
  ),
);

class _EffectsPage extends StatelessWidget {
  const _EffectsPage({required this.editor, required this.layerId});
  final EditorController editor;
  final String layerId;

  bool _has(Layer layer, String key) {
    final p = layer.props;
    return switch (key) {
      'stroke' => p.stroke?.visible ?? false,
      'adjust' => p.effects.any(
        (e) =>
            e.enabled &&
            EffectRegistry.instance[e.type]?.category == EffectCategory.adjust,
      ),
      'filters' => p.effects.any(
        (e) =>
            e.enabled &&
            EffectRegistry.instance[e.type]?.category == EffectCategory.filter,
      ),
      _ => p.effects.any((e) => e.type == key && e.enabled),
    };
  }

  void _pick(BuildContext context, Layer layer, FxEntry entry) {
    final nav = Navigator.of(context);
    final size = layerLocalSize(layer);
    if (entry.isFilter) {
      final def = EffectRegistry.instance[entry.key]!;
      final fx = def.create(suggestedParams(entry.key, layer, size));
      editor.updateProps(
        layer.id,
        (p) => p.copyWith(effects: [...p.effects, fx]),
        label: 'effect',
      );
      nav.pop(EffectsPageResult(ToolPanel.effect, effectId: fx.id));
      return;
    }
    switch (entry.key) {
      case 'stroke':
        final s = StrokePanel.strokeOf(layer);
        if (s == null || !s.visible) {
          final side = math.max(size.width, size.height);
          final next =
              (s ??
                      LayerStroke(
                        size: 0,
                        fill: PixFill.color(const Color(0xFF000000)),
                      ))
                  .copyWith(
                    size: s == null || s.size <= 0
                        ? (side * 0.012).clamp(2.0, 12.0).roundToDouble()
                        : null,
                    enabled: true,
                  );
          editor.updateLayer(
            layer.id,
            (x) => StrokePanel.withStroke(x, next),
            label: 'stroke',
          );
        }
      case 'adjust' || 'filters':
        break;
      default:
        final existing = editor.effectOf(layer.id, entry.key);
        if (existing == null) {
          final def = EffectRegistry.instance[entry.key];
          if (def != null) {
            editor.updateProps(
              layer.id,
              (p) => p.copyWith(effects: [...p.effects, def.create()]),
              label: 'effect',
            );
          }
        } else if (!existing.enabled) {
          editor.toggleEffect(layer.id, existing.id);
        }
    }
    nav.pop(EffectsPageResult(entry.panel!, inner: entry.inner ?? false));
  }

  void _edit(BuildContext context, LayerEffect e) {
    final (panel, inner) = panelForEffect(e.type);
    Navigator.of(context).pop(
      panel == null
          ? EffectsPageResult(ToolPanel.effect, effectId: e.id)
          : EffectsPageResult(panel, inner: inner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final layer = editor.document.layerById(layerId);
        if (layer == null) return const Scaffold();
        final applied = listedEffects(layer);
        final stroke = layer.props.stroke;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.layerEffects),
                Text(
                  layer.props.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l.copyEffects,
                onPressed: () {
                  editor.copyStyle(layer.id);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l.effectsCopied)));
                },
                icon: const Icon(Icons.style_rounded),
              ),
              IconButton(
                tooltip: l.pasteEffects,
                onPressed: editor.hasCopiedStyle
                    ? () => editor.pasteStyle([layer.id])
                    : null,
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (applied.isNotEmpty || stroke != null) ...[
                _SectionTitle(
                  l.onThisLayer,
                  trailing: TextButton.icon(
                    onPressed: () => editor.clearStyle(layer.id),
                    icon: const Icon(Icons.layers_clear_rounded, size: 18),
                    label: Text(l.clearEffects),
                  ),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final e in applied)
                        _AppliedRow(
                          icon: fxIcon(e.type),
                          label: fxLabel(l, e.type),
                          enabled: e.enabled,
                          onToggle: () => editor.toggleEffect(layer.id, e.id),
                          onEdit: () => _edit(context, e),
                          onDelete: () => editor.removeEffect(layer.id, e.id),
                        ),
                      if (stroke != null)
                        _AppliedRow(
                          icon: fxIcon('stroke'),
                          label: l.stroke,
                          enabled: stroke.enabled,
                          onToggle: () => editor.toggleStroke(layer.id),
                          onEdit: () => Navigator.of(context)
                              .pop(const EffectsPageResult(ToolPanel.stroke)),
                          onDelete: () => editor.updateLayer(
                            layer.id,
                            (x) => StrokePanel.withStroke(x, null),
                            label: 'stroke',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (final g in FxGroup.values) ...[
                _SectionTitle(fxGroupLabel(l, g)),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = math.max(3, (c.maxWidth / 124).floor());
                    final w = (c.maxWidth - (cols - 1) * 10) / cols;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final entry in fxCatalog)
                          if (entry.group == g &&
                              (entry.key != 'stroke' || layer is! GroupLayer))
                            _FxCard(
                              width: w,
                              label: fxLabel(l, entry.key),
                              icon: entry.icon,
                              on: _has(layer, entry.key),
                              preview: g == FxGroup.color
                                  ? null
                                  : _previewLayer(layer, entry.key),
                              assets: editor,
                              onTap: () => _pick(context, layer, entry),
                            ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The layer on its own, upright, with just the effect [key].
  Layer? _previewLayer(Layer layer, String key) {
    if (layer is GroupLayer) return null;
    final size = layerLocalSize(layer);
    final p = layer.props;
    final base = layer.withProps(
      p.copyWith(
        // Upright and unscaled, keeping mirroring.
        transform: LayerTransform(
          scaleX: p.transform.scaleX < 0 ? -1 : 1,
          scaleY: p.transform.scaleY < 0 ? -1 : 1,
        ),
        opacity: 1,
        effects: const [],
        clearStroke: true,
        fillOpacity: 1,
      ),
    );
    if (key == 'stroke') {
      final side = math.max(size.width, size.height);
      return base.update(
        (q) => q.copyWith(
          stroke: LayerStroke(
            size: side * 0.04,
            fill: PixFill.color(const Color(0xFF111111)),
          ),
        ),
      );
    }
    final def = EffectRegistry.instance[key];
    if (def == null) return base;
    return base.update(
      (q) => q.copyWith(effects: [def.create(previewParams(key, size))]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _AppliedRow extends StatelessWidget {
  const _AppliedRow({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      dense: true,
      leading: IconButton(
        tooltip: enabled ? l.hide : l.show,
        onPressed: onToggle,
        icon: Icon(
          enabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        ),
      ),
      title: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: enabled ? null : Theme.of(context).disabledColor,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: l.delete,
        onPressed: onDelete,
        icon: const Icon(Icons.close_rounded),
      ),
      onTap: onEdit,
    );
  }
}

class _FxCard extends StatelessWidget {
  const _FxCard({
    required this.width,
    required this.label,
    required this.icon,
    required this.on,
    required this.preview,
    required this.assets,
    required this.onTap,
  });
  final double width;
  final String label;
  final IconData icon;
  final bool on;
  final Layer? preview;
  final EditorController assets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      haptic: true,
      semanticLabel: label,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(PixTokens.radiusM),
          border: Border.all(
            color: on ? scheme.primary : scheme.outlineVariant,
            width: on ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: preview == null
                  ? Icon(icon, size: 34, color: scheme.primary)
                  : CustomPaint(
                      painter: _PreviewPainter(
                        preview!,
                        assets,
                        MediaQuery.devicePixelRatioOf(context),
                        scheme.surfaceContainerHighest,
                        scheme.surfaceContainerLow,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (on) ...[
                    Icon(Icons.check_circle, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.layer, this.editor, this.dpr, this.a, this.b)
    : super(repaint: MaskJobCache.instance);
  final Layer layer;
  final EditorController editor;
  final double dpr;
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    paintCheckerboard(canvas, area, a, b, cell: 8);
    final box = layerLocalRect(layer);
    if (box.isEmpty || !box.isFinite) return;
    final room = box.inflate(box.longestSide * 0.16);
    final s = math.min(size.width / room.width, size.height / room.height);
    canvas
      ..save()
      ..clipRect(area)
      ..translate(size.width / 2, size.height / 2)
      ..scale(s)
      ..translate(-room.center.dx, -room.center.dy);
    DocumentRenderer(
      editor.assets,
      pixelScale: s * dpr,
    ).paintLayer(canvas, layer);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.layer != layer || old.dpr != dpr || old.a != a;
}
