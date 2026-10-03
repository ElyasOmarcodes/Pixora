import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../document/model/layer.dart';
import '../../../document/render/brush_paint.dart';
import '../../../editor/tools/draw_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/pix_slider.dart';

/// Photoshop's Brush Settings for tip brushes: tip shape, shape dynamics
/// with taper, scattering, transfer and colour dynamics, over a live
/// preview stroke.
Future<void> showBrushSettings(BuildContext context, BrushSettings settings) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.4,
        maxChildSize: 0.96,
        builder: (context, scroll) =>
            _BrushSettingsBody(settings: settings, scroll: scroll),
      ),
    );

class _BrushSettingsBody extends StatelessWidget {
  const _BrushSettingsBody({required this.settings, required this.scroll});
  final BrushSettings settings;
  final ScrollController scroll;

  String _shapeLabel(AppLocalizations l, TipShape s) => switch (s) {
    TipShape.round => l.tipRound,
    TipShape.square => l.tipSquare,
    TipShape.diamond => l.tipDiamond,
    TipShape.star => l.tipStar,
    TipShape.leaf => l.tipLeaf,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final t = settings.tip ?? const BrushTip();
        void set(BrushTip v) => settings.tip = v;
        String pct(double v) => '${(v * 100).round()}%';
        Widget slider(
          String label,
          double value,
          double min,
          double max,
          double def,
          ValueChanged<double> f, {
          String Function(double)? format,
        }) => PixSlider(
          label: label,
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          defaultValue: def,
          format: format ?? pct,
          onChanged: f,
        );
        Widget section(String title, IconData icon) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
        Widget toggle(String label, bool value, ValueChanged<bool> f) =>
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(label),
              value: value,
              onChanged: f,
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l.brushSettings,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: settings.tipChanged
                        ? () => settings.tip = null
                        : null,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: Text(l.resetBrush),
                  ),
                ],
              ),
            ),
            // The stroke as it will draw, pinned above the settings.
            Container(
              height: 96,
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              decoration: BoxDecoration(
                color: settings.color.computeLuminance() > 0.7
                    ? const Color(0xFF2B2F36)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                size: Size.infinite,
                painter: BrushStrokePreview(settings),
              ),
            ),
            if (BrushTip.presetFor(settings.type) == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                child: Text(
                  l.brushSettingsHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  section(l.brushTipShape, Icons.brush_rounded),
                  SizedBox(
                    height: 74,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final s in TipShape.values)
                          _ShapeChip(
                            shape: s,
                            label: _shapeLabel(l, s),
                            selected: t.shape == s,
                            onTap: () => set(t.copyWith(shape: s)),
                          ),
                      ],
                    ),
                  ),
                  slider(
                    l.brushSize,
                    settings.size,
                    1,
                    300,
                    12,
                    (v) => settings.size = v,
                    format: (v) => '${v.round()} px',
                  ),
                  slider(
                    l.hardness,
                    t.hardness,
                    0,
                    1,
                    1,
                    (v) => set(t.copyWith(hardness: v)),
                  ),
                  slider(
                    l.spacing,
                    t.spacing,
                    0.02,
                    3,
                    0.12,
                    (v) => set(t.copyWith(spacing: v)),
                  ),
                  slider(
                    l.angle,
                    t.angle,
                    -180,
                    180,
                    0,
                    (v) => set(t.copyWith(angle: v)),
                    format: (v) => '${v.round()}°',
                  ),
                  slider(
                    l.roundness,
                    t.roundness,
                    0.05,
                    1,
                    1,
                    (v) => set(t.copyWith(roundness: v)),
                  ),
                  toggle(
                    l.followDirection,
                    t.followPath,
                    (v) => set(t.copyWith(followPath: v)),
                  ),
                  section(l.shapeDynamics, Icons.auto_graph_rounded),
                  slider(
                    l.sizeJitter,
                    t.sizeJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(sizeJitter: v)),
                  ),
                  slider(
                    l.minimumDiameter,
                    t.minSize,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(minSize: v)),
                  ),
                  slider(
                    l.angleJitter,
                    t.angleJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(angleJitter: v)),
                  ),
                  toggle(
                    l.sizeFromPressure,
                    t.pressureSize,
                    (v) => set(t.copyWith(pressureSize: v)),
                  ),
                  slider(
                    l.taperStart,
                    t.taperStart,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(taperStart: v)),
                  ),
                  slider(
                    l.taperEnd,
                    t.taperEnd,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(taperEnd: v)),
                  ),
                  section(l.scattering, Icons.scatter_plot_rounded),
                  slider(
                    l.scatterAmount,
                    t.scatter,
                    0,
                    5,
                    0,
                    (v) => set(t.copyWith(scatter: v)),
                  ),
                  slider(
                    l.dabCount,
                    t.count.toDouble(),
                    1,
                    16,
                    1,
                    (v) => set(t.copyWith(count: v.round())),
                    format: (v) => '${v.round()}',
                  ),
                  slider(
                    l.countJitter,
                    t.countJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(countJitter: v)),
                  ),
                  section(l.transfer, Icons.opacity_rounded),
                  slider(
                    l.opacity,
                    settings.opacity,
                    0.02,
                    1,
                    1,
                    (v) => settings.opacity = v,
                  ),
                  slider(
                    l.flow,
                    t.flow,
                    0.01,
                    1,
                    1,
                    (v) => set(t.copyWith(flow: v)),
                  ),
                  slider(
                    l.flowJitter,
                    t.flowJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(flowJitter: v)),
                  ),
                  toggle(
                    l.opacityFromPressure,
                    t.pressureOpacity,
                    (v) => set(t.copyWith(pressureOpacity: v)),
                  ),
                  section(l.colorDynamics, Icons.palette_outlined),
                  slider(
                    l.hueJitter,
                    t.hueJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(hueJitter: v)),
                  ),
                  slider(
                    l.saturationJitter,
                    t.saturationJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(saturationJitter: v)),
                  ),
                  slider(
                    l.brightnessJitter,
                    t.brightnessJitter,
                    0,
                    1,
                    0,
                    (v) => set(t.copyWith(brightnessJitter: v)),
                  ),
                  section(l.smoothing, Icons.gesture_rounded),
                  slider(
                    l.smoothing,
                    settings.smoothing,
                    0,
                    1,
                    0.5,
                    (v) => settings.smoothing = v,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShapeChip extends StatelessWidget {
  const _ShapeChip({
    required this.shape,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final TipShape shape;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 70,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CustomPaint(
                  painter: _TipPreview(
                    shape,
                    selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? scheme.primary : null,
                  fontWeight: selected ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipPreview extends CustomPainter {
  _TipPreview(this.shape, this.color);
  final TipShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintBrushStroke(
      canvas,
      BrushStroke(
        points: [size.center(Offset.zero)],
        type: BrushType.round,
        color: color,
        width: size.shortestSide * 0.95,
        tip: BrushTip(shape: shape),
      ),
    );
  }

  @override
  bool shouldRepaint(_TipPreview old) =>
      old.shape != shape || old.color != color;
}

/// A sample S-curve drawn with the current brush, pressure easing in and
/// out as a real stroke would.
class BrushStrokePreview extends CustomPainter {
  BrushStrokePreview(this.settings) : super(repaint: settings);
  final BrushSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 48;
    final w = math.min(settings.size, size.height * 0.45);
    final pts = <Offset>[
      for (var i = 0; i <= n; i++)
        Offset(
          w + (size.width - 2 * w) * i / n,
          size.height / 2 +
              (size.height / 2 - w * 0.6 - 4) * math.sin(i / n * 2 * math.pi),
        ),
    ];
    final pressures = [
      for (var i = 0; i <= n; i++) 0.35 + 0.65 * math.sin(i / n * math.pi),
    ];
    final s = settings.stroke(pts, 1, 11, pressures);
    paintBrushStroke(
      canvas,
      BrushStroke(
        points: s.points,
        type: s.type,
        color: settings.color,
        width: w,
        opacity: settings.opacity,
        softness: s.softness,
        seed: 11,
        tip: s.tip,
        pressures: s.pressures,
      ),
    );
  }

  @override
  bool shouldRepaint(BrushStrokePreview old) => true;
}
