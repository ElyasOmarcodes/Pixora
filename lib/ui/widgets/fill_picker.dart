import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../core/colors/recent_colors.dart';
import '../../document/model/fill.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/canvas_presets.dart';
import 'color_picker.dart';
import 'gradient_editor.dart';
import 'pix_slider.dart';
import 'pressable.dart';

/// The one colour control used across the app: a "Solid | Gradient"
/// switch (solid by default), then a row that starts with "+" (custom
/// colour or new gradient), the 20 most recently used colours/gradients
/// and the built-in ones.
class FillPicker extends StatefulWidget {
  const FillPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowTransparent = false,
    this.aspect = 1,
  });

  final PixFill? value;
  final void Function(PixFill? fill, {required bool live}) onChanged;
  final bool allowTransparent;

  /// Width / height of what is painted (for the gradient editor preview).
  final double aspect;

  @override
  State<FillPicker> createState() => _FillPickerState();
}

class _FillPickerState extends State<FillPicker> {
  late bool _gradient = widget.value?.isGradient ?? false;

  void _apply(PixFill f) {
    HapticFeedback.selectionClick();
    RecentColors.instance.addGradient(f);
    widget.onChanged(f, live: false);
  }

  Future<void> _edit({bool fresh = false}) async {
    final v = widget.value;
    final seed = !fresh && v != null && v.isGradient
        ? v
        : PixFill.linear([
            v?.primary ?? const Color(0xFF3D7BFF),
            Color.lerp(
              v?.primary ?? const Color(0xFF3D7BFF),
              Colors.white,
              0.75,
            )!,
          ], angle: 90);
    final f = await showGradientEditor(
      context,
      initial: seed,
      aspect: widget.aspect,
    );
    if (f != null) _apply(f);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final v = widget.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.circle, size: 16),
                label: Text(l.oneColor),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.gradient_rounded, size: 18),
                label: Text(l.gradient),
              ),
            ],
            selected: {_gradient},
            onSelectionChanged: (s) => setState(() => _gradient = s.first),
          ),
        ),
        if (!_gradient)
          ColorStrip(
            value: v == null || v.isGradient ? null : v.primary,
            allowTransparent: widget.allowTransparent,
            onChanged: (c, {required live}) => widget.onChanged(
              c == null ? null : PixFill.color(c),
              live: live,
            ),
          )
        else ...[
          SizedBox(
            height: 56,
            child: ListenableBuilder(
              listenable: RecentColors.instance,
              builder: (context, _) {
                final recent = RecentColors.instance.gradients;
                final presets = [
                  for (final g in kBackgroundGradients)
                    PixFill.linear(g, angle: 90),
                ];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _Tile(
                      selected: false,
                      onTap: () => _edit(fresh: true),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.add_rounded, color: scheme.primary),
                      ),
                    ),
                    if (v != null && v.isGradient)
                      _Tile(
                        selected: false,
                        onTap: _edit,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(painter: FillSwatchPainter(v)),
                            const Center(
                              child: Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 18,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    for (final g in recent)
                      _Tile(
                        selected: g == v,
                        onTap: () => _apply(g),
                        child: CustomPaint(painter: FillSwatchPainter(g)),
                      ),
                    if (recent.isNotEmpty)
                      Center(
                        child: Container(
                          width: 1.5,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: scheme.outlineVariant,
                        ),
                      ),
                    for (final g in presets)
                      _Tile(
                        selected:
                            v != null &&
                            v.isGradient &&
                            v.colors.length == g.colors.length &&
                            v.colors.first == g.colors.first &&
                            v.colors.last == g.colors.last,
                        onTap: () => _apply(
                          v != null && v.isGradient
                              ? v.copyWith(colors: g.colors, clearStops: true)
                              : g,
                        ),
                        child: CustomPaint(painter: FillSwatchPainter(g)),
                      ),
                  ],
                );
              },
            ),
          ),
          if (v != null && v.isGradient && v.kind != FillKind.radial)
            PixSlider(
              label: l.angle,
              value: v.angle % 360,
              min: 0,
              max: 360,
              defaultValue: 90,
              format: (x) => '${x.round()}°',
              onChanged: (x) =>
                  widget.onChanged(v.copyWith(angle: x), live: true),
              onChangeEnd: (x) =>
                  widget.onChanged(v.copyWith(angle: x), live: false),
            ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.child,
    required this.selected,
    required this.onTap,
  });
  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Pressable(
      scale: 0.9,
      onTap: onTap,
      child: AnimatedContainer(
        duration: PixTokens.fast,
        width: 48,
        height: 48,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: child,
      ),
    );
  }
}
