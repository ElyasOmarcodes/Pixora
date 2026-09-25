import 'package:flutter/material.dart';

import '../../../document/effects/effect_registry.dart';
import '../../../document/model/layer.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../effects_catalog.dart';
import 'effect_panels.dart';

/// Settings of one pixel filter on a layer (Gaussian blur, Add noise…),
/// with show/hide and remove. Filters stack, so it edits by effect id.
class FilterEffectPanel extends StatelessWidget {
  const FilterEffectPanel({
    super.key,
    required this.editor,
    required this.layer,
    required this.effectId,
  });

  final EditorController editor;
  final Layer layer;
  final String effectId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final effect = editor.effectById(layer.id, effectId);
    final def = effect == null ? null : EffectRegistry.instance[effect.type];
    if (effect == null || def == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l.noEffects, textAlign: TextAlign.center),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 8, 4),
          child: Row(
            children: [
              Icon(fxIcon(effect.type), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  fxLabel(l, effect.type),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: effect.enabled ? l.hide : l.show,
                onPressed: () => editor.toggleEffect(layer.id, effectId),
                icon: Icon(
                  effect.enabled
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
              IconButton(
                tooltip: l.delete,
                onPressed: () => editor.removeEffect(layer.id, effectId),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: effect.enabled ? 1 : 0.45,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in filterControls(l, effect.type))
                buildFxControl(
                  context,
                  c,
                  def,
                  valueOf: (k) =>
                      effect.number(k, def.param(k)?.defaultNumber ?? 0),
                  colorOf: (k) => effect.color(
                    k,
                    def.param(k)?.defaultColor ?? const Color(0xFF000000),
                  ),
                  set: (k, v, {live = false}) => editor.setEffectParamById(
                    layer.id,
                    effectId,
                    k,
                    v,
                    live: live,
                  ),
                  commit: () => editor.commit('effect'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Photoshop's Satin: inner shading that follows the shape's contours.
class SatinPanel extends StatelessWidget {
  const SatinPanel({super.key, required this.editor, required this.layer});
  final EditorController editor;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String px(double v) => '${v.round()} px';
    return EffectEditor(
      editor: editor,
      layer: layer,
      type: 'satin',
      title: l.satin,
      controls: [
        FxBlend(l.blendMode),
        const FxColor('color'),
        FxSlider('opacity', l.opacity),
        FxSlider('angle', l.angle, format: fxDegrees),
        FxSlider('distance', l.distance, format: px),
        FxSlider('size', l.size, format: px),
        FxToggle('invert', l.invert),
      ],
    );
  }
}
