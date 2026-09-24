import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/canvas_presets.dart';
import 'checkerboard.dart';
import 'pressable.dart';

/// A horizontal row of swatches with a "custom color" button in front.
///
/// [onChanged] receives `live = true` while the user drags inside the custom
/// picker and `live = false` for final choices, so callers can map these to
/// preview/commit.
class ColorStrip extends StatelessWidget {
  const ColorStrip({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowTransparent = false,
  });

  final Color? value;
  final void Function(Color? color, {required bool live}) onChanged;
  final bool allowTransparent;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Swatch(
            selected: false,
            onTap: () async {
              Color? last;
              final picked = await showPixColorPicker(
                context,
                initial: value ?? Colors.white,
                onLive: (c) => onChanged(last = c, live: true),
              );
              // Swiping the sheet away keeps what was picked so far.
              final result = picked ?? last;
              if (result != null) onChanged(result, live: false);
            },
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ],
                ),
              ),
              child: Icon(Icons.add_rounded, color: Colors.white, size: 20),
            ),
          ),
          if (allowTransparent)
            _Swatch(
              selected: value == null,
              onTap: () => onChanged(null, live: false),
              child: ClipOval(
                child: CheckerboardBox(
                  a: pix.checkerA,
                  b: pix.checkerB,
                  cell: 6,
                ),
              ),
            ),
          for (final c in kSwatches)
            _Swatch(
              selected: value?.toARGB32() == c.toARGB32(),
              onTap: () => onChanged(c, live: false),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
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
      onTap: onTap,
      scale: 0.88,
      child: AnimatedContainer(
        duration: PixTokens.fast,
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: EdgeInsets.all(selected ? 4 : 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
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

/// Shows an HSV color picker. Returns the chosen color, or null if dismissed.
Future<Color?> showPixColorPicker(
  BuildContext context, {
  required Color initial,
  ValueChanged<Color>? onLive,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PickerSheet(initial: initial, onLive: onLive),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.initial, this.onLive});
  final Color initial;
  final ValueChanged<Color>? onLive;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );

  static String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  void _set(HSVColor hsv, {bool updateHex = true}) {
    setState(() => _hsv = hsv);
    if (updateHex) _hex.text = _hexOf(hsv.toColor());
    widget.onLive?.call(hsv.toColor());
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _hsv.toColor();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.6,
            child: _SvArea(hsv: _hsv, onChanged: _set),
          ),
          const SizedBox(height: 18),
          _HueBar(hsv: _hsv, onChanged: _set),
          const SizedBox(height: 18),
          _AlphaBar(hsv: _hsv, onChanged: _set),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(PixTokens.radiusS),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: _hex,
                    maxLength: 6,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    ],
                    decoration: const InputDecoration(
                      prefixText: '#  ',
                      counterText: '',
                    ),
                    onChanged: (t) {
                      if (t.length == 6) {
                        final v = int.parse('FF$t', radix: 16);
                        _set(
                          HSVColor.fromColor(Color(v)).withAlpha(_hsv.alpha),
                          updateHex: false,
                        );
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, color),
                child: Text(l.done),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SvArea extends StatelessWidget {
  const _SvArea({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset p, Size s) {
    onChanged(
      hsv
          .withSaturation((p.dx / s.width).clamp(0.0, 1.0))
          .withValue(1 - (p.dy / s.height).clamp(0.0, 1.0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.biggest;
        return GestureDetector(
          onPanDown: (d) => _handle(d.localPosition, size),
          onPanUpdate: (d) => _handle(d.localPosition, size),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PixTokens.radiusM),
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white,
                        HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                      ],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * size.width - 12,
                  top: (1 - hsv.value) * size.height - 12,
                  child: _Knob(color: hsv.toColor().withValues(alpha: 1)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.t,
    required this.onChanged,
    required this.background,
    required this.knob,
  });
  final double t;
  final ValueChanged<double> onChanged;
  final Widget background;
  final Color knob;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          void h(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0));
          return GestureDetector(
            onPanDown: (d) => h(d.localPosition),
            onPanUpdate: (d) => h(d.localPosition),
            child: SizedBox(
              height: 28,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 4,
                    bottom: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: background,
                    ),
                  ),
                  Positioned(
                    left: t * w - 14,
                    top: 0,
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: _Knob(color: knob),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => _Bar(
    t: hsv.hue / 360,
    knob: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
    onChanged: (t) => onChanged(hsv.withHue(t * 360)),
    background: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            for (var i = 0; i <= 6; i++)
              HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
          ],
        ),
      ),
    ),
  );
}

class _AlphaBar extends StatelessWidget {
  const _AlphaBar({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    final c = hsv.toColor().withValues(alpha: 1);
    return _Bar(
      t: hsv.alpha,
      knob: hsv.toColor(),
      onChanged: (t) => onChanged(hsv.withAlpha(t)),
      background: Stack(
        fit: StackFit.expand,
        children: [
          CheckerboardBox(a: pix.checkerA, b: pix.checkerB, cell: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.withValues(alpha: 0), c]),
            ),
          ),
        ],
      ),
    );
  }
}
