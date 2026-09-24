import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_theme.dart';
import '../../../document/model/layer.dart';
import '../../../document/render/brush_paint.dart';
import '../../../editor/tools/draw_tool.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';
import '../../../ui/widgets/pix_slider.dart';
import '../../../ui/widgets/pressable.dart';

String brushLabel(AppLocalizations l, BrushType t) => switch (t) {
  BrushType.pen => l.brushPen,
  BrushType.pencil => l.brushPencil,
  BrushType.marker => l.brushMarker,
  BrushType.highlighter => l.brushHighlighter,
  BrushType.airbrush => l.brushAirbrush,
  BrushType.calligraphy => l.brushCalligraphy,
  BrushType.spray => l.brushSpray,
  BrushType.neon => l.brushNeon,
};

/// Freehand drawing: brush tips with live previews, draw / erase, size,
/// opacity, softness, stabilizer and colour. One finger draws on the
/// canvas, two fingers pan and zoom.
class BrushPanel extends StatelessWidget {
  const BrushPanel({super.key, required this.settings, required this.onDone});
  final BrushSettings settings;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final b = settings;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.brush_rounded, size: 18),
                    label: Text(l.draw),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.auto_fix_normal_rounded, size: 18),
                    label: Text(l.eraser),
                  ),
                ],
                selected: {b.eraser},
                onSelectionChanged: (v) {
                  HapticFeedback.selectionClick();
                  b.eraser = v.first;
                },
              ),
            ),
            SizedBox(
              height: 86,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final t in BrushType.values)
                    _BrushTile(
                      type: t,
                      label: brushLabel(l, t),
                      color: b.color,
                      selected: !b.eraser && b.type == t,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        b.type = t;
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ColorStrip(
              value: b.color,
              onChanged: (c, {required live}) {
                if (c != null) b.color = c;
              },
            ),
            PixSlider(
              label: l.brushSize,
              value: b.size,
              min: 1,
              max: 200,
              defaultValue: 12,
              onChanged: (v) => b.size = v,
            ),
            if (!b.eraser)
              PixSlider(
                label: l.opacity,
                value: b.opacity,
                min: 0.02,
                max: 1,
                defaultValue: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => b.opacity = v,
              ),
            PixSlider(
              label: l.softness,
              value: b.softness,
              min: 0,
              max: 1,
              defaultValue: 0,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => b.softness = v,
            ),
            PixSlider(
              label: l.smoothing,
              value: b.smoothing,
              min: 0,
              max: 1,
              defaultValue: 0.5,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => b.smoothing = v,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Text(
                l.drawHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: onDone,
                icon: const Icon(Icons.check_rounded),
                label: Text(l.done),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BrushTile extends StatelessWidget {
  const _BrushTile({
    required this.type,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final BrushType type;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: PixTokens.fast,
          width: 84,
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(PixTokens.radiusM),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Column(
            children: [
              SizedBox(
                height: 40,
                width: 72,
                child: CustomPaint(
                  painter: _BrushPreview(
                    type,
                    color.computeLuminance() > 0.8
                        ? const Color(0xFF111827)
                        : color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
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

/// A sample S-curve drawn with the brush.
class _BrushPreview extends CustomPainter {
  _BrushPreview(this.type, this.color);
  final BrushType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      for (var i = 0; i <= 32; i++)
        Offset(
          6 + (size.width - 12) * i / 32,
          size.height / 2 + size.height * 0.26 * math.sin(i / 32 * 2 * math.pi),
        ),
    ];
    paintBrushStroke(
      canvas,
      BrushStroke(
        points: pts,
        type: type,
        color: color,
        width: type == BrushType.highlighter ? 8 : 6,
        seed: 7,
      ),
    );
  }

  @override
  bool shouldRepaint(_BrushPreview old) =>
      old.type != type || old.color != color;
}
