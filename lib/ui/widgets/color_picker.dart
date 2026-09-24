import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../core/colors/recent_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../projects/canvas_presets.dart';
import 'checkerboard.dart';
import 'pix_slider.dart';
import 'pressable.dart';

/// Where the eyedropper reads colours from: the editor registers a
/// function that renders the current design.
abstract final class Eyedropper {
  static Future<ui.Image?> Function()? capture;

  static bool get available => capture != null;
}

String hexOf(Color c, {bool alpha = false}) {
  final v = c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  return alpha ? v : v.substring(2);
}

/// A horizontal row of swatches: "+" (custom colour), the eyedropper,
/// optionally "none", the last 20 colours used anywhere in the app, then
/// the built-in palette.
///
/// [onChanged] receives `live = true` while the user drags inside the custom
/// picker and `live = false` for final choices, so callers can map these to
/// preview/commit. Final choices are remembered as recent colours.
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

  void _final(Color? c) {
    if (c != null) RecentColors.instance.addColor(c);
    onChanged(c, live: false);
  }

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: RecentColors.instance,
      builder: (context, _) {
        final recent = RecentColors.instance.colors;
        final recentSet = {for (final c in recent) c.toARGB32()};
        Widget swatch(Color c) => _Swatch(
          selected: value?.toARGB32() == c.toARGB32(),
          onTap: () => _final(c),
          child: _ColorDot(c),
        );
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
                  _final(picked ?? last);
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
              if (Eyedropper.available)
                _Swatch(
                  selected: false,
                  onTap: () async {
                    final c = await pickColorFromCanvas(context);
                    if (c != null) _final(c);
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.onSurface.withValues(alpha: 0.07),
                    ),
                    child: Icon(
                      Icons.colorize_rounded,
                      size: 20,
                      color: scheme.onSurface,
                    ),
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
              for (final c in recent) swatch(c),
              if (recent.isNotEmpty)
                Center(
                  child: Container(
                    width: 1.5,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: scheme.outlineVariant,
                  ),
                ),
              for (final c in kSwatches)
                if (!recentSet.contains(c.toARGB32())) swatch(c),
            ],
          ),
        );
      },
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.c);
  final Color c;

  @override
  Widget build(BuildContext context) {
    final pix = PixColors.of(context);
    return ClipOval(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (c.a < 1)
            CheckerboardBox(a: pix.checkerA, b: pix.checkerB, cell: 5),
          DecoratedBox(
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
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

/// The advanced colour picker: saturation/brightness square, hue and
/// opacity bars, HEX, RGB / HSV / HSL sliders with exact values, the
/// eyedropper, recent colours and the palette. Returns the chosen colour,
/// or null if dismissed.
Future<Color?> showPixColorPicker(
  BuildContext context, {
  required Color initial,
  ValueChanged<Color>? onLive,
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(initial: initial, onLive: onLive),
  );
}

enum _Model { rgb, hsv, hsl }

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
    text: hexOf(widget.initial),
  );
  _Model _model = _Model.rgb;

  void _set(HSVColor hsv, {bool updateHex = true}) {
    setState(() => _hsv = hsv);
    if (updateHex) _hex.text = hexOf(hsv.toColor());
    widget.onLive?.call(hsv.toColor());
  }

  void _setColor(Color c) =>
      _set(HSVColor.fromColor(c.withValues(alpha: _hsv.alpha)));

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Future<void> _eyedrop() async {
    final c = await pickColorFromCanvas(context);
    if (c != null) _set(HSVColor.fromColor(c).withAlpha(_hsv.alpha));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pix = PixColors.of(context);
    final color = _hsv.toColor();

    Widget sliders() {
      switch (_model) {
        case _Model.rgb:
          final r = (color.r * 255).round(),
              g = (color.g * 255).round(),
              b = (color.b * 255).round();
          Color rgb(int r, int g, int b) =>
              Color.fromARGB((_hsv.alpha * 255).round(), r, g, b);
          return Column(
            children: [
              PixSlider(
                label: 'R',
                value: r.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) =>
                    _set(HSVColor.fromColor(rgb(v.round(), g, b))),
              ),
              PixSlider(
                label: 'G',
                value: g.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) =>
                    _set(HSVColor.fromColor(rgb(r, v.round(), b))),
              ),
              PixSlider(
                label: 'B',
                value: b.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) =>
                    _set(HSVColor.fromColor(rgb(r, g, v.round()))),
              ),
            ],
          );
        case _Model.hsv:
          return Column(
            children: [
              PixSlider(
                label: 'H',
                value: _hsv.hue,
                min: 0,
                max: 360,
                format: (v) => '${v.round()}°',
                onChanged: (v) => _set(_hsv.withHue(v)),
              ),
              PixSlider(
                label: 'S',
                value: _hsv.saturation,
                min: 0,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _set(_hsv.withSaturation(v)),
              ),
              PixSlider(
                label: 'V',
                value: _hsv.value,
                min: 0,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => _set(_hsv.withValue(v)),
              ),
            ],
          );
        case _Model.hsl:
          final hsl = HSLColor.fromColor(color);
          void setHsl(HSLColor h) =>
              _set(HSVColor.fromColor(h.toColor()).withAlpha(_hsv.alpha));
          return Column(
            children: [
              PixSlider(
                label: 'H',
                value: hsl.hue,
                min: 0,
                max: 360,
                format: (v) => '${v.round()}°',
                onChanged: (v) => setHsl(hsl.withHue(v)),
              ),
              PixSlider(
                label: 'S',
                value: hsl.saturation,
                min: 0,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setHsl(hsl.withSaturation(v)),
              ),
              PixSlider(
                label: 'L',
                value: hsl.lightness,
                min: 0,
                max: 1,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) => setHsl(hsl.withLightness(v)),
              ),
            ],
          );
      }
    }

    Widget miniSwatch(Color c) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkResponse(
        radius: 20,
        onTap: () {
          HapticFeedback.selectionClick();
          _setColor(c);
        },
        child: SizedBox(width: 30, height: 30, child: _ColorDot(c)),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: SingleChildScrollView(
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
            // Before / after, HEX, eyedropper and Done.
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PixTokens.radiusS),
                  child: SizedBox(
                    width: 64,
                    height: 44,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CheckerboardBox(
                          a: pix.checkerA,
                          b: pix.checkerB,
                          cell: 6,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    _set(HSVColor.fromColor(widget.initial)),
                                child: ColoredBox(
                                  color: widget.initial,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ColoredBox(
                                color: color,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _hex,
                      maxLength: 8,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9a-fA-F]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        prefixText: '# ',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: scheme.onSurface.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (t) {
                        if (t.length == 6) {
                          final v = int.parse('FF$t', radix: 16);
                          _set(
                            HSVColor.fromColor(Color(v)).withAlpha(_hsv.alpha),
                            updateHex: false,
                          );
                        } else if (t.length == 8) {
                          // AARRGGBB
                          _set(
                            HSVColor.fromColor(Color(int.parse(t, radix: 16))),
                            updateHex: false,
                          );
                        }
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l.copy,
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: '#${hexOf(color)}'),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                ),
                if (Eyedropper.available)
                  IconButton.filledTonal(
                    tooltip: l.eyedropper,
                    onPressed: _eyedrop,
                    icon: const Icon(Icons.colorize_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 1.8,
              child: _SvArea(hsv: _hsv, onChanged: _set),
            ),
            const SizedBox(height: 16),
            _HueBar(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 14),
            _AlphaBar(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 12),
            SegmentedButton<_Model>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: _Model.rgb, label: Text('RGB')),
                ButtonSegment(value: _Model.hsv, label: Text('HSB')),
                ButtonSegment(value: _Model.hsl, label: Text('HSL')),
              ],
              selected: {_model},
              onSelectionChanged: (s) => setState(() => _model = s.first),
            ),
            const SizedBox(height: 4),
            sliders(),
            PixSlider(
              label: l.opacity,
              value: _hsv.alpha,
              min: 0,
              max: 1,
              format: (v) => '${(v * 100).round()}%',
              onChanged: (v) => _set(_hsv.withAlpha(v)),
            ),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: RecentColors.instance,
              builder: (context, _) {
                final recent = RecentColors.instance.colors;
                return SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final c in recent) miniSwatch(c),
                      if (recent.isNotEmpty)
                        Container(
                          width: 1.5,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          color: scheme.outlineVariant,
                        ),
                      for (final c in kSwatches) miniSwatch(c),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              onPressed: () => Navigator.pop(context, color),
              icon: const Icon(Icons.check_rounded),
              label: Text(l.done),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user pick a colour from the current design with a magnifying
/// loupe. Returns null when cancelled or when there is nothing to sample.
Future<Color?> pickColorFromCanvas(BuildContext context) async {
  final capture = Eyedropper.capture;
  if (capture == null) return null;
  final image = await capture();
  if (image == null || !context.mounted) return null;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null || !context.mounted) return null;
  return Navigator.of(context).push<Color>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _EyedropperPage(image: image, pixels: data),
    ),
  );
}

