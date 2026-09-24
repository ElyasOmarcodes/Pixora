import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/effects/effect_registry.dart';
import '../../../document/model/effect.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../../../ui/widgets/pressable.dart';
import 'panel_common.dart';

/// Brightness, contrast, saturation… as non-destructive layer effects.
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  static const _icons = {
    'brightness': Icons.light_mode_rounded,
    'contrast': Icons.contrast_rounded,
    'saturation': Icons.water_drop_rounded,
    'hue': Icons.palette_rounded,
    'warmth': Icons.thermostat_rounded,
    'tint': Icons.gradient_rounded,
    'fade': Icons.blur_linear_rounded,
    'blur': Icons.blur_on_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final defs = EffectRegistry.instance
        .inCategory(EffectCategory.adjust)
        .toList();
    final hasAny = layer.props.effects.any(
      (e) => EffectRegistry.instance[e.type]?.category == EffectCategory.adjust,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelLabel(
          l.adjust,
          trailing: TextButton.icon(
            onPressed: hasAny
                ? () => editor.removeEffectsIn(layer.id, EffectCategory.adjust)
                : null,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(l.reset),
          ),
        ),
        for (final def in defs)
          Builder(
            builder: (context) {
              final p = def.params.first;
              final current =
                  editor
                      .effectOf(layer.id, def.type)
                      ?.number(p.key, p.defaultNumber) ??
                  p.defaultNumber;
              return PixSlider(
                icon: _icons[def.type],
                label: effectLabel(l, def.type),
                value: current,
                min: p.min,
                max: p.max,
                defaultValue: p.defaultNumber,
                format: p.max == 1 ? (v) => (v * 100).round().toString() : null,
                onChanged: (v) => editor.setEffectParam(
                  layer.id,
                  def.type,
                  p.key,
                  v,
                  live: true,
                ),
                onChangeEnd: (_) => editor.commit('adjust'),
              );
            },
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// One-tap looks with an intensity slider. Previews use the real layer
/// image when there is one.
class FiltersPanel extends StatelessWidget {
  const FiltersPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final defs = EffectRegistry.instance
        .inCategory(EffectCategory.filter)
        .toList();
    LayerEffect? active;
    for (final e in layer.props.effects) {
      if (EffectRegistry.instance[e.type]?.category == EffectCategory.filter) {
        active = e;
      }
    }
    final bytes = layer is RasterLayer
        ? editor.assets.bytesOf((layer as RasterLayer).assetId)
        : null;

    Widget thumb(List<double>? matrix) {
      Widget img = bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              cacheWidth: 160,
              gaplessPlayback: true,
            )
          : const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF9A8B),
                    Color(0xFF6A82FB),
                    Color(0xFF38EF7D),
                  ],
                ),
              ),
            );
      if (matrix != null) {
        img = ColorFiltered(
          colorFilter: ColorFilter.matrix(matrix),
          child: img,
        );
      }
      return img;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _FilterTile(
                label: l.filterNone,
                selected: active == null,
                onTap: () => editor.applyFilter(layer.id, null),
                child: thumb(null),
              ),
              for (final def in defs)
                _FilterTile(
                  label: effectLabel(l, def.type),
                  selected: active?.type == def.type,
                  onTap: () => editor.applyFilter(layer.id, def.type),
                  child: thumb(def.colorMatrix?.call(def.create())),
                ),
            ],
          ),
        ),
        if (active != null)
          PixSlider(
            label: l.intensity,
            value: active.number('amount', 1),
            min: 0,
            max: 1,
            defaultValue: 1,
            format: (v) => '${(v * 100).round()}%',
            onChanged: (v) => editor.setEffectParam(
              layer.id,
              active!.type,
              'amount',
              v,
              live: true,
            ),
            onChangeEnd: (_) => editor.commit('filter'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.93,
      haptic: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          children: [
            AnimatedContainer(
              duration: PixTokens.fast,
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PixTokens.radiusM),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PixTokens.radiusM - 4),
                child: child,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
