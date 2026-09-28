import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/effects/effect_registry.dart';
import '../../../document/model/effect.dart';
import '../../../editor/editor_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/fill_picker.dart';
import '../../../ui/widgets/pressable.dart';
import '../effects_catalog.dart';
import 'effect_panels.dart';
import 'panel_common.dart';

/// Solid / gradient / transparent background of the canvas.
class BackgroundPanel extends StatelessWidget {
  const BackgroundPanel({super.key, required this.editor});
  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final bg = editor.document.background;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FillPicker(
          value: bg,
          allowTransparent: true,
          aspect: editor.document.width / editor.document.height,
          onChanged: (f, {required live}) =>
              editor.setBackground(f, live: live),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Effects on the canvas background: blur, noise, grain, vignette and
/// colour adjustments — rendered like layer effects on the background.
class BackgroundEffectsPanel extends StatefulWidget {
  const BackgroundEffectsPanel({super.key, required this.editor});
  final EditorController editor;

  @override
  State<BackgroundEffectsPanel> createState() => _BackgroundEffectsPanelState();
}

class _BackgroundEffectsPanelState extends State<BackgroundEffectsPanel> {
  static const _types = <(String, IconData)>[
    ('gaussianBlur', Icons.blur_on_rounded),
    ('addNoise', Icons.grain_rounded),
    ('filmGrain', Icons.movie_filter_rounded),
    ('vignette', Icons.vignette_rounded),
    ('brightness', Icons.brightness_6_rounded),
    ('contrast', Icons.contrast_rounded),
    ('saturation', Icons.water_drop_rounded),
    ('hue', Icons.palette_rounded),
    ('warmth', Icons.thermostat_rounded),
    ('mono', Icons.filter_b_and_w_rounded),
    ('mosaic', Icons.grid_view_rounded),
    ('tiltShift', Icons.vertical_align_center_rounded),
  ];

  String _type = 'gaussianBlur';

  EditorController get e => widget.editor;

  LayerEffect? _find(String type) =>
      e.document.backgroundEffects.where((x) => x.type == type).firstOrNull;

  Map<String, Object> _defaults(String type) {
    final d = e.document;
    final side = math.max(d.width, d.height);
    return switch (type) {
      'gaussianBlur' => {'radius': (side * 0.012).roundToDouble()},
      'addNoise' => {'amount': 10, 'mono': 1},
      'mosaic' => {'cell': (side / 40).roundToDouble()},
      'tiltShift' => {'blur': (side * 0.01).roundToDouble()},
      'brightness' || 'contrast' || 'saturation' || 'warmth' => {'value': 0.2},
      'hue' => {'value': 30},
      _ => const {},
    };
  }

  void _add(String type) {
    final def = EffectRegistry.instance[type];
    if (def == null || _find(type) != null) return;
    e.updateBackgroundEffects((fx) => [...fx, def.create(_defaults(type))]);
  }

  void _replace(LayerEffect fx, {bool live = false}) =>
      e.updateBackgroundEffects(
        (list) => [for (final x in list) x.id == fx.id ? fx : x],
        live: live,
      );

  List<FxControl> _controls(AppLocalizations l, String type) => switch (type) {
    'brightness' ||
    'contrast' ||
    'saturation' ||
    'hue' ||
    'warmth' => [FxSlider('value', effectLabel(l, type))],
    'mono' => [FxSlider('amount', l.amount)],
    _ => filterControls(l, type),
  };

  String _label(AppLocalizations l, String type) => fxLabel(l, type);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final fx = _find(_type);
    final def = EffectRegistry.instance[_type]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final (type, icon) in _types)
                _FxTile(
                  icon: icon,
                  label: _label(l, type),
                  selected: type == _type,
                  active: _find(type)?.enabled ?? false,
                  onTap: () {
                    setState(() => _type = type);
                    _add(type);
                  },
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: fx == null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _add(_type),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_label(l, _type)),
                  ),
                )
              : Column(
                  key: ValueKey(fx.type),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        18,
                        0,
                        8,
                        0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _label(l, fx.type),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Switch(
                            value: fx.enabled,
                            onChanged: (on) =>
                                _replace(fx.copyWith(enabled: on)),
                          ),
                          IconButton(
                            tooltip: l.delete,
                            color: scheme.error,
                            onPressed: () => e.updateBackgroundEffects(
                              (list) => [
                                for (final x in list)
                                  if (x.id != fx.id) x,
                              ],
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                    for (final c in _controls(l, fx.type))
                      buildFxControl(
                        context,
                        c,
                        def,
                        valueOf: (k) => (_find(fx.type) ?? fx).number(
                          k,
                          def.param(k)?.defaultNumber ?? 0,
                        ),
                        colorOf: (k) =>
                            (_find(fx.type) ?? fx).color(k, Colors.black),
                        set: (k, v, {bool live = false}) {
                          final cur = _find(fx.type);
                          if (cur == null) return;
                          _replace(cur.withParam(k, v), live: live);
                        },
                        commit: () => e.commit('background'),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FxTile extends StatelessWidget {
  const _FxTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 76,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: fg, size: 24),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
