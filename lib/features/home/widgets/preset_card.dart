import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../projects/canvas_presets.dart';
import '../../../ui/widgets/soft_card.dart';

const double _cardWidth = 118;

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    child: SizedBox(width: _cardWidth, child: child),
  );
}

/// A canvas-size preset with a proportional preview of its shape.
class PresetCard extends StatelessWidget {
  const PresetCard({
    super.key,
    required this.preset,
    required this.label,
    required this.onTap,
  });

  final CanvasPreset preset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const box = 62.0;
    final a = preset.aspect;
    final w = a >= 1 ? box : box * a;
    final h = a >= 1 ? box / a : box;
    return _CardFrame(
      child: SoftCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: math.max(w, 18),
                    height: math.max(h, 18),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.55),
                        width: 1.6,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(preset.icon, size: 20, color: scheme.primary),
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${preset.width.round()} × ${preset.height.round()}',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The highlighted "open a photo" entry.
class PhotoCard extends StatelessWidget {
  const PhotoCard({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hsl = HSLColor.fromColor(scheme.primary);
    return _CardFrame(
      child: SoftCard(
        onTap: onTap,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            hsl.withHue((hsl.hue + 330) % 360).withLightness(0.62).toColor(),
            scheme.primary,
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(PixTokens.radiusM),
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomSizeCard extends StatelessWidget {
  const CustomSizeCard({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardFrame(
      child: SoftCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.aspect_ratio_rounded,
                    size: 34,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