class _EyedropperPage extends StatefulWidget {
  const _EyedropperPage({required this.image, required this.pixels});
  final ui.Image image;
  final ByteData pixels;

  @override
  State<_EyedropperPage> createState() => _EyedropperPageState();
}

class _EyedropperPageState extends State<_EyedropperPage> {
  late Offset _px = Offset(widget.image.width / 2, widget.image.height / 2);
  Offset? _finger;

  Color _at(Offset p) {
    final img = widget.image;
    final x = p.dx.floor().clamp(0, img.width - 1);
    final y = p.dy.floor().clamp(0, img.height - 1);
    final i = (y * img.width + x) * 4;
    final d = widget.pixels;
    return Color.fromARGB(
      d.getUint8(i + 3),
      d.getUint8(i),
      d.getUint8(i + 1),
      d.getUint8(i + 2),
    );
  }

  Rect _fit(Size box) {
    final img = widget.image;
    final s = math.min(box.width / img.width, box.height / img.height);
    final w = img.width * s, h = img.height * s;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _move(Offset local, Rect r) {
    final img = widget.image;
    final p = Offset(
      ((local.dx - r.left) / r.width * img.width).clamp(0, img.width - 1),
      ((local.dy - r.top) / r.height * img.height).clamp(0, img.height - 1),
    );
    HapticFeedback.selectionClick();
    setState(() {
      _px = p;
      _finger = local;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = _at(_px);
    return Scaffold(
      backgroundColor: const Color(0xFF15161A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15161A),
        foregroundColor: Colors.white,
        title: Text(
          l.eyedropper,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final box = c.biggest;
                  final r = _fit(box);
                  final at =
                      _finger ??
                      Offset(
                        r.left + _px.dx / widget.image.width * r.width,
                        r.top + _px.dy / widget.image.height * r.height,
                      );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanDown: (d) => _move(d.localPosition, r),
                    onPanUpdate: (d) => _move(d.localPosition, r),
                    child: CustomPaint(
                      size: box,
                      painter: _LoupePainter(
                        image: widget.image,
                        rect: r,
                        at: at,
                        px: _px,
                        color: color,
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: const Color(0xFF1E2026),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '#${hexOf(color)}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: () => Navigator.pop(context, color),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l.apply),
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

class _LoupePainter extends CustomPainter {
  _LoupePainter({
    required this.image,
    required this.rect,
    required this.at,
    required this.px,
    required this.color,
  });
  final ui.Image image;
  final Rect rect;
  final Offset at;
  final Offset px;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // Loupe above the finger: 11×11 pixels magnified.
    const r = 64.0;
    var c = at - const Offset(0, 96);
    if (c.dy - r < 0) c = at + const Offset(0, 96);
    final clip = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    canvas
      ..save()
      ..clipPath(clip);
    const n = 11.0;
    canvas.drawImageRect(
      image,
      Rect.fromCenter(center: px, width: n, height: n),
      Rect.fromCircle(center: c, radius: r),
      Paint()..filterQuality = FilterQuality.none,
    );
    const cell = r * 2 / n;
    canvas
      ..drawRect(
        Rect.fromCenter(center: c, width: cell, height: cell),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      )
      ..restore()
      ..drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = color,
      )
      ..drawCircle(
        c,
        r + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      )
      ..drawCircle(
        at,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
  }

  @override
  bool shouldRepaint(_LoupePainter old) =>
      old.at != at || old.px != px || old.rect != rect;
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
