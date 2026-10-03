import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui/widgets/color_picker.dart';

/// Patterns for the area around the canvas, as in Figma, Canva and
/// Procreate's workspace backgrounds.
enum PasteboardPattern {
  plain,
  dots,
  grid,
  lines,
  checker;

  static PasteboardPattern of(String name) => values.firstWhere(
    (p) => p.name == name,
    orElse: () => PasteboardPattern.plain,
  );

  String label(AppLocalizations l) => switch (this) {
    plain => l.patternPlain,
    dots => l.patternDots,
    grid => l.patternGrid,
    lines => l.patternLines,
    checker => l.patternChecker,
  };
}

/// Paints [pattern] over [area] in a tone that suits [base]; [origin] is
/// where the canvas sits, so the pattern moves with it when panning, and
/// [step] the spacing on screen.
void paintPasteboardPattern(
  Canvas canvas,
  Rect area,
  PasteboardPattern pattern,
  Color base, {
  Offset origin = Offset.zero,
  double step = 22,
}) {
  if (pattern == PasteboardPattern.plain) return;
  final ink = base.computeLuminance() > 0.45
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
  double start(double from, double o) =>
      from - ((from - o) % step + step) % step;
  final x0 = start(area.left, origin.dx), y0 = start(area.top, origin.dy);
  switch (pattern) {
    case PasteboardPattern.plain:
      break;
    case PasteboardPattern.dots:
      final p = Paint()..color = ink.withValues(alpha: 0.16);
      for (var y = y0; y <= area.bottom; y += step) {
        for (var x = x0; x <= area.right; x += step) {
          canvas.drawCircle(Offset(x, y), 1.4, p);
        }
      }
    case PasteboardPattern.grid:
      final p = Paint()
        ..color = ink.withValues(alpha: 0.08)
        ..strokeWidth = 1;
      for (var x = x0; x <= area.right; x += step) {
        canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), p);
      }
      for (var y = y0; y <= area.bottom; y += step) {
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), p);
      }
    case PasteboardPattern.lines:
      final p = Paint()
        ..color = ink.withValues(alpha: 0.07)
        ..strokeWidth = 1.2;
      canvas
        ..save()
        ..clipRect(area);
      final h = area.height;
      for (var x = x0 - h; x <= area.right; x += step) {
        canvas.drawLine(Offset(x, area.bottom), Offset(x + h, area.top), p);
      }
      canvas.restore();
    case PasteboardPattern.checker:
      final p = Paint()..color = ink.withValues(alpha: 0.05);
      var row = ((y0 - origin.dy) / step).round();
      for (var y = y0; y <= area.bottom; y += step, row++) {
        var col = ((x0 - origin.dx) / step).round();
        for (var x = x0; x <= area.right; x += step, col++) {
          if ((row + col).isEven) {
            canvas.drawRect(Rect.fromLTWH(x, y, step, step), p);
          }
        }
      }
  }
}

/// The pasteboard's settings: colour, pattern and whether layers moved
/// off the canvas stay there (opened by a long press outside the canvas).
Future<void> showPasteboardSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PasteboardSheet(),
    );

class _PasteboardSheet extends StatelessWidget {
  const _PasteboardSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final pattern = PasteboardPattern.of(settings.pasteboardPattern);
        final color = settings.pasteboardColor;
        final shown = color ?? PixColors.of(context).canvasBackdrop;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                  child: Text(l.pasteboard, style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    l.pasteboardHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.pasteboardColor,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (color != null)
                        TextButton.icon(
                          onPressed: () => settings.pasteboardColor = null,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: Text(l.useDefault),
                        ),
                    ],
                  ),
                ),
                ColorStrip(
                  value: color,
                  onChanged: (c, {required live}) {
                    if (c != null) settings.pasteboardColor = c;
                  },
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l.pasteboardPattern,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 92,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final p in PasteboardPattern.values)
                        _PatternTile(
                          pattern: p,
                          base: shown,
                          label: p.label(l),
                          selected: p == pattern,
                          onTap: () => settings.pasteboardPattern = p.name,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  secondary: const Icon(Icons.layers_outlined),
                  title: Text(l.pasteboardLayers),
                  subtitle: Text(l.pasteboardLayersHint),
                  value: settings.pasteboardLayers,
                  onChanged: (v) => settings.pasteboardLayers = v,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.pattern,
    required this.base,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final PasteboardPattern pattern;
  final Color base;
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
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 68,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: CustomPaint(
                  painter: _PatternPreview(pattern, base),
                  child: selected
                      ? Center(
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: scheme.primary,
                            size: 22,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

class _PatternPreview extends CustomPainter {
  _PatternPreview(this.pattern, this.base);
  final PasteboardPattern pattern;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = base);
    paintPasteboardPattern(canvas, r, pattern, base, step: 12);
  }

  @override
  bool shouldRepaint(_PatternPreview old) =>
      old.pattern != pattern || old.base != base;
}
